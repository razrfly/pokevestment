defmodule Pokevestment.ML.PriceFeatures do
  @moduledoc """
  Computes price-derived features for each card from sold_prices only.
  Returns %{card_id => %{feature_name => value}} using the latest snapshot date
  with variant priority ordering (tcgplayer/normal preferred).

  Sold prices only — listing data is never used for ML targets.
  All prices normalized to USD via price_usd column.
  """

  alias Pokevestment.Repo

  @doc """
  Computes price features using DISTINCT ON with variant priority.
  TCGPlayer is preferred over CardMarket. Uses price_usd as the
  canonical price — all prices in USD regardless of source.
  Returns %{card_id => %{feature_name => value}}.
  """
  def compute_all do
    %{columns: columns, rows: rows} = Repo.query!(query(), [], timeout: 60_000)
    rows_to_map(columns, rows)
  end

  defp query do
    """
    WITH canonical AS (
      SELECT DISTINCT ON (sp.card_id)
        sp.card_id,
        sp.marketplace AS source,
        'USD' AS currency,
        sp.price_usd::float AS canonical_price
      FROM sold_prices sp
      JOIN cards c ON c.id = sp.card_id
      WHERE sp.price_usd IS NOT NULL AND sp.price_usd > 0
        AND (
          c.variants IS NULL
          OR (sp.variant = 'normal' AND (c.variants->>'normal')::boolean IS NOT FALSE)
          OR (sp.variant = 'holofoil' AND (c.variants->>'holo')::boolean IS NOT FALSE)
          OR (sp.variant = 'reverse-holofoil' AND (c.variants->>'reverse')::boolean IS NOT FALSE)
          OR sp.variant NOT IN ('normal', 'holofoil', 'reverse-holofoil')
        )
      ORDER BY sp.card_id, sp.snapshot_date DESC,
        CASE
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'normal' THEN 1
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'holofoil' THEN 2
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'reverse-holofoil' THEN 3
          WHEN sp.marketplace = 'cardmarket' AND sp.variant = 'normal' THEN 4
          WHEN sp.marketplace = 'cardmarket' AND sp.variant = 'reverse-holofoil' THEN 5
          ELSE 6
        END
    ),
    rolling_avgs AS (
      SELECT DISTINCT ON (sp.card_id)
        sp.card_id,
        sp.price_avg_1d::float,
        sp.price_avg_7d::float,
        sp.price_avg_30d::float
      FROM sold_prices sp
      WHERE sp.price_avg_1d IS NOT NULL OR sp.price_avg_7d IS NOT NULL OR sp.price_avg_30d IS NOT NULL
      ORDER BY sp.card_id, sp.snapshot_date DESC,
        CASE
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'normal' THEN 1
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'holofoil' THEN 2
          WHEN sp.marketplace = 'tcgplayer' AND sp.variant = 'reverse-holofoil' THEN 3
          WHEN sp.marketplace = 'cardmarket' AND sp.variant = 'normal' THEN 4
          WHEN sp.marketplace = 'cardmarket' AND sp.variant = 'reverse-holofoil' THEN 5
          ELSE 6
        END
    )
    SELECT
      c.card_id,
      c.source,
      c.currency,
      c.canonical_price,
      r.price_avg_1d,
      r.price_avg_7d,
      r.price_avg_30d
    FROM canonical c
    LEFT JOIN rolling_avgs r ON r.card_id = c.card_id
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
    avg1 = base["price_avg_1d"]
    avg7 = base["price_avg_7d"]
    avg30 = base["price_avg_30d"]

    %{
      "price_momentum_7d" => momentum(avg1, avg7),
      "price_momentum_30d" => momentum(avg1, avg30),
      "price_volatility" => compute_volatility(avg1, avg30),
      "log_price" => safe_log(canonical)
    }
  end

  # Volatility computed from sold price time-window spread
  defp compute_volatility(avg1, avg30)
       when is_number(avg1) and is_number(avg30) and avg30 > 0,
       do: abs(avg1 - avg30) / avg30

  defp compute_volatility(_, _), do: nil

  defp momentum(_current, nil), do: nil
  defp momentum(nil, _old), do: nil
  defp momentum(_current, old) when old == 0, do: nil
  defp momentum(current, old), do: (current - old) / old

  defp safe_log(price) when is_number(price) and price > 0, do: :math.log(price)
  defp safe_log(_), do: nil
end
