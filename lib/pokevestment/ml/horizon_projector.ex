defmodule Pokevestment.ML.HorizonProjector do
  @moduledoc """
  Projects future prices across multiple time horizons using variable
  convergence rates adjusted by card-specific factors.
  """

  @horizons [1, 7, 30, 90, 365]
  @base_lambda 0.015

  @doc """
  Projects future prices for each horizon given current price and predicted fair value.

  ## Options
    * `:volatility` - price volatility (0.0-1.0), default 0.0
    * `:days_since_release` - days since set release, default 0
    * `:meta_share` - 30-day meta share (0.0-1.0), default 0.0

  Returns a map keyed by horizon days (as strings), each containing:
    * `"projected_price"` - Decimal projected price
    * `"projected_return"` - Decimal expected return percentage
    * `"confidence"` - `"low"`, `"medium"`, or `"high"`
  """
  def project(current_price, predicted_fair_value, opts \\ [])

  def project(current_price, predicted_fair_value, opts)
      when is_number(current_price) and current_price > 0 and is_number(predicted_fair_value) do
    volatility = Keyword.get(opts, :volatility, 0.0) |> ensure_float()
    days_since_release = Keyword.get(opts, :days_since_release, 0) |> ensure_int()
    meta_share = Keyword.get(opts, :meta_share, 0.0) |> ensure_float()

    lambda = compute_lambda(volatility, days_since_release, meta_share)

    Map.new(@horizons, fn days ->
      projected = current_price + (predicted_fair_value - current_price) * (1 - :math.exp(-lambda * days))
      return_pct = (projected - current_price) / current_price
      confidence = compute_confidence(days, volatility, days_since_release)

      {Integer.to_string(days), %{
        "projected_price" => safe_decimal(projected),
        "projected_return" => safe_decimal(return_pct),
        "confidence" => confidence
      }}
    end)
  end

  def project(_current_price, _predicted_fair_value, _opts), do: %{}

  # --- Private ---

  defp compute_lambda(volatility, days_since_release, meta_share) do
    adjustment =
      min(volatility, 1.0) * 0.01 +
        if(days_since_release > 365, do: 0.005, else: 0.0) +
        if(meta_share > 0.01, do: 0.003, else: 0.0)

    (@base_lambda + adjustment)
    |> max(0.005)
    |> min(0.04)
  end

  defp compute_confidence(days, volatility, days_since_release) do
    # Short horizons + low volatility + established cards = high confidence
    horizon_score = cond do
      days <= 7 -> 2
      days <= 30 -> 1
      true -> 0
    end

    volatility_score = cond do
      volatility < 0.15 -> 2
      volatility < 0.35 -> 1
      true -> 0
    end

    age_score = cond do
      days_since_release > 180 -> 2
      days_since_release > 60 -> 1
      true -> 0
    end

    total = horizon_score + volatility_score + age_score

    cond do
      total >= 5 -> "high"
      total >= 3 -> "medium"
      true -> "low"
    end
  end

  defp safe_decimal(val) when is_float(val), do: Decimal.from_float(val)
  defp safe_decimal(val) when is_integer(val), do: Decimal.new(val)

  defp ensure_float(v) when is_float(v), do: v
  defp ensure_float(v) when is_integer(v), do: v / 1
  defp ensure_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp ensure_float(_), do: 0.0

  defp ensure_int(v) when is_integer(v), do: v
  defp ensure_int(v) when is_float(v), do: round(v)
  defp ensure_int(_), do: 0
end
