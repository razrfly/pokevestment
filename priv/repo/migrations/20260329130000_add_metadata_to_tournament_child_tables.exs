defmodule Pokevestment.Repo.Migrations.AddMetadataToTournamentChildTables do
  use Ecto.Migration

  def change do
    alter table(:tournament_standings) do
      add :metadata, :map
    end

    alter table(:tournament_deck_cards) do
      add :metadata, :map
    end
  end
end
