defmodule Pokevestment.Repo.Migrations.CreatePredictionSnapshots do
  use Ecto.Migration

  def change do
    create table(:prediction_snapshots) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false
      add :model_version, :string, size: 20, null: false
      add :prediction_date, :date, null: false
      add :predicted_fair_value, :decimal, precision: 10, scale: 2
      add :current_price, :decimal, precision: 10, scale: 2
      add :value_ratio, :decimal, precision: 10, scale: 4
      add :signal_strength, :decimal, precision: 10, scale: 4
      add :signal, :string, size: 20, null: false
      add :features_snapshot, :map

      # Nullable backfill columns — populated later by outcome worker
      add :actual_price, :decimal, precision: 10, scale: 2
      add :actual_return, :decimal, precision: 10, scale: 4
      add :outcome, :string, size: 20

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:prediction_snapshots, [:card_id, :prediction_date])
    create index(:prediction_snapshots, [:model_version])

    create index(:prediction_snapshots, [:outcome],
      where: "outcome IS NOT NULL",
      name: :prediction_snapshots_with_outcome_index
    )
  end
end
