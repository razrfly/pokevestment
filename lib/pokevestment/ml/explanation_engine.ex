defmodule Pokevestment.ML.ExplanationEngine do
  @moduledoc """
  Generates structured explanations for card predictions
  using the top SHAP drivers and feature descriptions.

  Returns a map with summary, positive_reasons, and negative_reasons
  for rich frontend display.
  """

  alias Pokevestment.ML.FeatureDescriptions

  @doc """
  Generates a structured explanation map for a prediction.

  Returns:
    %{
      "summary" => "Human-readable summary with prices...",
      "positive_reasons" => [%{"feature" => ..., "label" => ..., "explanation" => ...}, ...],
      "negative_reasons" => [%{"feature" => ..., "label" => ..., "explanation" => ...}, ...]
    }
  """
  def generate(%{signal: "INSUFFICIENT_DATA"}) do
    %{
      "summary" => "Not enough pricing data to generate a prediction for this card.",
      "positive_reasons" => [],
      "negative_reasons" => []
    }
  end

  def generate(%{signal: signal} = prediction) do
    top_pos = sorted_drivers(prediction[:top_positive_drivers] || %{}, :desc)
    top_neg = sorted_drivers(prediction[:top_negative_drivers] || %{}, :asc)

    summary = build_summary(signal, prediction, top_pos, top_neg)
    positive_reasons = build_reasons(top_pos, 3)
    negative_reasons = build_reasons(top_neg, 2)

    %{
      "summary" => summary,
      "positive_reasons" => positive_reasons,
      "negative_reasons" => negative_reasons
    }
  end

  def generate(_), do: nil

  # --- Private ---

  defp build_summary(signal, prediction, top_pos, top_neg) do
    current = format_price(prediction[:current_price], prediction[:price_currency])
    fair = format_price(prediction[:predicted_fair_value], prediction[:price_currency])
    gap = compute_gap_pct(prediction[:current_price], prediction[:predicted_fair_value])

    case signal_category(signal) do
      :bullish ->
        intensity = if signal == "STRONG_BUY", do: "significantly undervalued", else: "undervalued"
        base = "This card looks #{intensity} — #{current} vs fair value #{fair}, #{gap} upside."
        add_counter(base, top_neg)

      :neutral ->
        pos_text = top_pos |> Enum.take(2) |> Enum.map(&driver_phrase/1) |> join_drivers()
        neg_text = top_neg |> Enum.take(2) |> Enum.map(&driver_phrase/1) |> join_drivers()

        cond do
          pos_text != nil and neg_text != nil ->
            "This card is fairly priced at #{current}. #{pos_text} adds value, but #{neg_text} holds it back."

          pos_text != nil ->
            "This card is fairly priced at #{current}, supported by #{pos_text}."

          neg_text != nil ->
            "This card is fairly priced at #{current} despite #{neg_text}."

          true ->
            "This card is fairly priced at #{current} based on the model's analysis."
        end

      :bearish ->
        base = "This card appears overpriced at #{current} — fair value is #{fair}, #{gap} downside."
        case Enum.take(top_pos, 1) do
          [{feature, _}] ->
            "#{base} #{FeatureDescriptions.label(feature)} provides some support."
          _ ->
            base
        end
    end
  end

  defp build_reasons(sorted_drivers, take_n) do
    sorted_drivers
    |> Enum.take(take_n)
    |> Enum.map(fn {feature, value} ->
      shap_val = to_float(value)
      %{
        "feature" => feature,
        "label" => FeatureDescriptions.label(feature),
        "explanation" => FeatureDescriptions.explain_direction(feature, shap_val)
      }
    end)
  end

  defp add_counter(base, top_neg) do
    case Enum.take(top_neg, 1) do
      [{feature, _}] ->
        label = FeatureDescriptions.label(feature) |> String.downcase()
        "#{base} However, #{label} weighs against it."

      _ ->
        base
    end
  end

  defp signal_category("STRONG_BUY"), do: :bullish
  defp signal_category("BUY"), do: :bullish
  defp signal_category("HOLD"), do: :neutral
  defp signal_category("OVERVALUED"), do: :bearish
  defp signal_category(_), do: :neutral

  defp driver_phrase({feature, _value}) do
    label = FeatureDescriptions.label(feature) |> String.downcase()
    "its #{label}"
  end

  defp join_drivers([]), do: nil
  defp join_drivers([single]), do: single

  defp join_drivers(phrases) do
    {last, rest} = List.pop_at(phrases, -1)
    Enum.join(rest, ", ") <> " and " <> last
  end

  defp format_price(nil, _currency), do: "N/A"

  defp format_price(price, currency) do
    symbol = currency_symbol(currency)
    val = to_float(price)
    "#{symbol}#{:erlang.float_to_binary(val, decimals: 2)}"
  end

  defp compute_gap_pct(nil, _), do: "0%"
  defp compute_gap_pct(_, nil), do: "0%"

  defp compute_gap_pct(current, fair) do
    c = to_float(current)
    f = to_float(fair)

    if c > 0 do
      pct = abs((f - c) / c * 100)
      "#{round(pct)}%"
    else
      "0%"
    end
  end

  defp currency_symbol("EUR"), do: "\u20AC"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol(_), do: "$"

  defp sorted_drivers(drivers, direction) when is_map(drivers) do
    drivers
    |> Enum.sort_by(fn {_f, v} -> to_float(v) end, direction)
    |> Enum.reject(fn {_f, v} -> to_float(v) == 0.0 end)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1
  defp to_float(_), do: 0.0
end
