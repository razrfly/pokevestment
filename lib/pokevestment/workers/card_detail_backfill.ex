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
  # Cap follow-up chain to prevent infinite rescheduling on permanently failing cards
  @max_follow_ups 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    follow_up = Map.get(args, "follow_up", 0)
    cards_needing_backfill = count_incomplete_cards()

    if cards_needing_backfill == 0 do
      Logger.info("[CardDetailBackfill] All cards have complete data, nothing to do")
      :ok
    else
      Logger.info(
        "[CardDetailBackfill] #{cards_needing_backfill} cards need backfill, processing up to #{@batch_size} (follow-up #{follow_up}/#{@max_follow_ups})"
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

      # Schedule follow-up only if: progress was made, cards remain, and we haven't hit the cap
      remaining = cards_needing_backfill - result.updated

      cond do
        remaining <= 0 ->
          :ok

        result.updated == 0 ->
          Logger.warning(
            "[CardDetailBackfill] No progress made, #{remaining} cards may be permanently unfetchable — stopping"
          )

          :ok

        follow_up >= @max_follow_ups ->
          Logger.warning(
            "[CardDetailBackfill] Reached follow-up limit (#{@max_follow_ups}), #{remaining} cards still incomplete — stopping"
          )

          :ok

        true ->
          Logger.info("[CardDetailBackfill] #{remaining} cards still need backfill, scheduling follow-up")

          case %{"follow_up" => follow_up + 1} |> __MODULE__.new(schedule_in: 300) |> Oban.insert() do
            {:ok, _job} -> :ok
            {:error, reason} ->
              Logger.error("[CardDetailBackfill] Failed to schedule follow-up job: #{inspect(reason)}")
              {:error, "failed to schedule follow-up: #{inspect(reason)}"}
          end
      end
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

    # Fetch individual card IDs — no set grouping needed since each card is
    # fetched individually. Flat async_stream avoids the previous issue where
    # large set groups could blow the outer timeout and silently discard progress.
    card_ids =
      from(c in Card,
        where: is_nil(c.rarity),
        select: c.id,
        order_by: [asc: c.id],
        limit: ^@batch_size
      )
      |> Repo.all()

    {updated, failed, sold_added, listing_added} =
      card_ids
      |> Task.async_stream(
        fn card_id ->
          case fetch_and_upsert(card_id, sets_map, species_ids) do
            {:ok, sold_count, listing_count} -> {:ok, card_id, sold_count, listing_count}
            {:error, reason} -> {:error, card_id, reason}
          end
        end,
        max_concurrency: 5,
        timeout: 30_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce({0, [], 0, 0}, fn
        {:ok, {:ok, _card_id, sold, listing}}, {total_ok, total_fails, total_sold, total_listing} ->
          {total_ok + 1, total_fails, total_sold + sold, total_listing + listing}

        {:ok, {:error, card_id, _reason}}, {total_ok, total_fails, total_sold, total_listing} ->
          {total_ok, [card_id | total_fails], total_sold, total_listing}

        {:exit, reason}, {total_ok, total_fails, total_sold, total_listing} ->
          Logger.warning("[CardDetailBackfill] Task exited: #{inspect(reason)}")
          {total_ok, [{:exit, reason} | total_fails], total_sold, total_listing}
      end)

    %{updated: updated, failed: failed, sold_added: sold_added, listing_added: listing_added}
  end

  defp fetch_and_upsert(card_id, sets_map, species_ids) do
    # Use try/catch inside the task to prevent linked-task crashes from
    # killing the caller before Task.yield can observe the exit.
    task =
      Task.async(fn ->
        try do
          Tcgdex.get_card(card_id)
        catch
          :exit, reason -> {:error, {:exit, reason}}
        end
      end)

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

      {:exit, reason} ->
        {:error, {:exit, reason}}

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
            case %CardType{} |> CardType.changeset(attrs) |> Repo.insert(on_conflict: :nothing) do
              {:ok, _} -> :ok
              {:error, cs} ->
                Logger.warning("[CardDetailBackfill] CardType insert failed for #{card.id}: #{inspect(cs.errors)}")
                Repo.rollback({:card_type_failed, card.id, cs.errors})
            end
          end)

          from(cd in CardDexId, where: cd.card_id == ^card.id) |> Repo.delete_all()

          Enum.each(dex_id_attrs, fn attrs ->
            if MapSet.member?(species_ids, attrs[:dex_id]) do
              case %CardDexId{} |> CardDexId.changeset(attrs) |> Repo.insert(on_conflict: :nothing) do
                {:ok, _} -> :ok
                {:error, cs} ->
                  Logger.warning("[CardDetailBackfill] CardDexId insert failed for #{card.id}: #{inspect(cs.errors)}")
                  Repo.rollback({:card_dex_id_failed, card.id, cs.errors})
              end
            end
          end)

          Enum.each(sold_attrs, fn attrs ->
            case %SoldPrice{}
                 |> SoldPrice.changeset(attrs)
                 |> Repo.insert(
                   on_conflict: :nothing,
                   conflict_target: [:card_id, :marketplace, :variant, :condition, :snapshot_date]
                 ) do
              {:ok, _} -> :ok
              {:error, cs} ->
                Logger.warning("[CardDetailBackfill] SoldPrice insert failed for #{card.id}: #{inspect(cs.errors)}")
                Repo.rollback({:sold_price_failed, card.id, cs.errors})
            end
          end)

          Enum.each(listing_attrs, fn attrs ->
            case %ListingPrice{}
                 |> ListingPrice.changeset(attrs)
                 |> Repo.insert(
                   on_conflict: :nothing,
                   conflict_target: [:card_id, :marketplace, :variant, :condition, :snapshot_date]
                 ) do
              {:ok, _} -> :ok
              {:error, cs} ->
                Logger.warning("[CardDetailBackfill] ListingPrice insert failed for #{card.id}: #{inspect(cs.errors)}")
                Repo.rollback({:listing_price_failed, card.id, cs.errors})
            end
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
