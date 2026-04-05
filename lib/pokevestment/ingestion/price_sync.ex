defmodule Pokevestment.Ingestion.PriceSync do
  @moduledoc """
  Daily price sync orchestrator — fetches current prices for all cards via
  the Pokemon TCG API (bulk per-set requests) and inserts new PriceSnapshot rows.

  Idempotent: `on_conflict: :nothing` means re-running on the same day
  inserts 0 new rows.
  """

  require Logger

  import Pokevestment.Helpers, only: [format_duration: 1]

  alias Pokevestment.Repo
  alias Pokevestment.Api.PokemonTcg
  alias Pokevestment.Ingestion.{SetMapping, Transformer}
  alias Pokevestment.Pricing.PriceSnapshot

  @doc """
  Run a full price sync for all cards using the Pokemon TCG API.

  Returns `{:ok, summary}` or `{:error, reason}`.
  """
  def run do
    start = System.monotonic_time(:millisecond)
    Logger.info("PriceSync: starting daily price sync via Pokemon TCG API...")

    with {:ok, set_mapping} <- SetMapping.build() do
      our_card_ids = load_card_ids()
      total_sets = map_size(set_mapping)
      Logger.info("PriceSync: #{total_sets} sets mapped, #{MapSet.size(our_card_ids)} cards in DB")

      counter = :counters.new(1, [:atomics])

      {snapshots_inserted, failed_sets} =
        set_mapping
        |> Map.to_list()
        |> Task.async_stream(
          fn {ptcg_set_id, our_set_id} ->
            {ptcg_set_id, sync_set(ptcg_set_id, our_set_id, our_card_ids)}
          end,
          max_concurrency: 5,
          timeout: 120_000,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Enum.reduce({0, []}, fn result, {inserted, failed} ->
          :counters.add(counter, 1, 1)
          processed = :counters.get(counter, 1)

          if rem(processed, 20) == 0 do
            elapsed = System.monotonic_time(:millisecond) - start
            pct = Float.round(processed / total_sets * 100, 1)
            Logger.info("PriceSync: #{processed}/#{total_sets} sets (#{pct}%) — #{format_duration(elapsed)}")
          end

          case result do
            {:ok, {_set_id, {:ok, count}}} ->
              {inserted + count, failed}

            {:ok, {set_id, {:error, reason}}} ->
              Logger.warning("PriceSync: failed set #{set_id}: #{inspect(reason)}")
              {inserted, [set_id | failed]}

            {:exit, reason} ->
              Logger.warning("PriceSync: task exited: #{inspect(reason)}")
              {inserted, failed}
          end
        end)

      elapsed_ms = System.monotonic_time(:millisecond) - start
      processed = :counters.get(counter, 1)

      Logger.info(
        "PriceSync: complete in #{format_duration(elapsed_ms)} — " <>
          "#{processed}/#{total_sets} sets processed, #{snapshots_inserted} snapshots inserted, " <>
          "#{length(failed_sets)} failed"
      )

      {:ok,
       %{
         total: total_sets,
         processed: processed,
         snapshots_inserted: snapshots_inserted,
         failed: failed_sets,
         elapsed_ms: elapsed_ms
       }}
    end
  end

  defp load_card_ids do
    import Ecto.Query
    from(c in "cards", select: c.id) |> Repo.all() |> MapSet.new()
  end

  defp sync_set(ptcg_set_id, our_set_id, our_card_ids) do
    case PokemonTcg.list_cards_for_set(ptcg_set_id) do
      {:ok, cards} ->
        snapshots =
          Enum.flat_map(cards, fn card ->
            number = card["number"] || ""
            card_id = resolve_card_id(our_set_id, number, our_card_ids)

            if card_id do
              Transformer.build_price_snapshots_from_ptcg(
                card_id,
                card["tcgplayer"],
                card["cardmarket"]
              )
            else
              []
            end
          end)

        inserted = insert_snapshots(snapshots)
        {:ok, inserted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Try both unpadded (older sets: xy4-35) and padded (modern sets: sv06-040) card IDs
  defp resolve_card_id(set_id, number, our_card_ids) do
    unpadded = "#{set_id}-#{number}"
    padded = "#{set_id}-#{String.pad_leading(number, 3, "0")}"

    cond do
      MapSet.member?(our_card_ids, unpadded) -> unpadded
      MapSet.member?(our_card_ids, padded) -> padded
      true -> nil
    end
  end

  defp insert_snapshots([]), do: 0

  defp insert_snapshots(snapshots) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {valid_rows, invalid_count} =
      Enum.reduce(snapshots, {[], 0}, fn attrs, {rows, bad} ->
        changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)

        if changeset.valid? do
          row = Map.merge(attrs, %{inserted_at: now})
          {[row | rows], bad}
        else
          Logger.warning(
            "PriceSync: dropping invalid snapshot for card #{attrs[:card_id]}: " <>
              "#{inspect(changeset.errors)}"
          )

          {rows, bad + 1}
        end
      end)

    if invalid_count > 0 do
      Logger.warning("PriceSync: skipped #{invalid_count} invalid snapshots in batch")
    end

    case valid_rows do
      [] ->
        0

      rows ->
        {count, _} =
          Repo.insert_all(PriceSnapshot, Enum.reverse(rows),
            on_conflict: :nothing,
            conflict_target: [:card_id, :source, :variant, :snapshot_date]
          )

        count
    end
  end
end
