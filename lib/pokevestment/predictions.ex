defmodule Pokevestment.Predictions do
  @moduledoc """
  Context module for card predictions. Provides query functions
  used by LiveView to display ML-generated investment signals.
  """

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.{Card, CardType, Set}
  alias Pokevestment.ML.CardPrediction
  alias Pokevestment.ML.PredictionSnapshot
  alias Pokevestment.Pricing.{SoldPrice, ListingPrice}
  alias Pokevestment.Tournaments.Tournament

  @doc """
  Lists predictions for all cards in a set.

  ## Options
    * `:signal` - filter by signal value (e.g. "STRONG_BUY", "BUY")
    * `:sort` - sort key: "strength_desc" (default), "price_desc", "price_asc",
      "number_asc", "name_asc"
    * `:search` - card name text search (case-insensitive, partial match)
    * `:min_price` - minimum current_price filter (Decimal or float)
    * `:type` - Pokemon type filter (e.g. "Fire", "Water")
    * `:limit` - max results (default 500)
  """
  def list_for_set(set_id, opts \\ []) do
    signal_filter = Keyword.get(opts, :signal)
    sort_key = Keyword.get(opts, :sort, "strength_desc")
    search = Keyword.get(opts, :search)
    min_price = Keyword.get(opts, :min_price)
    type_filter = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 500)

    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: c.set_id == ^set_id,
      limit: ^limit,
      preload: [card: c]
    )
    |> maybe_filter_signal(signal_filter)
    |> maybe_filter_search(search)
    |> maybe_filter_min_price(min_price)
    |> maybe_filter_type(type_filter)
    |> apply_card_sort(sort_key)
    |> Repo.all()
  end

  defp maybe_filter_signal(query, nil), do: query
  defp maybe_filter_signal(query, ""), do: query
  defp maybe_filter_signal(query, signal), do: where(query, [p], p.signal == ^signal)

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    escaped = String.replace(search, ~r/[%_\\]/, fn c -> "\\#{c}" end)
    where(query, [_, c], ilike(c.name, ^"%#{escaped}%"))
  end

  defp maybe_filter_min_price(query, nil), do: query
  defp maybe_filter_min_price(query, ""), do: query

  defp maybe_filter_min_price(query, min_price) do
    where(query, [p], p.current_price >= ^min_price)
  end

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, ""), do: query
  defp maybe_filter_type(query, "all"), do: query

  defp maybe_filter_type(query, type) do
    card_ids = from(ct in CardType, where: ct.type_name == ^type, select: ct.card_id)
    where(query, [_, c], c.id in subquery(card_ids))
  end

  defp apply_card_sort(query, "price_desc"),
    do: order_by(query, [p], desc_nulls_last: p.current_price)

  defp apply_card_sort(query, "price_asc"),
    do: order_by(query, [p], asc_nulls_last: p.current_price)

  defp apply_card_sort(query, "number_asc"),
    do: order_by(query, [_, c], asc: c.local_id)

  defp apply_card_sort(query, "name_asc"),
    do: order_by(query, [_, c], asc: c.name)

  defp apply_card_sort(query, _strength_desc),
    do: order_by(query, [p], desc_nulls_last: p.signal_strength)

  @doc """
  Gets a single card prediction with the card preloaded.
  Returns nil if no prediction exists.
  """
  def get_prediction(card_id) do
    CardPrediction
    |> Repo.get(card_id)
    |> Repo.preload(:card)
  end

  @doc """
  Gets a card prediction with full card associations for the detail page.
  Preloads card with card_types and set.
  Returns nil if no prediction exists.
  """
  def get_card_prediction(card_id) do
    from(p in CardPrediction,
      where: p.card_id == ^card_id,
      preload: [card: [:card_types, :set]]
    )
    |> Repo.one()
  end

  @doc """
  Returns a summary of signal counts for a specific set.

  Returns a map like `%{"STRONG_BUY" => 2, "BUY" => 5, "HOLD" => 150}`.
  """
  def signal_summary_for_set(set_id) do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: c.set_id == ^set_id,
      group_by: p.signal,
      select: {p.signal, count(p.card_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns the distinct Pokemon types present in a set, sorted alphabetically.
  """
  def types_for_set(set_id) do
    from(ct in CardType,
      join: c in Card,
      on: c.id == ct.card_id,
      where: c.set_id == ^set_id,
      distinct: true,
      select: ct.type_name,
      order_by: ct.type_name
    )
    |> Repo.all()
  end

  @doc """
  Returns aggregated signal counts grouped by set_id.

  Returns a list of maps: `%{set_id: "sv06", signal: "BUY", count: 12}`.
  Only includes BUY and STRONG_BUY signals.
  """
  def signal_counts_by_set do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: p.signal in ["STRONG_BUY", "BUY"],
      group_by: [c.set_id, p.signal],
      select: %{set_id: c.set_id, signal: p.signal, count: count(p.card_id)}
    )
    |> Repo.all()
  end

  @doc """
  Returns top BUY/STRONG_BUY cards globally, ordered by signal_strength.
  Only includes cards that have an image and a current price.
  """
  def top_buys(limit \\ 8) do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: p.signal in ["STRONG_BUY", "BUY"],
      where: not is_nil(c.image_url),
      where: not is_nil(p.current_price),
      order_by: [desc_nulls_last: p.signal_strength],
      limit: ^limit,
      preload: [card: c]
    )
    |> Repo.all()
  end

  @doc """
  Returns signal counts across all predictions.
  """
  def global_signal_summary do
    from(p in CardPrediction,
      group_by: p.signal,
      select: {p.signal, count(p.card_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Promo sets and non-expansion sets excluded from homepage "Hot Sets"
  @excluded_series ~w(tcgp tk mc misc pop)
  @excluded_set_ids ~w(sp ex5.5 fut2020 ru1 wp)

  @doc """
  Returns sets ranked by total BUY + STRONG_BUY prediction count.
  Excludes promo sets and non-expansion sets.
  """
  def top_sets_by_signals(limit \\ 4) do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      join: s in Set,
      on: s.id == c.set_id,
      where: p.signal in ["STRONG_BUY", "BUY"],
      where: s.series_id not in @excluded_series,
      where: s.id not in @excluded_set_ids,
      where: not ilike(s.name, "%promo%"),
      group_by: s.id,
      order_by: [desc: count(p.card_id)],
      limit: ^limit,
      select: {s, count(p.card_id)}
    )
    |> Repo.all()
  end

  @doc """
  Returns aggregate homepage stats: card count, set count, tournament count.
  """
  def homepage_stats do
    cards = Repo.aggregate(Card, :count)
    sets = Repo.aggregate(Set, :count)
    tournaments = Repo.aggregate(Tournament, :count)

    %{cards: cards, sets: sets, tournaments: tournaments}
  end

  @doc """
  Returns marketplace URLs for a list of card IDs, keyed by card_id and source.

  Returns `%{card_id => %{"tcgplayer" => url, "cardmarket" => url}}`.
  URLs come from the latest sold_prices/listing_prices metadata for each card+marketplace.
  """
  def marketplace_urls_for_cards([]), do: %{}

  def marketplace_urls_for_cards(card_ids) do
    # Query both sold_prices and listing_prices for marketplace URLs in metadata
    sold_urls =
      from(sp in SoldPrice,
        where: sp.card_id in ^card_ids,
        where: not is_nil(sp.metadata),
        where: fragment("? ->> 'marketplace_url' IS NOT NULL", sp.metadata),
        distinct: [sp.card_id, sp.marketplace],
        order_by: [sp.card_id, sp.marketplace, desc: sp.snapshot_date],
        select: {sp.card_id, sp.marketplace, fragment("? ->> 'marketplace_url'", sp.metadata)}
      )
      |> Repo.all()

    listing_urls =
      from(lp in ListingPrice,
        where: lp.card_id in ^card_ids,
        where: not is_nil(lp.metadata),
        where: fragment("? ->> 'marketplace_url' IS NOT NULL", lp.metadata),
        distinct: [lp.card_id, lp.marketplace],
        order_by: [lp.card_id, lp.marketplace, desc: lp.snapshot_date],
        select: {lp.card_id, lp.marketplace, fragment("? ->> 'marketplace_url'", lp.metadata)}
      )
      |> Repo.all()

    # Prefer sold_prices URLs, fall back to listing_prices
    (sold_urls ++ listing_urls)
    |> Enum.uniq_by(fn {card_id, marketplace, _} -> {card_id, marketplace} end)
    |> Enum.group_by(
      fn {card_id, _, _} -> card_id end,
      fn {_, marketplace, url} -> {marketplace, url} end
    )
    |> Map.new(fn {card_id, source_urls} -> {card_id, Map.new(source_urls)} end)
  end

  @doc """
  Returns the most recent prediction_date, or nil if no predictions exist.
  """
  def last_prediction_date do
    Repo.one(from p in CardPrediction, select: max(p.prediction_date))
  end

  @doc """
  Batch upserts predictions into card_predictions (hot table) and inserts
  corresponding rows into prediction_snapshots (cold table).

  Expects a list of maps with prediction attributes.
  """
  def upsert_predictions(predictions_list) when is_list(predictions_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      prediction_count = upsert_card_predictions(predictions_list, now)
      snapshot_count = insert_prediction_snapshots(predictions_list, now)

      %{predictions_upserted: prediction_count, snapshots_inserted: snapshot_count}
    end)
  end

  defp upsert_card_predictions(predictions_list, now) do
    predictions_list
    |> Enum.map(fn attrs ->
      attrs
      |> Map.put(:updated_at, now)
    end)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} =
        Repo.insert_all(CardPrediction, chunk,
          on_conflict:
            {:replace_all_except, [:card_id]},
          conflict_target: :card_id
        )

      acc + count
    end)
  end

  defp insert_prediction_snapshots(predictions_list, now) do
    predictions_list
    |> Enum.map(fn attrs ->
      attrs
      |> Map.drop([:top_positive_drivers, :top_negative_drivers, :umbrella_breakdown])
      |> Map.put(:inserted_at, now)
    end)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} = Repo.insert_all(PredictionSnapshot, chunk)
      acc + count
    end)
  end
end
