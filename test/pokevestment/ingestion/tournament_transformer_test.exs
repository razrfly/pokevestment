defmodule Pokevestment.Ingestion.TournamentTransformerTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Ingestion.TournamentTransformer

  describe "tournament_attrs/1" do
    test "transforms raw tournament data" do
      raw = %{
        "id" => "67e1ad04d7ec2c03e99d7b33",
        "name" => "Locals @ Card Shop",
        "date" => "2025-12-15T00:00:00.000Z",
        "format" => "STANDARD",
        "players" => 32,
        "organizerId" => 42,
        "game" => "PTCG"
      }

      result = TournamentTransformer.tournament_attrs(raw)

      assert result.external_id == "67e1ad04d7ec2c03e99d7b33"
      assert result.name == "Locals @ Card Shop"
      assert result.format == "STANDARD"
      assert result.player_count == 32
      assert result.organizer_id == 42
      assert %DateTime{} = result.tournament_date
      assert result.metadata == %{"game" => "PTCG"}
    end

    test "handles nil format" do
      raw = %{
        "id" => "abc123",
        "name" => "Test Tournament",
        "date" => nil,
        "format" => nil,
        "players" => 8,
        "organizerId" => 1
      }

      result = TournamentTransformer.tournament_attrs(raw)

      assert result.external_id == "abc123"
      assert result.format == nil
      assert result.tournament_date == nil
    end

    test "truncates long names" do
      raw = %{
        "id" => "abc",
        "name" => String.duplicate("A", 300),
        "date" => nil,
        "format" => nil,
        "players" => nil,
        "organizerId" => nil
      }

      result = TournamentTransformer.tournament_attrs(raw)
      assert byte_size(result.name) == 255
    end
  end

  describe "standing_attrs/2" do
    test "transforms raw standing data" do
      raw = %{
        "name" => "Ash Ketchum",
        "player" => "ash_k",
        "country" => "US",
        "placing" => 1,
        "record" => %{"wins" => 5, "losses" => 1, "ties" => 0},
        "drop" => nil,
        "deck" => %{"id" => "charizard-ex", "name" => "Charizard ex"}
      }

      result = TournamentTransformer.standing_attrs(raw, 42)

      assert result.tournament_id == 42
      assert result.player_name == "Ash Ketchum"
      assert result.player_handle == "ash_k"
      assert result.country == "US"
      assert result.placing == 1
      assert result.wins == 5
      assert result.losses == 1
      assert result.ties == 0
      assert result.dropped_round == nil
      assert result.deck_archetype_id == "charizard-ex"
      assert result.deck_archetype_name == "Charizard ex"
    end

    test "falls back to name when player handle is nil" do
      raw = %{
        "name" => "Misty",
        "player" => nil,
        "country" => nil,
        "placing" => nil,
        "record" => nil,
        "drop" => nil,
        "deck" => nil
      }

      result = TournamentTransformer.standing_attrs(raw, 1)

      assert result.player_handle == "Misty"
      assert result.wins == 0
      assert result.losses == 0
      assert result.ties == 0
    end

    test "handles dropped player" do
      raw = %{
        "name" => "Brock",
        "player" => "brock_pewter",
        "country" => "US",
        "placing" => nil,
        "record" => %{"wins" => 2, "losses" => 3, "ties" => 0},
        "drop" => 5,
        "deck" => %{"id" => "gardevoir-ex", "name" => "Gardevoir ex"}
      }

      result = TournamentTransformer.standing_attrs(raw, 1)
      assert result.dropped_round == 5
      assert result.placing == nil
    end
  end

  describe "deck_card_attrs_from_decklist/2" do
    test "flattens decklist categories into card attrs" do
      decklist = %{
        "pokemon" => [
          %{"count" => 2, "set" => "TWM", "number" => "40", "name" => "Charizard ex"},
          %{"count" => 3, "set" => "OBF", "number" => "91", "name" => "Charmander"}
        ],
        "trainer" => [
          %{"count" => 4, "set" => "PAR", "number" => "150", "name" => "Professor's Research"}
        ],
        "energy" => [
          %{"count" => 10, "set" => "SVP", "number" => "2", "name" => "Fire Energy"}
        ]
      }

      result = TournamentTransformer.deck_card_attrs_from_decklist(decklist, 99)

      assert length(result) == 4

      pokemon_cards = Enum.filter(result, &(&1.card_category == "pokemon"))
      assert length(pokemon_cards) == 2

      trainers = Enum.filter(result, &(&1.card_category == "trainer"))
      assert length(trainers) == 1

      energies = Enum.filter(result, &(&1.card_category == "energy"))
      assert length(energies) == 1

      charizard = Enum.find(result, &(&1.card_name == "Charizard ex"))
      assert charizard.tournament_standing_id == 99
      assert charizard.set_code == "TWM"
      assert charizard.card_number == "40"
      assert charizard.count == 2
    end

    test "returns empty list for nil decklist" do
      assert TournamentTransformer.deck_card_attrs_from_decklist(nil, 1) == []
    end

    test "handles missing categories" do
      decklist = %{
        "pokemon" => [
          %{"count" => 1, "set" => "TWM", "number" => "1", "name" => "Pikachu"}
        ]
      }

      result = TournamentTransformer.deck_card_attrs_from_decklist(decklist, 1)
      assert length(result) == 1
    end
  end

  describe "deck_card_attrs/3" do
    test "transforms a single card entry" do
      card_raw = %{
        "count" => 3,
        "set" => "SVI",
        "number" => "25",
        "name" => "Pikachu"
      }

      result = TournamentTransformer.deck_card_attrs(card_raw, 5, "pokemon")

      assert result.tournament_standing_id == 5
      assert result.card_category == "pokemon"
      assert result.card_name == "Pikachu"
      assert result.set_code == "SVI"
      assert result.card_number == "25"
      assert result.count == 3
    end

    test "converts numeric card_number to string" do
      card_raw = %{"count" => 1, "set" => "TWM", "number" => 42, "name" => "Test"}
      result = TournamentTransformer.deck_card_attrs(card_raw, 1, "trainer")
      assert result.card_number == "42"
    end
  end

  describe "resolve_card_id/4" do
    test "resolves card_id with zero-padding" do
      ptcgo_map = %{"TWM" => "sv06", "SVI" => "sv01"}
      card_ids = MapSet.new(["sv06-040", "sv01-025"])

      assert TournamentTransformer.resolve_card_id("TWM", "40", ptcgo_map, card_ids) ==
               "sv06-040"

      assert TournamentTransformer.resolve_card_id("SVI", "25", ptcgo_map, card_ids) ==
               "sv01-025"
    end

    test "resolves card_id with already-padded number" do
      ptcgo_map = %{"TWM" => "sv06"}
      card_ids = MapSet.new(["sv06-185"])

      assert TournamentTransformer.resolve_card_id("TWM", "185", ptcgo_map, card_ids) ==
               "sv06-185"
    end

    test "returns nil for unknown PTCGO code" do
      ptcgo_map = %{"TWM" => "sv06"}
      card_ids = MapSet.new(["sv06-040"])

      assert TournamentTransformer.resolve_card_id("UNKNOWN", "1", ptcgo_map, card_ids) == nil
    end

    test "returns nil when card_id not in known set" do
      ptcgo_map = %{"TWM" => "sv06"}
      card_ids = MapSet.new(["sv06-040"])

      assert TournamentTransformer.resolve_card_id("TWM", "999", ptcgo_map, card_ids) == nil
    end
  end
end
