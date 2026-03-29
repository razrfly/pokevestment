defmodule Pokevestment.Ingestion.FeatureExtractor do
  @moduledoc """
  Pure functions to compute ML feature columns from card data.
  No database access — all functions are side-effect free.
  """

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
    Enum.any?(variants_detailed, fn
      %{"subtype" => ^subtype} -> true
      _ -> false
    end)
  end

  defp has_stamp?(variants_detailed, stamp) do
    Enum.any?(variants_detailed, fn
      %{"stamp" => stamps} when is_list(stamps) -> stamp in stamps
      _ -> false
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
