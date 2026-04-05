defmodule Pokevestment.Ingestion.SetMapping do
  @moduledoc """
  Maps Pokemon TCG API set IDs to our TCGdex-based set IDs using
  `ptcgo_code` as a bridge, with name-based fallback for sets missing
  ptcgo codes (e.g. all SV-era sets). Built once per sync run.
  """

  require Logger

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Api.PokemonTcg

  @doc """
  Builds a mapping from Pokemon TCG API set IDs to our internal (TCGdex) set IDs.

  Returns `{:ok, %{ptcg_set_id => our_set_id}}` or `{:error, reason}`.
  """
  def build do
    {by_ptcgo, all_sets} = load_our_sets()

    with {:ok, ptcg_sets} <- PokemonTcg.list_sets() do
      mapping =
        Enum.reduce(ptcg_sets, %{}, fn ptcg_set, acc ->
          ptcg_id = ptcg_set["id"]
          ptcgo_code = ptcg_set["ptcgoCode"]
          ptcg_name = ptcg_set["name"]

          our_id =
            match_by_ptcgo(ptcgo_code, ptcg_name, by_ptcgo) ||
              match_by_name(ptcg_name, all_sets)

          if our_id do
            Map.put(acc, ptcg_id, our_id)
          else
            Logger.debug("SetMapping: no match for #{ptcg_id} (#{ptcg_name}, ptcgo=#{ptcgo_code})")
            acc
          end
        end)

      Logger.info("SetMapping: mapped #{map_size(mapping)}/#{length(ptcg_sets)} Pokemon TCG API sets")
      {:ok, mapping}
    end
  end

  defp load_our_sets do
    sets =
      from(s in Set, select: %{id: s.id, name: s.name, ptcgo_code: s.ptcgo_code, release_date: s.release_date})
      |> Repo.all()

    by_ptcgo =
      sets
      |> Enum.group_by(& &1.ptcgo_code)
      |> Map.delete(nil)

    {by_ptcgo, sets}
  end

  # --- Strategy 1: Match by ptcgo_code ---

  defp match_by_ptcgo(nil, _name, _by_ptcgo), do: nil

  defp match_by_ptcgo(ptcgo_code, ptcg_name, by_ptcgo) do
    case Map.get(by_ptcgo, ptcgo_code) do
      nil -> nil
      [single] -> single.id
      multiple -> disambiguate_by_name(ptcg_name, multiple)
    end
  end

  # --- Strategy 2: Name-based fallback for sets with nil ptcgo_code ---

  @name_similarity_threshold 0.5

  defp match_by_name(nil, _all_sets), do: nil

  defp match_by_name(ptcg_name, all_sets) do
    ptcg_down = String.downcase(ptcg_name)

    {best_set, best_score} =
      Enum.reduce(all_sets, {nil, 0.0}, fn set, {best, score} ->
        our_down = String.downcase(set.name || "")
        sim = name_similarity(ptcg_down, our_down)

        if sim > score, do: {set, sim}, else: {best, score}
      end)

    if best_score >= @name_similarity_threshold do
      best_set.id
    else
      nil
    end
  end

  # When multiple sets share a ptcgo_code (e.g. old sets with "RR"),
  # pick the one whose name is most similar to the Pokemon TCG API name.
  defp disambiguate_by_name(nil, [first | _]), do: first.id

  defp disambiguate_by_name(ptcg_name, sets) do
    ptcg_down = String.downcase(ptcg_name)

    sets
    |> Enum.max_by(fn set ->
      our_down = String.downcase(set.name || "")
      name_similarity(ptcg_down, our_down)
    end)
    |> Map.get(:id)
  end

  # Simple Jaccard similarity on word tokens — good enough for set name matching.
  defp name_similarity(a, b) do
    words_a = a |> String.split(~r/[\s&:—–-]+/, trim: true) |> MapSet.new()
    words_b = b |> String.split(~r/[\s&:—–-]+/, trim: true) |> MapSet.new()

    intersection = MapSet.intersection(words_a, words_b) |> MapSet.size()
    union = MapSet.union(words_a, words_b) |> MapSet.size()

    if union == 0, do: 0.0, else: intersection / union
  end
end
