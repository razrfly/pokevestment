defmodule Pokevestment.ML.PriceFeatures do
  @moduledoc """
  Computes price-derived features for each card from price snapshots.
  Returns %{card_id => %{feature_name => value}} using the latest snapshot date
  with variant priority ordering (cardmarket/normal preferred).
  """

  alias Pokevestment.Repo

  @doc """
  Computes price features using DISTINCT ON with variant priority.
  TCGPlayer is preferred over CardMarket. Uses COALESCE(price_market, price_avg)
  as the canonical price to handle both sources correctly.
  Returns %{card_id => %{feature_name => value}}.
  """
  def compute_all do
    %{columns: columns, rows: rows} = Repo.query!(query(), [], timeout: 60_000)
    rows_to_map(columns, rows)
  end

  defp query do
    """
    SELECT DISTINCT ON (ps.card_id)
      ps.card_id,
      ps.source,
      ps.currency,
      COALESCE(ps.price_market, ps.price_avg)::float AS canonical_price,
      ps.price_low::float,
      ps.price_high::float,
      ps.price_mid::float,
      ps.price_market::float,
      ps.price_avg::float,
      ps.price_trend::float,
      ps.price_avg1::float,
      ps.price_avg7::float,
      ps.price_avg30::float
    FROM price_snapshots ps
    WHERE COALESCE(ps.price_market, ps.price_avg) IS NOT NULL
      AND COALESCE(ps.price_market, ps.price_avg) > 0
    ORDER BY ps.card_id, ps.snapshot_date DESC,
      CASE
        WHEN ps.source = 'tcgplayer' AND ps.variant = 'normal' THEN 1
        WHEN ps.source = 'tcgplayer' AND ps.variant = 'holofoil' THEN 2
        WHEN ps.source = 'tcgplayer' AND ps.variant = 'reverse-holofoil' THEN 3
        WHEN ps.source = 'cardmarket' AND ps.variant = 'normal' THEN 4
        WHEN ps.source = 'cardmarket' AND ps.variant = 'holo' THEN 5
        ELSE 6
      END
    """
  end

  defp rows_to_map(columns, rows) do
    [_ | feature_names] = columns

    Map.new(rows, fn [card_id | values] ->
      base =
        Enum.zip(feature_names, values)
        |> Map.new()

      derived = compute_derived(base)
      {card_id, Map.merge(base, derived)}
    end)
  end

  defp compute_derived(base) do
    canonical = base["canonical_price"]
    source = base["source"]
    avg1 = base["price_avg1"]
    avg7 = base["price_avg7"]
    avg30 = base["price_avg30"]
    high = base["price_high"]
    low = base["price_low"]
    market = base["price_market"]
    avg = base["price_avg"]

    %{
      "price_momentum_7d" => momentum(avg1, avg7),
      "price_momentum_30d" => momentum(avg1, avg30),
      "price_volatility" => compute_volatility(source, high, low, market, avg),
      "log_price" => safe_log(canonical)
    }
  end

  # TCGPlayer has high/low/market, CardMarket has avg/low (high may be nil)
  defp compute_volatility("tcgplayer", high, low, market, _avg)
       when is_number(high) and is_number(low) and is_number(market) and market > 0,
       do: (high - low) / market

  defp compute_volatility(_source, high, low, _market, avg)
       when is_number(high) and is_number(low) and is_number(avg) and avg > 0,
       do: (high - low) / avg

  defp compute_volatility(_source, _high, low, _market, avg)
       when is_number(low) and is_number(avg) and avg > 0,
       do: (avg - low) / avg

  defp compute_volatility(_, _, _, _, _), do: nil

  defp momentum(_current, nil), do: nil
  defp momentum(nil, _old), do: nil
  defp momentum(_current, old) when old == 0, do: nil
  defp momentum(current, old), do: (current - old) / old

  defp safe_log(price) when is_number(price) and price > 0, do: :math.log(price)
  defp safe_log(_), do: nil
end
