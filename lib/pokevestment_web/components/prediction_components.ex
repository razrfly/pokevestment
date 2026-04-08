defmodule PokevestmentWeb.PredictionComponents do
  @moduledoc """
  Reusable function components for displaying ML prediction data.
  """
  use Phoenix.Component

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

  @feature_labels %{
    "meta_share_30d" => "30-day Meta Share",
    "meta_share_90d" => "90-day Meta Share",
    "meta_share_all" => "All-time Meta Share",
    "top8_appearances_30d" => "Top 8 (30d)",
    "top8_appearances_90d" => "Top 8 (90d)",
    "top8_appearances_all" => "Top 8 (all-time)",
    "win_rate_30d" => "Win Rate (30d)",
    "win_rate_90d" => "Win Rate (90d)",
    "deck_diversity_30d" => "Deck Diversity (30d)",
    "deck_diversity_90d" => "Deck Diversity (90d)",
    "rarity_encoded" => "Rarity",
    "is_secret_rare" => "Secret Rare",
    "is_full_art" => "Full Art",
    "is_alternate_art" => "Alternate Art",
    "art_type_encoded" => "Art Type",
    "generation" => "Generation",
    "has_ability" => "Has Ability",
    "ability_count" => "Ability Count",
    "attack_count" => "Attack Count",
    "hp" => "HP",
    "retreat_cost" => "Retreat Cost",
    "weakness_count" => "Weaknesses",
    "resistance_count" => "Resistances",
    "total_attack_damage" => "Total Attack Damage",
    "max_attack_damage" => "Max Attack Damage",
    "energy_cost_total" => "Total Energy Cost",
    "secret_rare_ratio" => "Set Secret Rare Ratio",
    "secret_rare_count" => "Set Secret Rares",
    "card_count_total" => "Set Card Count",
    "era_encoded" => "Era",
    "set_age_days" => "Set Age (days)",
    "days_since_release" => "Days Since Release",
    "log_price_avg_7d" => "7-day Avg Price",
    "log_price_avg_30d" => "30-day Avg Price",
    "price_volatility_7d" => "7-day Price Volatility",
    "price_volatility_30d" => "30-day Price Volatility",
    "price_trend_7d" => "7-day Price Trend",
    "price_trend_30d" => "30-day Price Trend",
    "language_count" => "Language Availability",
    "illustrator_encoded" => "Illustrator",
    "illustrator_card_count" => "Illustrator Portfolio",
    "illustrator_avg_price" => "Illustrator Avg Price",
    "stage_encoded" => "Evolution Stage",
    "energy_type_encoded" => "Energy Type",
    "category_encoded" => "Category",
    "first_edition" => "First Edition",
    "is_shadowless" => "Shadowless"
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

  # Helpers

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
  defp to_float(n) when is_integer(n), do: n / 1
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

  defp feature_label(feature), do: Map.get(@feature_labels, feature, humanize_feature(feature))

  defp humanize_feature(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_driver_value(value) do
    v = to_float(value)
    sign = if v >= 0, do: "+", else: ""
    "#{sign}#{:erlang.float_to_binary(v, decimals: 4)}"
  end

  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol(nil), do: ""
  defp currency_symbol(_), do: ""
end
