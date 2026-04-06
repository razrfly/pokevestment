defmodule Pokevestment.Repo.Migrations.CreatePredictionOutcomes do
  use Ecto.Migration

  def change do
    create table(:prediction_outcomes) do
      add :prediction_snapshot_id, references(:prediction_snapshots, on_delete: :delete_all),
        null: false

      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false
      add :model_version, :string, size: 20, null: false
      add :prediction_date, :date, null: false
      add :outcome_date, :date, null: false
      add :predicted_fair_value, :decimal, precision: 10, scale: 2
      add :price_at_prediction, :decimal, precision: 10, scale: 2
      add :price_at_outcome, :decimal, precision: 10, scale: 2
      add :actual_return, :decimal, precision: 10, scale: 4
      add :signal, :string, size: 20, null: false
      add :signal_correct, :boolean
      add :outcome_price_source, :string, size: 20
      add :outcome_price_currency, :string, size: 5

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:prediction_outcomes, [:prediction_snapshot_id])
    create index(:prediction_outcomes, [:model_version, :outcome_date])
    create index(:prediction_outcomes, [:signal, :signal_correct])
    create index(:prediction_outcomes, [:card_id, :outcome_date])
  end
end
