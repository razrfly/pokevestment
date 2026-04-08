defmodule Pokevestment.ML.FeatureDescriptions do
  @moduledoc """
  Registry mapping ML feature names to human-readable labels, descriptions,
  directional explanations, and umbrella categories.

  Single source of truth for feature display — replaces the `@feature_labels`
  map previously maintained in `PredictionComponents`.
  """

  @descriptions %{
    # --- Tournament & Meta ---
    "tournament_appearances" => %{
      label: "Tournament Appearances",
      description: "Number of tournaments where this card appeared in a registered deck",
      high: "Frequently played in tournament decks — strong competitive demand",
      low: "Rarely appears in tournament play",
      category: "tournament_meta"
    },
    "total_deck_inclusions" => %{
      label: "Total Deck Inclusions",
      description: "Total number of tournament decks that included this card",
      high: "Widely adopted across many decks — staple card",
      low: "Niche or rarely included in decks",
      category: "tournament_meta"
    },
    "avg_copies_per_deck" => %{
      label: "Avg Copies per Deck",
      description: "Average number of copies of this card in decks that run it",
      high: "Typically played as a 3-4 copy staple",
      low: "Usually a 1-of tech card",
      category: "tournament_meta"
    },
    "meta_share_total" => %{
      label: "All-time Meta Share",
      description: "Percentage of all tournament decks that include this card",
      high: "Format-defining staple with wide adoption",
      low: "Minimal competitive presence",
      category: "tournament_meta"
    },
    "meta_share_30d" => %{
      label: "30-day Meta Share",
      description: "How often this card appears in competitive tournament decks over the last 30 days",
      high: "Heavily played in the current competitive meta — increases demand",
      low: "Rarely seen in recent competitive play",
      category: "tournament_meta"
    },
    "meta_share_90d" => %{
      label: "90-day Meta Share",
      description: "How often this card appears in competitive tournament decks over the last 90 days",
      high: "Consistently played over the recent season",
      low: "Low recent competitive presence",
      category: "tournament_meta"
    },
    "archetype_count" => %{
      label: "Archetype Count",
      description: "Number of distinct deck archetypes that use this card",
      high: "Versatile card used across many deck types",
      low: "Locked to a single archetype",
      category: "tournament_meta"
    },
    "top_8_appearances" => %{
      label: "Top 8 Appearances",
      description: "Number of times this card appeared in a Top 8 tournament finish",
      high: "Proven winner — consistently in top-performing decks",
      low: "Rarely seen in winning decks",
      category: "tournament_meta"
    },
    "top_8_rate" => %{
      label: "Top 8 Rate",
      description: "Percentage of tournament appearances that resulted in a Top 8 finish",
      high: "High win rate when included in decks",
      low: "Included in decks but rarely reaches Top 8",
      category: "tournament_meta"
    },
    "avg_placing" => %{
      label: "Average Placing",
      description: "Average tournament placement of decks containing this card",
      high: "Higher average placing — less successful in tournaments",
      low: "Lower average placing — more successful in tournaments",
      category: "tournament_meta"
    },
    "avg_win_rate" => %{
      label: "Average Win Rate",
      description: "Average win rate of decks containing this card",
      high: "Decks with this card win more often",
      low: "Decks with this card tend to underperform",
      category: "tournament_meta"
    },
    "meta_trend" => %{
      label: "Meta Trend",
      description: "Whether this card's meta share is increasing or decreasing over time",
      high: "Rising competitive popularity — increasing demand expected",
      low: "Declining competitive relevance",
      category: "tournament_meta"
    },
    "weighted_tournament_score" => %{
      label: "Tournament Score",
      description: "Composite tournament performance score weighting recency and placement",
      high: "Strong recent tournament performance",
      low: "Weak tournament impact",
      category: "tournament_meta"
    },

    # --- Rarity & Collectibility ---
    "rarity" => %{
      label: "Rarity",
      description: "The card's printed rarity level",
      high: "Higher rarity — more collectible and scarcer",
      low: "Common rarity — widely available",
      category: "rarity_collectibility"
    },
    "art_type" => %{
      label: "Art Type",
      description: "Special art treatment (full art, alternate art, etc.)",
      high: "Premium art treatment — collector premium",
      low: "Standard art",
      category: "rarity_collectibility"
    },
    "is_full_art" => %{
      label: "Full Art",
      description: "Whether the card has full-art illustration extending to the borders",
      high: "Full art card — commands collector premium",
      low: "Standard card frame",
      category: "rarity_collectibility"
    },
    "is_alternate_art" => %{
      label: "Alternate Art",
      description: "Whether the card has an alternate or special illustration",
      high: "Alternate art variant — highly sought by collectors",
      low: "Standard illustration",
      category: "rarity_collectibility"
    },
    "is_secret_rare" => %{
      label: "Secret Rare",
      description: "Whether the card is numbered beyond the set's official card count",
      high: "Secret rare — extremely limited pull rate",
      low: "Standard numbered card",
      category: "rarity_collectibility"
    },
    "first_edition" => %{
      label: "First Edition",
      description: "Whether this is a First Edition printing",
      high: "First Edition stamp — significant collector premium",
      low: "Unlimited or later printing",
      category: "rarity_collectibility"
    },
    "is_shadowless" => %{
      label: "Shadowless",
      description: "Whether this is a Shadowless printing (early Base Set variant)",
      high: "Shadowless variant — very rare and valuable to collectors",
      low: "Standard shadow border",
      category: "rarity_collectibility"
    },
    "has_first_edition_stamp" => %{
      label: "First Edition Stamp",
      description: "Whether the card bears a First Edition stamp",
      high: "Has First Edition stamp — collectible premium",
      low: "No First Edition stamp",
      category: "rarity_collectibility"
    },
    "language_count" => %{
      label: "Language Availability",
      description: "Number of languages this card was printed in",
      high: "Available in many languages — wider collector base",
      low: "Limited language availability — can indicate exclusivity",
      category: "rarity_collectibility"
    },
    "secret_rare_ratio" => %{
      label: "Set Secret Rare Ratio",
      description: "Proportion of secret rares in this card's set",
      high: "Set has many secret rares — more competition for collector attention",
      low: "Few secret rares in set — each one gets more attention",
      category: "rarity_collectibility"
    },

    # --- Card Attributes ---
    "hp" => %{
      label: "HP",
      description: "The card's hit points",
      high: "High HP — indicates powerful or evolved Pokemon",
      low: "Low HP — basic or support Pokemon",
      category: "card_attributes"
    },
    "retreat_cost" => %{
      label: "Retreat Cost",
      description: "Energy required to retreat this Pokemon",
      high: "High retreat cost — less flexible in play",
      low: "Low retreat cost — more versatile",
      category: "card_attributes"
    },
    "attack_count" => %{
      label: "Attack Count",
      description: "Number of attacks the card has",
      high: "Multiple attacks — more versatile in battle",
      low: "Single attack — more focused role",
      category: "card_attributes"
    },
    "total_attack_damage" => %{
      label: "Total Attack Damage",
      description: "Sum of all attack damage values",
      high: "High total damage output",
      low: "Low damage — likely a support card",
      category: "card_attributes"
    },
    "max_attack_damage" => %{
      label: "Max Attack Damage",
      description: "Highest single-attack damage value",
      high: "Powerful main attack",
      low: "Low max damage",
      category: "card_attributes"
    },
    "has_ability" => %{
      label: "Has Ability",
      description: "Whether the card has a Pokemon Ability",
      high: "Has an Ability — adds strategic depth and often increases value",
      low: "No Ability",
      category: "card_attributes"
    },
    "ability_count" => %{
      label: "Ability Count",
      description: "Number of Abilities on the card",
      high: "Multiple Abilities — rare and potentially powerful",
      low: "No special Abilities",
      category: "card_attributes"
    },
    "weakness_count" => %{
      label: "Weaknesses",
      description: "Number of type weaknesses",
      high: "More weaknesses — more exploitable in battle",
      low: "Fewer weaknesses — more resilient",
      category: "card_attributes"
    },
    "resistance_count" => %{
      label: "Resistances",
      description: "Number of type resistances",
      high: "More resistances — harder to take down",
      low: "No resistances",
      category: "card_attributes"
    },
    "energy_cost_total" => %{
      label: "Total Energy Cost",
      description: "Total energy required across all attacks",
      high: "High energy cost — slower to set up",
      low: "Low energy cost — fast attacker",
      category: "card_attributes"
    },
    "type_count" => %{
      label: "Type Count",
      description: "Number of Pokemon types on this card",
      high: "Dual type — potentially more versatile",
      low: "Single type",
      category: "card_attributes"
    },
    "stage" => %{
      label: "Evolution Stage",
      description: "The card's evolution stage (Basic, Stage 1, Stage 2, etc.)",
      high: "Higher evolution stage — typically more powerful",
      low: "Basic stage — foundation card",
      category: "card_attributes"
    },
    "category" => %{
      label: "Category",
      description: "Card category (Pokemon, Trainer, Energy)",
      high: "Category affects playability and collector appeal differently",
      low: "Category affects playability and collector appeal differently",
      category: "card_attributes"
    },
    "energy_type" => %{
      label: "Energy Type",
      description: "The Pokemon's energy type (Fire, Water, etc.)",
      high: "Popular energy types often have more competitive support",
      low: "Energy type may have less meta support",
      category: "card_attributes"
    },

    # --- Price Momentum ---
    "price_momentum_7d" => %{
      label: "7-day Price Momentum",
      description: "Price change direction and magnitude over the last 7 days",
      high: "Price trending upward recently — positive momentum",
      low: "Price trending downward recently — negative momentum",
      category: "price_momentum"
    },
    "price_momentum_30d" => %{
      label: "30-day Price Momentum",
      description: "Price change direction and magnitude over the last 30 days",
      high: "Sustained price increase over the past month",
      low: "Price declining over the past month",
      category: "price_momentum"
    },
    "price_volatility" => %{
      label: "Price Volatility",
      description: "How much the card's price fluctuates",
      high: "Volatile pricing — higher risk but potential for gains",
      low: "Stable pricing — lower risk, more predictable",
      category: "price_momentum"
    },
    "price_currency" => %{
      label: "Price Currency",
      description: "Currency of the price data (USD or EUR)",
      high: "Price source market indicator",
      low: "Price source market indicator",
      category: "price_momentum"
    },

    # --- Supply Proxy ---
    "set_card_count" => %{
      label: "Set Card Count",
      description: "Total number of cards in this card's set",
      high: "Large set — more cards competing for attention",
      low: "Small set — each card gets more focus",
      category: "supply_proxy"
    },
    "era" => %{
      label: "Era",
      description: "The Pokemon TCG era this card belongs to (e.g. Scarlet & Violet, Sword & Shield)",
      high: "Era affects print runs, availability, and nostalgia value",
      low: "Era affects print runs, availability, and nostalgia value",
      category: "supply_proxy"
    },
    "days_since_release" => %{
      label: "Days Since Release",
      description: "How many days since the card's set was released",
      high: "Older card — potentially out of print and scarcer",
      low: "Recently released — still in active print runs",
      category: "supply_proxy"
    },
    "set_age_bucket" => %{
      label: "Set Age Bucket",
      description: "Grouped age category of the set (new, recent, modern, vintage)",
      high: "Older age bracket — increased scarcity potential",
      low: "Newer age bracket — still widely available",
      category: "supply_proxy"
    },
    "legal_standard" => %{
      label: "Standard Legal",
      description: "Whether the card is legal in Standard format tournament play",
      high: "Standard legal — playable in the most popular format, higher demand",
      low: "Rotated out of Standard — competitive demand limited to Expanded",
      category: "supply_proxy"
    },
    "legal_expanded" => %{
      label: "Expanded Legal",
      description: "Whether the card is legal in Expanded format tournament play",
      high: "Expanded legal — playable in a wider card pool",
      low: "Not legal in Expanded",
      category: "supply_proxy"
    },

    # --- Species ---
    "species_generation" => %{
      label: "Species Generation",
      description: "Which Pokemon generation this species debuted in",
      high: "Earlier generations often carry nostalgia premium",
      low: "Newer generation — less nostalgia but potentially trendy",
      category: "species"
    },
    "is_legendary" => %{
      label: "Legendary",
      description: "Whether this Pokemon is classified as a Legendary",
      high: "Legendary Pokemon — iconic and collectible",
      low: "Regular Pokemon",
      category: "species"
    },
    "is_mythical" => %{
      label: "Mythical",
      description: "Whether this Pokemon is classified as Mythical",
      high: "Mythical Pokemon — rare and highly sought after",
      low: "Non-mythical Pokemon",
      category: "species"
    },
    "is_baby" => %{
      label: "Baby Pokemon",
      description: "Whether this is a baby pre-evolution Pokemon",
      high: "Baby Pokemon — cute factor adds collector appeal",
      low: "Not a baby Pokemon",
      category: "species"
    },
    "capture_rate" => %{
      label: "Capture Rate",
      description: "In-game capture difficulty (lower = harder to catch = rarer)",
      high: "Easy to catch in games — common species",
      low: "Hard to catch — rare and desirable species",
      category: "species"
    },
    "base_happiness" => %{
      label: "Base Happiness",
      description: "The Pokemon's base friendship value in the games",
      high: "Higher base happiness",
      low: "Lower base happiness — may indicate fiercer Pokemon",
      category: "species"
    },
    "growth_rate" => %{
      label: "Growth Rate",
      description: "The Pokemon's experience growth rate category",
      high: "Growth rate category indicator",
      low: "Growth rate category indicator",
      category: "species"
    },
    "dex_id_count" => %{
      label: "Dex Entry Count",
      description: "How many regional Pokedexes include this species",
      high: "Appears in many regional dexes — widely recognized species",
      low: "Appears in few dexes — more obscure species",
      category: "species"
    },
    "has_evolution" => %{
      label: "Has Evolution",
      description: "Whether this species has an evolution chain",
      high: "Part of an evolution line — may benefit from related card synergies",
      low: "Standalone Pokemon — no evolution chain",
      category: "species"
    },

    # --- Illustrator ---
    "illustrator_frequency" => %{
      label: "Illustrator Portfolio Size",
      description: "How many cards this illustrator has done",
      high: "Prolific illustrator — well-known in the community",
      low: "Rare illustrator — fewer cards may mean niche appeal",
      category: "illustrator"
    },
    "illustrator_avg_price" => %{
      label: "Illustrator Avg Price",
      description: "Average price of cards by the same illustrator",
      high: "Illustrator's cards tend to command higher prices",
      low: "Illustrator's cards are typically lower priced",
      category: "illustrator"
    }
  }

  @doc "Returns the full description map for a feature, or nil."
  def get(feature_name), do: Map.get(@descriptions, feature_name)

  @doc "Returns all feature descriptions."
  def all, do: @descriptions

  @doc "Returns the human-readable label for a feature."
  def label(feature_name) do
    case get(feature_name) do
      %{label: label} -> label
      nil -> humanize(feature_name)
    end
  end

  @doc """
  Returns a directional explanation for a feature's SHAP contribution.
  Positive SHAP = feature pushes price up; negative = pushes price down.
  """
  def explain_direction(feature_name, shap_value) when is_number(shap_value) do
    case get(feature_name) do
      %{high: high, low: low} ->
        if shap_value >= 0, do: high, else: low

      nil ->
        if shap_value >= 0,
          do: "#{humanize(feature_name)} increases predicted value",
          else: "#{humanize(feature_name)} decreases predicted value"
    end
  end

  @doc "Returns the category for a feature."
  def category(feature_name) do
    case get(feature_name) do
      %{category: cat} -> cat
      nil -> "other"
    end
  end

  defp humanize(name) do
    name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
