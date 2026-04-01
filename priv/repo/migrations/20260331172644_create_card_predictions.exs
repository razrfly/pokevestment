defmodule Pokevestment.Repo.Migrations.CreateCardPredictions do
  use Ecto.Migration

  def change do
    create table(:card_predictions, primary_key: false) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all),
        primary_key: true,
        null: false,
        size: 30

      add :model_version, :string, size: 20, null: false
      add :prediction_date, :date, null: false
      add :predicted_fair_value, :decimal, precision: 10, scale: 2
      add :current_price, :decimal, precision: 10, scale: 2
      add :value_ratio, :decimal, precision: 10, scale: 4
      add :signal_strength, :decimal, precision: 10, scale: 4
      add :signal, :string, size: 20, null: false
      add :top_positive_drivers, :map
      add :top_negative_drivers, :map
      add :umbrella_breakdown, :map

      timestamps(type: :utc_datetime, inserted_at: false)
    end

    create index(:card_predictions, [:signal])

    create index(:card_predictions, [:signal],
      where: "signal IN ('STRONG_BUY', 'BUY')",
      name: :card_predictions_buy_signals_index
    )
  end
end
