defmodule Pokevestment.Repo.Migrations.CreateTournamentTables do
  use Ecto.Migration

  def change do
    create table(:tournaments) do
      add :external_id, :string, size: 30, null: false
      add :name, :string, size: 255, null: false
      add :format, :string, size: 20
      add :tournament_date, :utc_datetime
      add :player_count, :integer
      add :organizer_id, :integer
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tournaments, [:external_id])
    create index(:tournaments, [:format])
    create index(:tournaments, [:tournament_date])

    create table(:tournament_standings) do
      add :tournament_id, references(:tournaments, on_delete: :delete_all), null: false
      add :player_name, :string, size: 100
      add :player_handle, :string, size: 100
      add :country, :string, size: 2
      add :placing, :integer
      add :wins, :integer, default: 0
      add :losses, :integer, default: 0
      add :ties, :integer, default: 0
      add :dropped_round, :integer
      add :deck_archetype_id, :string, size: 100
      add :deck_archetype_name, :string, size: 150

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tournament_standings, [:tournament_id, :player_handle])
    create index(:tournament_standings, [:tournament_id])
    create index(:tournament_standings, [:deck_archetype_id])

    create table(:tournament_deck_cards) do
      add :tournament_standing_id, references(:tournament_standings, on_delete: :delete_all),
        null: false

      add :card_category, :string, size: 10, null: false
      add :card_name, :string, size: 150, null: false
      add :set_code, :string, size: 10, null: false
      add :card_number, :string, size: 20, null: false
      add :count, :integer, null: false
      add :card_id, references(:cards, type: :string, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:tournament_deck_cards, [:tournament_standing_id])
    create index(:tournament_deck_cards, [:card_id])
    create index(:tournament_deck_cards, [:set_code, :card_number])
  end
end
