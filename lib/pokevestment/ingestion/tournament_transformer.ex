defmodule Pokevestment.Ingestion.TournamentTransformer do
  @moduledoc """
  Pure functions to transform Limitless TCG API responses into Ecto-compatible
  attribute maps. No database access — all functions are side-effect free.
  """

  @doc """
  Transform a raw tournament list item into Tournament schema attrs.

  Raw shape: %{"id" => "abc", "name" => "...", "date" => "2025-...", "format" => "STANDARD",
               "players" => 42, "organizerId" => 123, "game" => "PTCG"}
  """
  def tournament_attrs(raw) do
    %{
      external_id: raw["id"],
      name: truncate(raw["name"], 255),
      format: raw["format"],
      tournament_date: parse_datetime(raw["date"]),
      player_count: raw["players"],
      organizer_id: raw["organizerId"],
      metadata: Map.drop(raw, ["id", "name", "date", "format", "players", "organizerId"])
    }
  end

  @doc """
  Transform a raw standing object into TournamentStanding schema attrs.

  Raw shape: %{"name" => "...", "player" => "handle", "country" => "US",
               "placing" => 1, "record" => %{"wins" => 4, ...},
               "drop" => nil, "deck" => %{"id" => "...", "name" => "..."}}
  """
  def standing_attrs(raw, tournament_id) do
    record = raw["record"] || %{}
    deck = raw["deck"] || %{}

    %{
      tournament_id: tournament_id,
      player_name: truncate(raw["name"], 100),
      player_handle: truncate(raw["player"] || raw["name"], 100),
      country: truncate(raw["country"], 2),
      placing: raw["placing"],
      wins: record["wins"] || 0,
      losses: record["losses"] || 0,
      ties: record["ties"] || 0,
      dropped_round: raw["drop"],
      deck_archetype_id: deck["id"],
      deck_archetype_name: truncate(deck["name"], 150),
      metadata: raw
    }
  end

  @doc """
  Extract deck card attrs from a standing's decklist.

  Returns a flat list of card attrs for all categories (pokemon, trainer, energy).

  Raw decklist shape: %{"pokemon" => [%{"count" => 2, "set" => "TWM", "number" => "123", "name" => "Charizard ex"}], ...}
  """
  def deck_card_attrs_from_decklist(decklist, standing_id) do
    if decklist do
      Enum.flat_map(~w(pokemon trainer energy), fn category ->
        decklist
        |> Map.get(category, [])
        |> Enum.map(&deck_card_attrs(&1, standing_id, category))
      end)
    else
      []
    end
  end

  @doc """
  Transform a single card entry from the decklist into TournamentDeckCard attrs.

  Raw shape: %{"count" => 2, "set" => "TWM", "number" => "123", "name" => "Charizard ex"}
  """
  def deck_card_attrs(card_raw, standing_id, card_category) do
    %{
      tournament_standing_id: standing_id,
      card_category: card_category,
      card_name: truncate(card_raw["name"], 150),
      set_code: card_raw["set"],
      card_number: to_string(card_raw["number"]),
      count: card_raw["count"],
      metadata: card_raw
    }
  end

  @doc """
  Resolve a card_id from Limitless set_code + card_number using preloaded lookup maps.

  `ptcgo_to_set_id` maps PTCGO codes to TCGdex set IDs: %{"TWM" => "sv06", ...}
  `card_ids` is a MapSet of all known card IDs.

  Returns the card_id string or nil if not found.
  """
  def resolve_card_id(set_code, card_number, ptcgo_to_set_id, card_ids) do
    case Map.get(ptcgo_to_set_id, set_code) do
      nil ->
        nil

      tcgdex_set_id ->
        padded = pad_card_number(card_number)
        card_id = "#{tcgdex_set_id}-#{padded}"

        if MapSet.member?(card_ids, card_id) do
          card_id
        else
          nil
        end
    end
  end

  # --- Private Helpers ---

  # TCGdex uses zero-padded 3-digit card numbers (e.g. "065"),
  # while Limitless sends unpadded (e.g. "65").
  defp pad_card_number(number) when is_binary(number) do
    case Integer.parse(number) do
      {n, ""} -> String.pad_leading(Integer.to_string(n), 3, "0")
      _ -> number
    end
  end

  defp pad_card_number(number) when is_integer(number) do
    String.pad_leading(Integer.to_string(number), 3, "0")
  end

  defp truncate(nil, _max), do: nil

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max do
    String.slice(str, 0, max)
  end

  defp truncate(str, _max) when is_binary(str), do: str

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
