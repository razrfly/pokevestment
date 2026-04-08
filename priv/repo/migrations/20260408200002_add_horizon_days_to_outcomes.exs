defmodule Pokevestment.Repo.Migrations.AddHorizonDaysToOutcomes do
  use Ecto.Migration

  def change do
    alter table(:prediction_outcomes) do
      add :horizon_days, :integer, null: false, default: 30
    end

    drop unique_index(:prediction_outcomes, [:prediction_snapshot_id])
    create unique_index(:prediction_outcomes, [:prediction_snapshot_id, :horizon_days])
  end
end
