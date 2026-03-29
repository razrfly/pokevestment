defmodule Pokevestment.Tournaments.TournamentTest do
  use Pokevestment.DataCase, async: true

  alias Pokevestment.Tournaments.{Tournament, TournamentStanding, TournamentDeckCard}

  describe "Tournament changeset" do
    test "valid with required fields" do
      changeset =
        Tournament.changeset(%Tournament{}, %{
          external_id: "abc123",
          name: "Test Tournament"
        })

      assert changeset.valid?
    end

    test "valid with all fields" do
      changeset =
        Tournament.changeset(%Tournament{}, %{
          external_id: "abc123",
          name: "Test Tournament",
          format: "STANDARD",
          tournament_date: ~U[2025-12-15 00:00:00Z],
          player_count: 32,
          organizer_id: 42,
          metadata: %{"game" => "PTCG"}
        })

      assert changeset.valid?
    end

    test "invalid without external_id" do
      changeset = Tournament.changeset(%Tournament{}, %{name: "Test"})
      refute changeset.valid?
      assert %{external_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without name" do
      changeset = Tournament.changeset(%Tournament{}, %{external_id: "abc"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces external_id max length" do
      changeset =
        Tournament.changeset(%Tournament{}, %{
          external_id: String.duplicate("a", 31),
          name: "Test"
        })

      refute changeset.valid?
    end

    test "enforces unique external_id on insert" do
      attrs = %{external_id: "unique123", name: "First"}
      {:ok, _} = %Tournament{} |> Tournament.changeset(attrs) |> Repo.insert()

      {:error, changeset} =
        %Tournament{} |> Tournament.changeset(%{attrs | name: "Second"}) |> Repo.insert()

      assert %{external_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "TournamentStanding changeset" do
    setup do
      {:ok, tournament} =
        %Tournament{}
        |> Tournament.changeset(%{external_id: "test1", name: "Test"})
        |> Repo.insert()

      %{tournament: tournament}
    end

    test "valid with required fields", %{tournament: t} do
      changeset =
        TournamentStanding.changeset(%TournamentStanding{}, %{tournament_id: t.id})

      assert changeset.valid?
    end

    test "valid with all fields", %{tournament: t} do
      changeset =
        TournamentStanding.changeset(%TournamentStanding{}, %{
          tournament_id: t.id,
          player_name: "Ash Ketchum",
          player_handle: "ash_k",
          country: "US",
          placing: 1,
          wins: 5,
          losses: 1,
          ties: 0,
          deck_archetype_id: "charizard-ex",
          deck_archetype_name: "Charizard ex"
        })

      assert changeset.valid?
    end

    test "invalid without tournament_id" do
      changeset = TournamentStanding.changeset(%TournamentStanding{}, %{})
      refute changeset.valid?
      assert %{tournament_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "enforces unique (tournament_id, player_handle)", %{tournament: t} do
      attrs = %{tournament_id: t.id, player_handle: "ash_k"}
      {:ok, _} = %TournamentStanding{} |> TournamentStanding.changeset(attrs) |> Repo.insert()

      {:error, changeset} =
        %TournamentStanding{} |> TournamentStanding.changeset(attrs) |> Repo.insert()

      assert %{tournament_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "TournamentDeckCard changeset" do
    setup do
      {:ok, tournament} =
        %Tournament{}
        |> Tournament.changeset(%{external_id: "test2", name: "Test"})
        |> Repo.insert()

      {:ok, standing} =
        %TournamentStanding{}
        |> TournamentStanding.changeset(%{tournament_id: tournament.id, player_handle: "p1"})
        |> Repo.insert()

      %{standing: standing}
    end

    test "valid with required fields", %{standing: s} do
      changeset =
        TournamentDeckCard.changeset(%TournamentDeckCard{}, %{
          tournament_standing_id: s.id,
          card_category: "pokemon",
          card_name: "Charizard ex",
          set_code: "TWM",
          card_number: "40",
          count: 2
        })

      assert changeset.valid?
    end

    test "invalid without required fields" do
      changeset = TournamentDeckCard.changeset(%TournamentDeckCard{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:tournament_standing_id]
      assert errors[:card_category]
      assert errors[:card_name]
      assert errors[:set_code]
      assert errors[:card_number]
      assert errors[:count]
    end

    test "validates count is positive", %{standing: s} do
      changeset =
        TournamentDeckCard.changeset(%TournamentDeckCard{}, %{
          tournament_standing_id: s.id,
          card_category: "pokemon",
          card_name: "Test",
          set_code: "TWM",
          card_number: "1",
          count: 0
        })

      refute changeset.valid?
      assert %{count: [_]} = errors_on(changeset)
    end

    test "accepts optional card_id", %{standing: s} do
      changeset =
        TournamentDeckCard.changeset(%TournamentDeckCard{}, %{
          tournament_standing_id: s.id,
          card_category: "pokemon",
          card_name: "Charizard ex",
          set_code: "TWM",
          card_number: "40",
          count: 2,
          card_id: nil
        })

      assert changeset.valid?
    end
  end

  describe "cascade deletes" do
    test "deleting tournament cascades to standings and deck cards" do
      {:ok, tournament} =
        %Tournament{}
        |> Tournament.changeset(%{external_id: "cascade1", name: "Cascade Test"})
        |> Repo.insert()

      {:ok, standing} =
        %TournamentStanding{}
        |> TournamentStanding.changeset(%{tournament_id: tournament.id, player_handle: "p1"})
        |> Repo.insert()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {1, _} =
        Repo.insert_all(TournamentDeckCard, [
          %{
            tournament_standing_id: standing.id,
            card_category: "pokemon",
            card_name: "Pikachu",
            set_code: "SVI",
            card_number: "25",
            count: 1,
            inserted_at: now
          }
        ])

      assert Repo.aggregate(TournamentStanding, :count) == 1
      assert Repo.aggregate(TournamentDeckCard, :count) == 1

      Repo.delete!(tournament)

      assert Repo.aggregate(TournamentStanding, :count) == 0
      assert Repo.aggregate(TournamentDeckCard, :count) == 0
    end
  end
end
