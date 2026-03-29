defmodule Pokevestment.Ingestion.FeatureExtractor do
  @moduledoc """
  Pure functions to compute ML feature columns from card data.
  No database access — all functions are side-effect free.
  """

  # Rarity → {art_type, is_full_art, is_alternate_art}
  @rarity_mapping %{
    # Standard rarities
    "Common" => {"standard", false, false},
    "Uncommon" => {"standard", false, false},
    "Rare" => {"standard", false, false},
    "None" => {"standard", false, false},
    # Holo rarities
    "Holo Rare" => {"holo", false, false},
    "Rare Holo" => {"holo", false, false},
    # Premium holo (LV.X, PRIME, LEGEND)
    "Rare Holo LV.X" => {"premium_holo", true, false},
    "Rare PRIME" => {"premium_holo", true, false},
    "LEGEND" => {"premium_holo", true, false},
    # Mechanic ultra (V/VMAX/VSTAR)
    "Holo Rare V" => {"mechanic_ultra", true, false},
    "Holo Rare VMAX" => {"mechanic_ultra", true, false},
    "Holo Rare VSTAR" => {"mechanic_ultra", true, false},
    # Full art / Ultra Rare
    "Ultra Rare" => {"full_art", true, true},
    "Full Art Trainer" => {"full_art", true, true},
    # Illustration rares
    "Illustration rare" => {"illustration", true, true},
    "Special illustration rare" => {"special_illustration", true, true},
    # Hyper rare
    "Hyper rare" => {"hyper_rare", true, true},
    # Amazing rare
    "Amazing Rare" => {"amazing", false, true},
    # Shiny rarities (is_full_art varies)
    "Shiny rare" => {"shiny", false, true},
    "Shiny rare V" => {"shiny", true, true},
    "Shiny rare VMAX" => {"shiny", true, true},
    "Shiny Ultra Rare" => {"shiny", true, true},
    # Crown
    "Crown" => {"crown", true, true},
    # Secret rare
    "Secret Rare" => {"secret", true, true},
    # ACE SPEC
    "ACE SPEC Rare" => {"ace_spec", false, false},
    # Double/Mega ultra
    "Double rare" => {"ultra", true, true},
    "Mega Hyper Rare" => {"ultra", true, true},
    # Pocket TCG diamond rarities
    "One Diamond" => {"standard", false, false},
    "Two Diamond" => {"standard", false, false},
    "Three Diamond" => {"standard", false, false},
    "Four Diamond" => {"holo", false, false},
    # Pocket TCG star rarities
    "One Star" => {"illustration", true, true},
    "Two Star" => {"special_illustration", true, true},
    "Three Star" => {"crown", true, true},
    # Pocket TCG shiny rarities
    "One Shiny" => {"shiny", false, true},
    "Two Shiny" => {"shiny", true, true},
    # Miscellaneous
    "Classic Collection" => {"standard", false, true},
    "Radiant Rare" => {"amazing", false, true},
    "Black White Rare" => {"standard", false, false}
  }

  @doc """
  Compute art type features from a card's rarity string.

  Accepts a map with `:rarity` or `"rarity"` key.
  Returns `%{art_type: string, is_full_art: boolean, is_alternate_art: boolean}`.
  """
  def compute_art_features(data) when is_map(data) do
    rarity = Map.get(data, :rarity) || Map.get(data, "rarity")

    {art_type, is_full_art, is_alternate_art} =
      Map.get(@rarity_mapping, rarity, {"standard", false, false})

    %{
      art_type: art_type,
      is_full_art: is_full_art,
      is_alternate_art: is_alternate_art
    }
  end

  # Series ID → era mapping (all 21 series in DB)
  @era_mapping %{
    "base" => "wotc",
    "gym" => "wotc",
    "neo" => "wotc",
    "lc" => "wotc",
    "ecard" => "e_series",
    "ex" => "ex",
    "pop" => "ex",
    "dp" => "dp",
    "pl" => "dp",
    "hgss" => "hgss",
    "col" => "hgss",
    "bw" => "bw",
    "xy" => "xy",
    "sm" => "sm",
    "swsh" => "swsh",
    "sv" => "sv",
    "me" => "mega",
    "mc" => "promo",
    "misc" => "promo",
    "tk" => "promo",
    "tcgp" => "promo"
  }

  @doc """
  Compute set-level supply proxy features from set data.

  Accepts a map with `:series_id`, `:card_count_official`, and `:card_count_total`.
  Returns `%{secret_rare_count, secret_rare_ratio, era}`.
  """
  def compute_set_features(data) when is_map(data) do
    official = Map.get(data, :card_count_official) || Map.get(data, "card_count_official")
    total = Map.get(data, :card_count_total) || Map.get(data, "card_count_total")
    series_id = Map.get(data, :series_id) || Map.get(data, "series_id")

    secret_count =
      if is_integer(total) and is_integer(official), do: total - official, else: nil

    secret_ratio =
      if is_integer(secret_count) and is_integer(official) and official > 0,
        do: Decimal.div(Decimal.new(secret_count), Decimal.new(official)),
        else: nil

    %{
      secret_rare_count: secret_count,
      secret_rare_ratio: secret_ratio,
      era: Map.get(@era_mapping, series_id)
    }
  end

  @doc """
  Compute 10 ML feature values from card data.

  Accepts both atom-keyed and string-keyed maps. Missing or nil lists default to [].

  Returns a map with keys: :attack_count, :total_attack_damage, :max_attack_damage,
  :has_ability, :ability_count, :weakness_count, :resistance_count,
  :first_edition, :is_shadowless, :has_first_edition_stamp.
  """
  def compute_features(data) when is_map(data) do
    attacks = get_list(data, :attacks, "attacks")
    abilities = get_list(data, :abilities, "abilities")
    weaknesses = get_list(data, :weaknesses, "weaknesses")
    resistances = get_list(data, :resistances, "resistances")
    variants = get_map(data, :variants, "variants")
    variants_detailed = get_list(data, :variants_detailed, "variants_detailed")

    damage_values =
      attacks
      |> Enum.map(&parse_damage/1)
      |> Enum.reject(&is_nil/1)

    %{
      attack_count: length(attacks),
      total_attack_damage: Enum.sum(damage_values),
      max_attack_damage: if(damage_values == [], do: 0, else: Enum.max(damage_values)),
      has_ability: abilities != [],
      ability_count: length(abilities),
      weakness_count: length(weaknesses),
      resistance_count: length(resistances),
      first_edition: first_edition?(variants),
      is_shadowless: has_subtype?(variants_detailed, "shadowless"),
      has_first_edition_stamp: has_stamp?(variants_detailed, "1st-edition")
    }
  end

  @doc """
  Extract numeric damage from an attack map.

  Handles: "50+", "120", "30×", "X", nil, integers, and maps with "damage" key.
  Returns integer or nil.
  """
  def parse_damage(%{"damage" => damage}), do: parse_damage_value(damage)
  def parse_damage(%{damage: damage}), do: parse_damage_value(damage)
  def parse_damage(val) when is_binary(val), do: parse_damage_value(val)
  def parse_damage(val) when is_integer(val), do: val
  def parse_damage(_), do: nil

  defp parse_damage_value(nil), do: nil
  defp parse_damage_value(val) when is_integer(val), do: val

  defp parse_damage_value(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, _rest} -> num
      :error -> nil
    end
  end

  defp parse_damage_value(_), do: nil

  defp first_edition?(%{"firstEdition" => true}), do: true
  defp first_edition?(%{firstEdition: true}), do: true
  defp first_edition?(_), do: false

  defp has_subtype?(variants_detailed, subtype) do
    Enum.any?(variants_detailed, fn variant ->
      (Map.get(variant, "subtype") || Map.get(variant, :subtype)) == subtype
    end)
  end

  defp has_stamp?(variants_detailed, stamp) do
    Enum.any?(variants_detailed, fn variant ->
      stamps = Map.get(variant, "stamp") || Map.get(variant, :stamp)
      is_list(stamps) and stamp in stamps
    end)
  end

  defp get_list(map, atom_key, string_key) do
    case Map.get(map, atom_key) || Map.get(map, string_key) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp get_map(map, atom_key, string_key) do
    case Map.get(map, atom_key) || Map.get(map, string_key) do
      m when is_map(m) -> m
      _ -> %{}
    end
  end
end
