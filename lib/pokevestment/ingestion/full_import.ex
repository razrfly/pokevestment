defmodule Pokevestment.Ingestion.FullImport do
  @moduledoc """
  Orchestrates full data import from TCGdex and PokeAPI in FK dependency order:
  series -> sets -> species -> cards.

  Note: `language_count` on cards is NOT populated during import because it requires
  cross-language API data (6 Western TCGdex endpoints, range 1–6). Japanese is excluded
  due to incompatible card ID schemes. After running the full import, run:

      mix pokevestment.backfill_language_counts
  """

  require Logger

  import Ecto.Query
  import Pokevestment.Helpers, only: [format_duration: 1]

  alias Pokevestment.Repo
  alias Pokevestment.Api.{Tcgdex, PokeApi}
  alias Pokevestment.Ingestion.Transformer
  alias Pokevestment.Cards.{Series, Set, Card, CardType, CardDexId}
  alias Pokevestment.Pokemon.Species
  alias Pokevestment.Pricing.PriceSnapshot

  @doc "Run full import in FK dependency order."
  def run do
    start = System.monotonic_time(:millisecond)
    Logger.info("Starting full import...")

    with {:ok, series_count} <- import_series(),
         {:ok, sets_count} <- import_sets(),
         {:ok, species_count} <- import_species(),
         {:ok, cards_result} <- import_cards() do
      elapsed = System.monotonic_time(:millisecond) - start
      Logger.info("Full import complete in #{format_duration(elapsed)}")

      Logger.info(
        "Series: #{series_count}, Sets: #{sets_count}, Species: #{species_count}, Cards: #{cards_result.imported}"
      )

      if cards_result.failed != [] do
        Logger.warning("Failed card IDs: #{Enum.join(cards_result.failed, ", ")}")
      end

      {:ok,
       %{series: series_count, sets: sets_count, species: species_count, cards: cards_result}}
    end
  end

  @doc "Import all series from TCGdex (~21 rows)."
  def import_series do
    Logger.info("Importing series...")
    start = System.monotonic_time(:millisecond)

    with {:ok, raw_series} <- Tcgdex.list_series() do
      count =
        Enum.reduce(raw_series, 0, fn raw, acc ->
          attrs = Transformer.series_attrs(raw)

          %Series{}
          |> Series.changeset(attrs)
          |> Repo.insert(on_conflict: :replace_all, conflict_target: [:id])
          |> case do
            {:ok, _} ->
              acc + 1

            {:error, changeset} ->
              Logger.warning(
                "Failed to upsert series #{attrs[:id]}: #{inspect(changeset.errors)}"
              )

              acc
          end
        end)

      elapsed = System.monotonic_time(:millisecond) - start
      Logger.info("Imported #{count} series in #{format_duration(elapsed)}")
      {:ok, count}
    end
  end

  @doc "Import all sets from TCGdex (~200 rows). Fetches list then details concurrently."
  def import_sets do
    Logger.info("Importing sets...")
    start = System.monotonic_time(:millisecond)

    with {:ok, raw_sets} <- Tcgdex.list_sets() do
      set_ids = Enum.map(raw_sets, & &1["id"])
      Logger.info("Fetching details for #{length(set_ids)} sets...")

      {count, failed} =
        set_ids
        |> Task.async_stream(
          fn id ->
            case Tcgdex.get_set(id) do
              {:ok, raw} -> {:ok, id, Transformer.set_attrs(raw)}
              {:error, reason} -> {:error, id, reason}
            end
          end,
          max_concurrency: 10,
          timeout: 120_000,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Enum.reduce({0, []}, fn
          {:ok, {:ok, _id, attrs}}, {count, failed} ->
            case upsert_set(attrs) do
              {:ok, _} ->
                {count + 1, failed}

              {:error, changeset} ->
                Logger.warning("Failed to upsert set #{attrs[:id]}: #{inspect(changeset.errors)}")

                {count, [attrs[:id] | failed]}
            end

          {:ok, {:error, id, reason}}, {count, failed} ->
            Logger.warning("Failed to fetch set #{id}: #{inspect(reason)}")
            {count, [id | failed]}

          {:exit, reason}, {count, failed} ->
            Logger.warning("Set task crashed: #{inspect(reason)}")
            {count, failed}
        end)

      elapsed = System.monotonic_time(:millisecond) - start
      Logger.info("Imported #{count} sets in #{format_duration(elapsed)}")
      if failed != [], do: Logger.warning("Failed set IDs: #{inspect(failed)}")
      {:ok, count}
    end
  end

  @doc """
  Import all Pokemon species from PokeAPI (1,025 species).

  Two-pass approach for self-referencing FK:
  1. Insert all species with evolves_from_species_id: nil
  2. UPDATE evolution references now that all target rows exist
  """
  def import_species do
    Logger.info("Importing Pokemon species (two-pass)...")
    start = System.monotonic_time(:millisecond)

    # Pass 1: Insert all species with nil evolves_from_species_id
    Logger.info("Pass 1: Inserting 1025 species...")

    {count, evolution_map} =
      1..1025
      |> Task.async_stream(
        fn id ->
          with {:ok, species_raw} <- PokeApi.get_species(id),
               {:ok, pokemon_raw} <- PokeApi.get_pokemon(id) do
            attrs = Transformer.species_attrs(species_raw, pokemon_raw)
            {:ok, id, attrs}
          else
            {:error, reason} -> {:error, id, reason}
          end
        end,
        max_concurrency: 3,
        timeout: 120_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({0, %{}}, fn
        {:ok, {:ok, id, attrs}}, {count, evo_map} ->
          evolves_from = attrs[:evolves_from_species_id]
          insert_attrs = Map.put(attrs, :evolves_from_species_id, nil)

          case upsert_species(insert_attrs) do
            {:ok, _} ->
              evo_map =
                if evolves_from, do: Map.put(evo_map, id, evolves_from), else: evo_map

              new_count = count + 1
              if rem(new_count, 100) == 0, do: Logger.info("  Species inserted: #{new_count}")
              {new_count, evo_map}

            {:error, changeset} ->
              Logger.warning("Failed to insert species #{id}: #{inspect(changeset.errors)}")

              {count, evo_map}
          end

        {:ok, {:error, id, reason}}, {count, evo_map} ->
          Logger.warning("Failed to fetch species #{id}: #{inspect(reason)}")
          {count, evo_map}

        {:exit, reason}, {count, evo_map} ->
          Logger.warning("Species task crashed: #{inspect(reason)}")
          {count, evo_map}
      end)

    # Pass 2: Update evolves_from_species_id
    Logger.info("Pass 2: Updating #{map_size(evolution_map)} evolution references...")

    Enum.each(evolution_map, fn {species_id, evolves_from_id} ->
      from(s in Species, where: s.id == ^species_id)
      |> Repo.update_all(set: [evolves_from_species_id: evolves_from_id])
    end)

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("Imported #{count} species in #{format_duration(elapsed)}")
    {:ok, count}
  end

  @doc """
  Import all cards from TCGdex (~22,755 cards) using set detail responses.

  Creates cards with minimal data from set responses (id, name, local_id,
  set_id, image_url, category). Card detail fields are backfilled later
  when the card detail API endpoint is available.
  """
  def import_cards do
    Logger.info("Importing cards...")
    start = System.monotonic_time(:millisecond)

    species_ids = load_species_ids()
    Logger.info("Loaded #{MapSet.size(species_ids)} species IDs for dex_id validation")

    set_ids = Repo.all(from(s in Set, select: s.id))
    Logger.info("Importing cards from #{length(set_ids)} sets...")

    counter = :counters.new(1, [:atomics])

    {imported, all_failed_acc} =
      set_ids
      |> Task.async_stream(
        fn set_id ->
          case Tcgdex.get_set(set_id) do
            {:ok, %{"cards" => raw_cards}} when is_list(raw_cards) ->
              results =
                Enum.reduce(raw_cards, {0, []}, fn card_entry, {count, fails} ->
                  {card, types, dex_ids, snapshots} =
                    Transformer.card_attrs_minimal(card_entry, set_id)

                  case upsert_card(card, types, dex_ids, snapshots, species_ids) do
                    {:ok, _} ->
                      :counters.add(counter, 1, 1)
                      total = :counters.get(counter, 1)
                      if rem(total, 500) == 0, do: Logger.info("  Cards imported: #{total}")
                      {count + 1, fails}

                    {:error, reason} ->
                      Logger.warning("Failed to upsert card #{card[:id]}: #{inspect(reason)}")
                      {count, [card[:id] | fails]}
                  end
                end)

              {:ok, results}

            {:ok, _} ->
              {:ok, {0, []}}

            {:error, reason} ->
              Logger.warning("Failed to fetch set #{set_id}: #{inspect(reason)}")
              {:ok, {0, []}}
          end
        end,
        max_concurrency: 10,
        timeout: 120_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({0, []}, fn
        {:ok, {:ok, {count, fails}}}, {total, all_failed} ->
          {total + count, [fails | all_failed]}

        {:exit, reason}, {total, all_failed} ->
          Logger.warning("Set card task crashed: #{inspect(reason)}")
          {total, all_failed}
      end)

    failed = all_failed_acc |> Enum.reverse() |> List.flatten()

    elapsed = System.monotonic_time(:millisecond) - start
    Logger.info("Imported #{imported} cards in #{format_duration(elapsed)}")
    if failed != [], do: Logger.warning("#{length(failed)} cards failed")
    {:ok, %{imported: imported, failed: failed, total: imported + length(failed)}}
  end

  # --- Private: Upsert helpers ---

  defp upsert_set(attrs) do
    %Set{}
    |> Set.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:id]
    )
  end

  defp upsert_species(attrs) do
    %Species{}
    |> Species.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: [:id]
    )
  end

  defp upsert_card(card_attrs, type_attrs, dex_id_attrs, snapshot_attrs, species_ids) do
    Repo.transaction(fn ->
      # Upsert the card
      case %Card{}
           |> Card.changeset(card_attrs)
           |> Repo.insert(
             on_conflict: {:replace_all_except, [:id, :inserted_at]},
             conflict_target: [:id]
           ) do
        {:ok, card} ->
          # Delete + reinsert card_types (composite PK — no Ecto upsert)
          from(ct in CardType, where: ct.card_id == ^card.id) |> Repo.delete_all()

          Enum.each(type_attrs, fn attrs ->
            case %CardType{} |> CardType.changeset(attrs) |> Repo.insert() do
              {:ok, _} -> :ok
              {:error, _} -> :ok
            end
          end)

          # Delete + reinsert card_dex_ids (skip FK failures for dex_id > 1025)
          from(cd in CardDexId, where: cd.card_id == ^card.id) |> Repo.delete_all()

          Enum.each(dex_id_attrs, fn attrs ->
            if MapSet.member?(species_ids, attrs[:dex_id]) do
              case %CardDexId{} |> CardDexId.changeset(attrs) |> Repo.insert() do
                {:ok, _} -> :ok
                {:error, _} -> :ok
              end
            else
              Logger.debug(
                "Skipping dex_id #{attrs[:dex_id]} for card #{card.id}: no matching species"
              )
            end
          end)

          # Insert price_snapshots (never overwrite existing for same date)
          Enum.each(snapshot_attrs, fn attrs ->
            %PriceSnapshot{}
            |> PriceSnapshot.changeset(attrs)
            |> Repo.insert(
              on_conflict: :nothing,
              conflict_target: [:card_id, :source, :variant, :snapshot_date]
            )
          end)

          card

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  rescue
    e ->
      Logger.warning("Exception upserting card #{card_attrs[:id]}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc """
  Backfill full card details from TCGdex card detail API.

  Fetches `/cards/{id}` for every card missing rarity data and updates with
  full attributes (rarity, HP, stage, illustrator, types, dex_ids, etc.).
  Uses the same `upsert_card` path as the original import.
  """
  def backfill_card_details do
    Logger.info("Backfilling card details from TCGdex...")
    start = System.monotonic_time(:millisecond)

    species_ids = load_species_ids()
    sets_map = load_sets_map()

    # Only backfill cards missing rarity (i.e. minimal imports)
    card_ids =
      from(c in Card, where: is_nil(c.rarity), select: c.id)
      |> Repo.all()

    total = length(card_ids)
    Logger.info("#{total} cards need detail backfill")

    if total == 0 do
      Logger.info("All cards already have full details")
      {:ok, %{updated: 0, failed: [], total: 0}}
    else
      counter = :counters.new(1, [:atomics])

      # Group cards by set for batch processing
      cards_by_set =
        from(c in Card,
          where: is_nil(c.rarity),
          select: {c.set_id, c.id}
        )
        |> Repo.all()
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

      Logger.info("Cards spread across #{map_size(cards_by_set)} sets")

      {updated, all_fails_acc} =
        cards_by_set
        |> Enum.to_list()
        |> Task.async_stream(
          fn {set_id, set_card_ids} ->
            # Fetch full set detail (includes all card summaries)
            # Then fetch individual card details for cards in this set
            set_data = Map.get(sets_map, set_id, %{})

            Enum.reduce(set_card_ids, {0, []}, fn card_id, {count, fails} ->
              # Use a task with 15s timeout to skip unresponsive cards quickly
              task = Task.async(fn -> Tcgdex.get_card(card_id) end)

              case Task.yield(task, 15_000) || Task.shutdown(task) do
                {:ok, {:ok, card_raw}} ->
                  {card, types, dex_ids, snapshots} =
                    Transformer.card_attrs(card_raw, set_data)

                  case upsert_card(card, types, dex_ids, snapshots, species_ids) do
                    {:ok, _} ->
                      :counters.add(counter, 1, 1)
                      done = :counters.get(counter, 1)

                      if rem(done, 500) == 0 do
                        Logger.info("  Backfilled: #{done}/#{total}")
                      end

                      {count + 1, fails}

                    {:error, reason} ->
                      Logger.warning("Failed to upsert card #{card_id}: #{inspect(reason)}")
                      {count, [card_id | fails]}
                  end

                {:ok, {:error, _reason}} ->
                  {count, [card_id | fails]}

                nil ->
                  # Timed out — skip this card
                  {count, [card_id | fails]}
              end
            end)
          end,
          max_concurrency: 5,
          timeout: :infinity,
          ordered: false
        )
        |> Enum.reduce({0, []}, fn
          {:ok, {count, fails}}, {total_count, all_fails} ->
            {total_count + count, [fails | all_fails]}

          {:exit, reason}, {count, fails} ->
            Logger.warning("Card detail task crashed: #{inspect(reason)}")
            {count, fails}
        end)

      failed = all_fails_acc |> Enum.reverse() |> List.flatten()

      elapsed = System.monotonic_time(:millisecond) - start
      Logger.info("Backfilled #{updated} cards in #{format_duration(elapsed)}")
      if failed != [], do: Logger.warning("#{length(failed)} cards failed backfill")
      {:ok, %{updated: updated, failed: failed, total: total}}
    end
  end

  # --- Private: Data loading ---

  defp load_sets_map do
    from(s in Set, select: {s.id, %{card_count_official: s.card_count_official}})
    |> Repo.all()
    |> Map.new()
  end

  defp load_species_ids do
    from(s in Species, select: s.id)
    |> Repo.all()
    |> MapSet.new()
  end
end
