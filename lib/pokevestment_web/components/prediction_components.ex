defmodule PokevestmentWeb.PredictionComponents do
  @moduledoc """
  Reusable function components for displaying ML prediction data.
  """
  use Phoenix.Component

  alias Pokevestment.ML.FeatureDescriptions

  @signal_colors %{
    "STRONG_BUY" => "bg-emerald-700 text-emerald-50 dark:bg-emerald-500/20 dark:text-emerald-400",
    "BUY" => "bg-lime-700 text-lime-50 dark:bg-lime-500/20 dark:text-lime-400",
    "HOLD" => "bg-olive-600 text-olive-50 dark:bg-olive-500/20 dark:text-olive-400",
    "OVERVALUED" => "bg-red-700 text-red-50 dark:bg-red-500/20 dark:text-red-400",
    "INSUFFICIENT_DATA" => "bg-gray-500 text-gray-50 dark:bg-gray-500/20 dark:text-gray-400"
  }

  @umbrella_icons %{
    "tournament_meta" => "🏆",
    "rarity_collectibility" => "🎨",
    "species" => "🧬",
    "supply_proxy" => "📅",
    "price_momentum" => "💰",
    "card_attributes" => "⚔️",
    "illustrator" => "🎭"
  }

  # Signal badge

  attr :signal, :string, required: true

  def signal_badge(assigns) do
    assigns = assign(assigns, :colors, Map.get(@signal_colors, assigns.signal, "bg-gray-500 text-gray-50"))

    ~H"""
    <span class={["inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold", @colors]}>
      {format_signal(@signal)}
    </span>
    """
  end

  # Value display

  attr :current_price, :any, required: true
  attr :predicted_fair_value, :any, required: true
  attr :value_ratio, :any, required: true
  attr :price_currency, :string, default: nil

  def value_display(assigns) do
    assigns = assign(assigns, :symbol, currency_symbol(assigns.price_currency))

    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <span class="text-olive-700 dark:text-olive-300">
        {@symbol}{format_decimal(@current_price)}
      </span>
      <span class="text-olive-400 dark:text-olive-600">→</span>
      <span class="font-semibold text-olive-900 dark:text-olive-100">
        {@symbol}{format_decimal(@predicted_fair_value)}
      </span>
      <span class={ratio_color(@value_ratio)}>
        ({format_decimal(@value_ratio)}x)
      </span>
    </div>
    """
  end

  # Marketplace link

  attr :urls, :map, required: true
  attr :price_source, :string, default: nil

  def marketplace_link(assigns) do
    # Show the link matching the prediction's price source, or fall back to first available
    url =
      if assigns.price_source do
        Map.get(assigns.urls, assigns.price_source) || Map.values(assigns.urls) |> List.first()
      else
        Map.values(assigns.urls) |> List.first()
      end

    source_label =
      case assigns.price_source do
        "tcgplayer" -> "TCGPlayer"
        "cardmarket" -> "Cardmarket"
        _ -> "Marketplace"
      end

    assigns = assign(assigns, url: url, source_label: source_label)

    ~H"""
    <a
      :if={@url}
      href={@url}
      target="_blank"
      rel="noopener noreferrer"
      class="mt-1 inline-flex items-center gap-1 text-xs text-olive-500 hover:text-olive-700 dark:text-olive-500 dark:hover:text-olive-300"
    >
      {@source_label} &#8599;
    </a>
    """
  end

  # Umbrella breakdown

  attr :breakdown, :map, required: true

  def umbrella_breakdown(assigns) do
    sorted =
      assigns.breakdown
      |> Enum.sort_by(fn {_k, v} -> -abs(to_float(v)) end)

    max_val =
      sorted
      |> Enum.map(fn {_k, v} -> abs(to_float(v)) end)
      |> Enum.max(fn -> 1.0 end)

    assigns = assign(assigns, sorted: sorted, max_val: max_val)

    ~H"""
    <div class="space-y-2">
      <div :for={{category, value} <- @sorted} class="flex items-center gap-2">
        <span class="w-5 text-center" title={category}>
          {umbrella_icon(category)}
        </span>
        <span class="w-36 truncate text-xs text-olive-700 dark:text-olive-400">
          {format_umbrella_name(category)}
        </span>
        <div class="flex-1">
          <div class="h-2 rounded-full bg-olive-200 dark:bg-olive-800">
            <div
              class={[
                "h-2 rounded-full",
                if(to_float(value) >= 0, do: "bg-emerald-500 dark:bg-emerald-600", else: "bg-red-500 dark:bg-red-600")
              ]}
              style={"width: #{bar_width(value, @max_val)}%"}
            />
          </div>
        </div>
        <span class="w-12 text-right text-xs tabular-nums text-olive-600 dark:text-olive-500">
          {format_contribution(value)}
        </span>
      </div>
    </div>
    """
  end

  # Driver list

  attr :drivers, :map, required: true
  attr :kind, :atom, required: true, values: [:positive, :negative]

  def driver_list(assigns) do
    sorted =
      assigns.drivers
      |> Enum.sort_by(fn {_k, v} ->
        if assigns.kind == :positive, do: -to_float(v), else: to_float(v)
      end)
      |> Enum.take(5)

    assigns = assign(assigns, sorted: sorted)

    ~H"""
    <div class="space-y-1">
      <div :for={{feature, value} <- @sorted} class="flex items-center justify-between text-xs">
        <span class="truncate text-olive-700 dark:text-olive-400">
          {feature_label(feature)}
        </span>
        <span class={[
          "ml-2 tabular-nums font-medium",
          if(@kind == :positive, do: "text-emerald-600 dark:text-emerald-400", else: "text-red-600 dark:text-red-400")
        ]}>
          {format_driver_value(value)}
        </span>
      </div>
    </div>
    """
  end

  # Explanation text

  attr :explanation, :string, required: true

  def explanation_text(assigns) do
    ~H"""
    <p class="text-sm text-olive-700 dark:text-olive-300 italic">
      {@explanation}
    </p>
    """
  end

  # Explanation panel (structured map version)

  attr :explanation, :map, required: true

  def explanation_panel(assigns) do
    explanation = assigns.explanation || %{}
    positive = explanation["positive_reasons"] || []
    negative = explanation["negative_reasons"] || []

    assigns =
      assigns
      |> assign(:explanation, explanation)
      |> assign(:positive_reasons, positive)
      |> assign(:negative_reasons, negative)

    ~H"""
    <div class="space-y-3">
      <p class="text-sm font-medium text-olive-800 dark:text-olive-200">
        {@explanation["summary"]}
      </p>

      <ul :if={@positive_reasons != []} class="space-y-1.5">
        <li :for={reason <- @positive_reasons} class="flex items-start gap-2 text-sm">
          <span class="mt-1 block h-1.5 w-1.5 flex-shrink-0 rounded-full bg-emerald-500" />
          <span>
            <span class="font-medium text-emerald-700 dark:text-emerald-400">{reason["label"]}</span>
            <span class="text-olive-600 dark:text-olive-400"> — {reason["explanation"]}</span>
          </span>
        </li>
      </ul>

      <ul :if={@negative_reasons != []} class="space-y-1.5">
        <li :for={reason <- @negative_reasons} class="flex items-start gap-2 text-sm">
          <span class="mt-1 block h-1.5 w-1.5 flex-shrink-0 rounded-full bg-red-500" />
          <span>
            <span class="font-medium text-red-700 dark:text-red-400">{reason["label"]}</span>
            <span class="text-olive-600 dark:text-olive-400"> — {reason["explanation"]}</span>
          </span>
        </li>
      </ul>
    </div>
    """
  end

  # Projection table (full table version with confidence)

  attr :projections, :map, required: true
  attr :currency, :string, default: nil

  @confidence_colors %{
    "high" => "bg-emerald-100 text-emerald-800 dark:bg-emerald-500/20 dark:text-emerald-400",
    "medium" => "bg-amber-100 text-amber-800 dark:bg-amber-500/20 dark:text-amber-400",
    "low" => "bg-olive-100 text-olive-700 dark:bg-olive-500/20 dark:text-olive-400"
  }

  def projection_table(assigns) do
    sorted =
      assigns.projections
      |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)

    assigns = assign(assigns, sorted: sorted, symbol: currency_symbol(assigns.currency))

    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-olive-200 dark:border-olive-700">
            <th class="py-2 pr-4 text-left text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">Horizon</th>
            <th class="py-2 pr-4 text-right text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">Price</th>
            <th class="py-2 pr-4 text-right text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">Return</th>
            <th class="py-2 text-center text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">Confidence</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{horizon, data} <- @sorted} class="border-b border-olive-100 last:border-0 dark:border-olive-800">
            <td class="py-2 pr-4 text-sm font-medium text-olive-900 dark:text-olive-100">
              {horizon_label(horizon)}
            </td>
            <td class="py-2 pr-4 text-right text-sm tabular-nums font-semibold text-olive-900 dark:text-olive-100">
              {@symbol}{format_decimal(data["projected_price"])}
            </td>
            <td class={["py-2 pr-4 text-right text-sm tabular-nums font-medium", return_color_class(data["projected_return"])]}>
              {format_return(data["projected_return"])}
            </td>
            <td class="py-2 text-center">
              <span class={[
                "inline-flex rounded-full px-2 py-0.5 text-xs font-medium",
                confidence_color(data["confidence"])
              ]}>
                {data["confidence"] || "—"}
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      <p class="mt-2 text-xs text-olive-400 dark:text-olive-600">
        Based on variable-rate convergence model adjusted for volatility, card age, and meta presence.
      </p>
    </div>
    """
  end

  # Horizon projections (original compact version, kept for backward compat)

  @horizon_labels %{"1" => "1d", "7" => "7d", "30" => "30d", "90" => "90d", "365" => "1yr"}

  def horizon_projections(assigns) do
    sorted =
      assigns.projections
      |> Enum.sort_by(fn {k, _v} -> String.to_integer(k) end)

    cols = sorted |> length() |> min(5) |> max(1)

    assigns = assign(assigns, sorted: sorted, symbol: currency_symbol(assigns.currency), cols: cols)

    ~H"""
    <div class="grid gap-2 text-center" style={"grid-template-columns: repeat(#{@cols}, minmax(0, 1fr))"}>
      <div :for={{horizon, data} <- @sorted} class="space-y-0.5">
        <span class="block text-[10px] font-medium uppercase tracking-wider text-olive-500 dark:text-olive-500">
          {horizon_label(horizon)}
        </span>
        <span class="block text-xs font-semibold text-olive-900 dark:text-olive-100">
          {@symbol}{format_decimal(data["projected_price"])}
        </span>
        <span class={["block text-[10px] font-medium tabular-nums", return_color_class(data["projected_return"])]}>
          {format_return(data["projected_return"])}
        </span>
      </div>
    </div>
    """
  end

  # Helpers

  defp horizon_label(key), do: Map.get(@horizon_labels, key, "#{key}d")

  defp return_color_class(nil), do: "text-olive-500"

  defp return_color_class(%Decimal{} = d) do
    case Decimal.compare(d, Decimal.new(0)) do
      :gt -> "text-emerald-600 dark:text-emerald-400"
      :lt -> "text-red-600 dark:text-red-400"
      _ -> "text-olive-500 dark:text-olive-500"
    end
  end

  defp return_color_class(n) when is_number(n) do
    cond do
      n > 0 -> "text-emerald-600 dark:text-emerald-400"
      n < 0 -> "text-red-600 dark:text-red-400"
      true -> "text-olive-500 dark:text-olive-500"
    end
  end

  defp return_color_class(_), do: "text-olive-500"

  defp format_return(nil), do: "—"

  defp format_return(%Decimal{} = d) do
    val = Decimal.to_float(d) * 100
    sign = if val >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(val, decimals: 1)}%"
  end

  defp format_return(n) when is_number(n) do
    val = n * 100
    sign = if val >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(val, decimals: 1)}%"
  end

  defp format_return(_), do: "—"

  defp format_signal(signal) do
    signal
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_decimal(nil), do: "—"
  defp format_decimal(%Decimal{} = d), do: Decimal.round(d, 2) |> Decimal.to_string()
  defp format_decimal(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 2)
  defp format_decimal(n) when is_integer(n), do: Integer.to_string(n)
  defp format_decimal(n) when is_binary(n), do: n

  defp ratio_color(nil), do: "text-olive-500 dark:text-olive-500"

  defp ratio_color(%Decimal{} = d) do
    if Decimal.compare(d, Decimal.new(1)) in [:gt, :eq],
      do: "text-emerald-600 dark:text-emerald-400",
      else: "text-red-600 dark:text-red-400"
  end

  defp ratio_color(_), do: "text-olive-500 dark:text-olive-500"

  defp umbrella_icon(category), do: Map.get(@umbrella_icons, category, "📊")

  defp format_umbrella_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_float(n), do: n
  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(_), do: 0.0

  defp bar_width(value, max_val) when max_val > 0 do
    (abs(to_float(value)) / max_val * 100) |> Float.round(1)
  end

  defp bar_width(_, _), do: 0

  defp format_contribution(value) do
    v = to_float(value)
    sign = if v >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(v * 100, decimals: 1)}%"
  end

  defp feature_label(feature), do: FeatureDescriptions.label(feature)

  defp format_driver_value(value) do
    v = to_float(value)
    sign = if v >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(v, decimals: 4)}"
  end

  defp confidence_color(level), do: Map.get(@confidence_colors, level, "bg-olive-100 text-olive-700")

  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol(nil), do: ""
  defp currency_symbol(_), do: ""
end
