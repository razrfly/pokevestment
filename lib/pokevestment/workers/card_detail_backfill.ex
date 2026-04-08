defmodule Pokevestment.Workers.CardDetailBackfill do
  @moduledoc """
  Oban worker that detects cards missing detailed data (rarity, HP, attacks,
  TCGdex pricing) and backfills them from the TCGdex card detail API.

  Runs daily at 6:30 AM UTC (after DailyPriceSync starts, before DataQualityCheck).
  Processes in batches to avoid overwhelming the TCGdex API. Self-limiting:
  returns :ok immediately when no cards need backfill.

  This worker exists to ensure data completeness is self-healing — if FullImport
  creates minimal card records, or new sets are added, this worker will
  automatically fill in the gaps without manual intervention.
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Api.Tcgdex
  alias Pokevestment.Cards.{Card, Set}
  alias Pokevestment.Ingestion.Transformer
  alias Pokevestment.Pokemon.Species
  alias Pokevestment.Pricing.{ExchangeRate, SoldPrice, ListingPrice}
  alias Pokevestment.Cards.{CardType, CardDexId}

  # Process up to this many cards per run to avoid long-running jobs
  @batch_size 500

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cards_needing_backfill = count_incomplete_cards()

    if cards_needing_backfill == 0 do
      Logger.info("[CardDetailBackfill] All cards have complete data, nothing to do")
      :ok
    else
      Logger.info(
        "[CardDetailBackfill] #{cards_needing_backfill} cards need backfill, processing up to #{@batch_size}"
      )

      # Fetch exchange rate once for the batch
      case ExchangeRate.fetch_and_cache() do
        {:ok, rate_info} ->
          Logger.info("[CardDetailBackfill] EUR/USD rate = #{rate_info.rate} (#{rate_info.date})")

        {:error, reason} ->
          Logger.warning("[CardDetailBackfill] Could not fetch exchange rate: #{inspect(reason)}")
      end

      result = backfill_batch()

      Logger.info(
        "[CardDetailBackfill] Backfilled #{result.updated} cards, #{length(result.failed)} failed, " <>
          "#{result.sold_added} sold prices, #{result.listing_added} listing prices"
      )

      # If more cards remain, schedule another run in 5 minutes
      remaining = cards_needing_backfill - result.updated
      if remaining > 0 do
        Logger.info("[CardDetailBackfill] #{remaining} cards still need backfill, scheduling follow-up")
        %{} |> __MODULE__.new(schedule_in: 300) |> Oban.insert()
      end

      :ok
    end
  end

  @doc "Count cards missing rarity (proxy for 'needs detail backfill')."
  def count_incomplete_cards do
    from(c in Card, where: is_nil(c.rarity))
    |> Repo.aggregate(:count)
  end

  defp backfill_batch do
    species_ids = load_species_ids()
    sets_map = load_sets_map()

    # Get cards missing rarity, grouped by set for efficient processing
    cards_by_set =
      from(c in Card,
        where: is_nil(c.rarity),
        select: {c.set_id, c.id},
        limit: ^@batch_size
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    {updated, failed, sold_added, listing_added} =
      cards_by_set
      |> Enum.to_list()
      |> Task.async_stream(
        fn {_set_id, card_ids} ->
          Enum.reduce(card_ids, {0, [], 0, 0}, fn card_id, {ok, fails, sold, listing} ->
            case fetch_and_upsert(card_id, sets_map, species_ids) do
              {:ok, sold_count, listing_count} ->
                {ok + 1, fails, sold + sold_count, listing + listing_count}

              {:error, _} ->
                {ok, [card_id | fails], sold, listing}
            end
          end)
        end,
        max_concurrency: 5,
        timeout: 120_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({0, [], 0, 0}, fn
        {:ok, {ok, fails, sold, listing}}, {total_ok, total_fails, total_sold, total_listing} ->
          {total_ok + ok, total_fails ++ fails, total_sold + sold, total_listing + listing}

        {:exit, _reason}, acc ->
          acc
      end)

    %{updated: updated, failed: failed, sold_added: sold_added, listing_added: listing_added}
  end

  defp fetch_and_upsert(card_id, sets_map, species_ids) do
    task = Task.async(fn -> Tcgdex.get_card(card_id) end)

    case Task.yield(task, 15_000) || Task.shutdown(task) do
      {:ok, {:ok, card_raw}} ->
        set_data = Map.get(sets_map, card_raw["set"]["id"] || "", %{})

        {card_attrs, type_attrs, dex_id_attrs, sold_attrs, listing_attrs} =
          Transformer.card_attrs(card_raw, set_data)

        case upsert_card(card_attrs, type_attrs, dex_id_attrs, sold_attrs, listing_attrs, species_ids) do
          {:ok, _} -> {:ok, length(sold_attrs), length(listing_attrs)}
          {:error, reason} -> {:error, reason}
        end

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, :timeout}
    end
  end

  defp upsert_card(card_attrs, type_attrs, dex_id_attrs, sold_attrs, listing_attrs, species_ids) do
    Repo.transaction(fn ->
      case %Card{}
           |> Card.changeset(card_attrs)
           |> Repo.insert(
             on_conflict: {:replace_all_except, [:id, :inserted_at]},
             conflict_target: [:id]
           ) do
        {:ok, card} ->
          from(ct in CardType, where: ct.card_id == ^card.id) |> Repo.delete_all()

          Enum.each(type_attrs, fn attrs ->
            %CardType{} |> CardType.changeset(attrs) |> Repo.insert(on_conflict: :nothing)
          end)

          from(cd in CardDexId, where: cd.card_id == ^card.id) |> Repo.delete_all()

          Enum.each(dex_id_attrs, fn attrs ->
            if MapSet.member?(species_ids, attrs[:dex_id]) do
              %CardDexId{} |> CardDexId.changeset(attrs) |> Repo.insert(on_conflict: :nothing)
            end
          end)

          Enum.each(sold_attrs, fn attrs ->
            %SoldPrice{}
            |> SoldPrice.changeset(attrs)
            |> Repo.insert(
              on_conflict: :nothing,
              conflict_target: [:card_id, :marketplace, :variant, :snapshot_date]
            )
          end)

          Enum.each(listing_attrs, fn attrs ->
            %ListingPrice{}
            |> ListingPrice.changeset(attrs)
            |> Repo.insert(
              on_conflict: :nothing,
              conflict_target: [:card_id, :marketplace, :variant, :snapshot_date]
            )
          end)

          card

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  rescue
    e ->
      Logger.warning("[CardDetailBackfill] Exception upserting card #{card_attrs[:id]}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp load_species_ids do
    from(s in Species, select: s.id) |> Repo.all() |> MapSet.new()
  end

  defp load_sets_map do
    from(s in Set, select: {s.id, %{card_count_official: s.card_count_official}})
    |> Repo.all()
    |> Map.new()
  end
end
