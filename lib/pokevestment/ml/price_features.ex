defmodule Pokevestment.ML.PriceFeatures do
  @moduledoc """
  Computes price-derived features for each card from price snapshots.
  Returns %{card_id => %{feature_name => value}} using the latest snapshot date
  with variant priority ordering (cardmarket/normal preferred).
  """

  alias Pokevestment.Repo

  @doc """
  Computes price features using DISTINCT ON with variant priority.
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
      ps.variant,
      ps.price_avg::float,
      ps.price_low::float,
      ps.price_high::float,
      ps.price_mid::float,
      ps.price_market::float,
      ps.price_trend::float,
      ps.price_avg1::float,
      ps.price_avg7::float,
      ps.price_avg30::float
    FROM price_snapshots ps
    WHERE ps.snapshot_date = (SELECT MAX(snapshot_date) FROM price_snapshots)
      AND ps.price_avg IS NOT NULL
      AND ps.price_avg > 0
    ORDER BY ps.card_id,
      CASE
        WHEN ps.source = 'cardmarket' AND ps.variant = 'normal' THEN 1
        WHEN ps.source = 'cardmarket' AND ps.variant = 'holo' THEN 2
        WHEN ps.source = 'tcgplayer' AND ps.variant = 'normal' THEN 3
        WHEN ps.source = 'tcgplayer' AND ps.variant = 'holofoil' THEN 4
        ELSE 5
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
    avg = base["price_avg"]
    avg1 = base["price_avg1"]
    avg7 = base["price_avg7"]
    avg30 = base["price_avg30"]
    high = base["price_high"] || 0
    low = base["price_low"] || 0

    %{
      "price_momentum_7d" => momentum(avg1, avg7),
      "price_momentum_30d" => momentum(avg1, avg30),
      "price_volatility" => volatility(high, low, avg),
      "log_price" => safe_log(avg)
    }
  end

  defp momentum(_current, nil), do: nil
  defp momentum(nil, _old), do: nil
  defp momentum(_current, old) when old == 0, do: nil
  defp momentum(current, old), do: (current - old) / old

  defp volatility(_high, _low, avg) when avg == 0, do: nil
  defp volatility(high, low, avg), do: (high - low) / avg

  defp safe_log(avg) when avg > 0, do: :math.log(avg)
  defp safe_log(_), do: nil
end
