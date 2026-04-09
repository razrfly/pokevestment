defmodule Pokevestment.Ingestion.PptBackfill do
  @moduledoc """
  Backfills pricing data from PokemonPriceTracker API.

  Two modes:
  - `run_priority_sets/1`: targets 10 sets with zero TCGPlayer pricing (737 cards)
  - `run/1`: all sets via dynamic set name mapping

  Uses pagination (limit=100, offset) to fetch cards per set.
  Tracks daily credit budget via response headers.
  PPT rows use upsert semantics — reruns refresh data.
  """

  require Logger

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Api.PokemonPriceTracker, as: PPT
  alias Pokevestment.Ingestion.Transformer
  alias Pokevestment.Pricing.{SoldPrice, ListingPrice}

  # Maps our set IDs to PPT set names for the 10 Cardmarket-only sets
  @priority_sets %{
    "2014xy" => "McDonald's Promos 2014",
    "2015xy" => "McDonald's Promos 2015",
    "2016xy" => "McDonald's Promos 2016",
    "2017sm" => "McDonald's Promos 2017",
    "2018sm" => "McDonald's Promos 2018",
    "ex5.5" => "Poké Card Creator Pack",
    "me02.5" => "ME: Ascended Heroes",
    "me03" => "ME03: Perfect Order",
    "mep" => "ME: Mega Evolution Promo",
    "svp" => "SV: Scarlet & Violet Promo Cards"
  }

  @default_credit_reserve 2_000
  @page_size 100

  @doc """
  Sync only the 10 priority sets that have zero TCGPlayer pricing.
  Good for testing on the free tier (737 cards = 737 credits).

  Options:
  - `:credit_reserve` — stop when credits drop below this (default 2000)
  - `:include_history` — fetch price history (+1 credit/card, default false)
  - `:days` — history window in days (default 3)
  """
  def run_priority_sets(opts \\ []) do
    our_card_ids = load_card_ids()

    Logger.info("[PptBackfill] Starting priority sets sync (#{map_size(@priority_sets)} sets, #{MapSet.size(our_card_ids)} cards in DB)")

    run_set_list(@priority_sets, our_card_ids, opts)
  end

  @doc """
  Sync all sets by building a dynamic mapping from PPT set list.
  Requires $9.99/mo plan for sufficient credits.
  """
  def run(opts \\ []) do
    our_card_ids = load_card_ids()
    our_set_names = load_set_names()

    case build_set_mapping(our_set_names) do
      {:ok, mapping} ->
        Logger.info("[PptBackfill] Full sync: #{map_size(mapping)} sets mapped")
        run_set_list(mapping, our_card_ids, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_set_list(set_mapping, our_card_ids, opts) do
    credit_reserve = Keyword.get(opts, :credit_reserve, @default_credit_reserve)
    include_history = Keyword.get(opts, :include_history, false)
    days = Keyword.get(opts, :days, 3)
    counter = :counters.new(2, [:atomics])
    # counter 1 = sets processed, counter 2 = prices inserted

    errors =
      Enum.reduce_while(set_mapping, [], fn {our_set_id, ppt_set_name}, errs ->
        case sync_set(ppt_set_name, our_card_ids, include_history, days) do
          {:ok, count, credits_remaining} ->
            :counters.add(counter, 1, 1)
            :counters.add(counter, 2, count)
            sets_done = :counters.get(counter, 1)
            total_inserted = :counters.get(counter, 2)

            Logger.info(
              "[PptBackfill] Set #{our_set_id} (\"#{ppt_set_name}\"): #{count} prices upserted " <>
                "(#{sets_done} sets done, #{total_inserted} total, #{credits_remaining || "?"} credits left)"
            )

            if credits_remaining && credits_remaining < credit_reserve do
              Logger.warning("[PptBackfill] Credit reserve reached (#{credits_remaining} < #{credit_reserve}), stopping")
              {:halt, errs}
            else
              {:cont, errs}
            end

          {:error, {:rate_limited, retry_after}} ->
            Logger.warning("[PptBackfill] Rate limited on set #{our_set_id}, waiting #{retry_after}s")
            Process.sleep(retry_after * 1000)
            {:cont, [{our_set_id, :rate_limited} | errs]}

          {:error, reason} ->
            Logger.warning("[PptBackfill] Failed set #{our_set_id}: #{inspect(reason)}")
            {:cont, [{our_set_id, reason} | errs]}
        end
      end)

    sets_processed = :counters.get(counter, 1)
    total_inserted = :counters.get(counter, 2)

    Logger.info("[PptBackfill] Complete: #{sets_processed} sets, #{total_inserted} prices, #{length(errors)} errors")

    {:ok, %{sets_processed: sets_processed, inserted: total_inserted, errors: errors}}
  end

  defp sync_set(ppt_set_name, our_card_ids, include_history, days) do
    fetch_opts = [
      include_history: include_history,
      days: days,
      limit: @page_size
    ]

    fetch_all_pages(ppt_set_name, our_card_ids, fetch_opts, 0, 0, nil)
  end

  defp fetch_all_pages(set_name, our_card_ids, opts, offset, total_inserted, _last_credits) do
    page_opts = Keyword.put(opts, :offset, offset)

    case PPT.fetch_cards_for_set(set_name, page_opts) do
      {:ok, %{"data" => cards, "metadata" => meta}, credits_meta} when is_list(cards) ->
        count = process_cards(cards, our_card_ids)
        new_total = total_inserted + count
        has_more = meta["hasMore"] == true

        if has_more and length(cards) > 0 do
          fetch_all_pages(set_name, our_card_ids, opts, offset + length(cards), new_total, credits_meta.credits_remaining)
        else
          {:ok, new_total, credits_meta.credits_remaining}
        end

      {:ok, %{"data" => card}, credits_meta} when is_map(card) ->
        # Single card response
        count = process_cards([card], our_card_ids)
        {:ok, total_inserted + count, credits_meta.credits_remaining}

      {:error, reason} ->
        if total_inserted > 0 do
          # Partial success — return what we got
          {:ok, total_inserted, nil}
        else
          {:error, reason}
        end
    end
  end

  defp process_cards(cards, our_card_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {all_sold, all_listing} =
      Enum.reduce(cards, {[], []}, fn card, {sold_acc, listing_acc} ->
        card_id = card["externalCatalogId"]

        if card_id && MapSet.member?(our_card_ids, card_id) do
          {sold, listing} = Transformer.build_prices_from_ppt(card)
          {sold ++ sold_acc, listing ++ listing_acc}
        else
          {sold_acc, listing_acc}
        end
      end)

    sold_count = upsert_sold(all_sold, now)
    listing_count = upsert_listing(all_listing, now)
    sold_count + listing_count
  end

  defp upsert_sold([], _now), do: 0

  defp upsert_sold(prices, now) do
    {valid, invalid} =
      Enum.reduce(prices, {[], 0}, fn attrs, {rows, bad} ->
        changeset = SoldPrice.changeset(%SoldPrice{}, attrs)

        if changeset.valid? do
          row = Map.put(attrs, :inserted_at, now)
          {[row | rows], bad}
        else
          Logger.warning("[PptBackfill] Invalid sold price for #{attrs[:card_id]}: #{inspect(changeset.errors)}")
          {rows, bad + 1}
        end
      end)

    if invalid > 0 do
      Logger.warning("[PptBackfill] Skipped #{invalid} invalid sold prices")
    end

    case valid do
      [] ->
        0

      rows ->
        {count, _} =
          Repo.insert_all(SoldPrice, Enum.reverse(rows),
            on_conflict: {:replace, [:price, :price_usd, :source_updated_at, :metadata]},
            conflict_target: [:card_id, :marketplace, :variant, :condition, :snapshot_date]
          )

        count
    end
  end

  defp upsert_listing([], _now), do: 0

  defp upsert_listing(prices, now) do
    {valid, invalid} =
      Enum.reduce(prices, {[], 0}, fn attrs, {rows, bad} ->
        changeset = ListingPrice.changeset(%ListingPrice{}, attrs)

        if changeset.valid? do
          row = Map.put(attrs, :inserted_at, now)
          {[row | rows], bad}
        else
          Logger.warning("[PptBackfill] Invalid listing price for #{attrs[:card_id]}: #{inspect(changeset.errors)}")
          {rows, bad + 1}
        end
      end)

    if invalid > 0 do
      Logger.warning("[PptBackfill] Skipped #{invalid} invalid listing prices")
    end

    case valid do
      [] ->
        0

      rows ->
        {count, _} =
          Repo.insert_all(ListingPrice, Enum.reverse(rows),
            on_conflict: {:replace, [:price_low, :price_low_usd, :source_updated_at, :metadata]},
            conflict_target: [:card_id, :marketplace, :variant, :condition, :snapshot_date]
          )

        count
    end
  end

  defp load_card_ids do
    from(c in "cards", select: c.id) |> Repo.all() |> MapSet.new()
  end

  defp load_set_names do
    from(s in "sets", select: {s.id, s.name}) |> Repo.all() |> Map.new()
  end

  defp build_set_mapping(our_set_names) do
    case PPT.list_sets(limit: 250) do
      {:ok, %{"data" => ppt_sets}, _credits} ->
        ppt_by_name =
          Enum.map(ppt_sets, fn s -> {s["name"], s["name"]} end)
          |> Map.new()

        mapping =
          our_set_names
          |> Enum.reduce(%{}, fn {our_id, our_name}, acc ->
            # Try exact name match, then known priority mappings
            ppt_name =
              cond do
                Map.has_key?(@priority_sets, our_id) -> @priority_sets[our_id]
                Map.has_key?(ppt_by_name, our_name) -> our_name
                true -> nil
              end

            if ppt_name, do: Map.put(acc, our_id, ppt_name), else: acc
          end)

        {:ok, mapping}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
