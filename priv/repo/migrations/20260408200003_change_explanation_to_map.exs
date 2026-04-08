defmodule Pokevestment.Repo.Migrations.ChangeExplanationToMap do
  use Ecto.Migration

  def change do
    alter table(:card_predictions) do
      remove :explanation, :string, size: 500
      add :explanation, :map
    end

    alter table(:prediction_snapshots) do
      remove :explanation, :string, size: 500
      add :explanation, :map
    end
  end
end
