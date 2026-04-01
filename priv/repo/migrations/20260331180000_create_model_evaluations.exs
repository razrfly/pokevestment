defmodule Pokevestment.Repo.Migrations.CreateModelEvaluations do
  use Ecto.Migration

  def change do
    create table(:model_evaluations) do
      add :model_version, :string, size: 20, null: false
      add :evaluation_date, :date, null: false

      # Core metrics
      add :rmse, :decimal, precision: 10, scale: 6
      add :mae, :decimal, precision: 10, scale: 6
      add :r_squared, :decimal, precision: 10, scale: 6
      add :mape, :decimal, precision: 10, scale: 6

      # Baseline comparisons
      add :baseline_rmse, :decimal, precision: 10, scale: 6
      add :baseline_r_squared, :decimal, precision: 10, scale: 6

      # Split info
      add :split_strategy, :string, size: 20
      add :train_rows, :integer
      add :val_rows, :integer

      # JSONB metadata
      add :feature_importances, :map
      add :umbrella_importances, :map
      add :training_params, :map

      add :notes, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:model_evaluations, [:model_version])
  end
end
