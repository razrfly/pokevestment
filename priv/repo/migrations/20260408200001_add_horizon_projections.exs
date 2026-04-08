defmodule Pokevestment.Repo.Migrations.AddHorizonProjections do
  use Ecto.Migration

  def change do
    alter table(:card_predictions) do
      add :horizon_projections, :map
      add :explanation, :string, size: 500
    end

    alter table(:prediction_snapshots) do
      add :horizon_projections, :map
      add :explanation, :string, size: 500
    end
  end
end
