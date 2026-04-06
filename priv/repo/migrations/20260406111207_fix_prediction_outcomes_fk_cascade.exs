defmodule Pokevestment.Repo.Migrations.FixPredictionOutcomesFkCascade do
  use Ecto.Migration

  def change do
    # Fix card_id FK to include ON DELETE CASCADE (matching all other card_id FKs)
    execute(
      "ALTER TABLE prediction_outcomes DROP CONSTRAINT prediction_outcomes_card_id_fkey; " <>
        "ALTER TABLE prediction_outcomes ADD CONSTRAINT prediction_outcomes_card_id_fkey " <>
        "FOREIGN KEY (card_id) REFERENCES cards(id) ON DELETE CASCADE",
      "ALTER TABLE prediction_outcomes DROP CONSTRAINT prediction_outcomes_card_id_fkey; " <>
        "ALTER TABLE prediction_outcomes ADD CONSTRAINT prediction_outcomes_card_id_fkey " <>
        "FOREIGN KEY (card_id) REFERENCES cards(id)"
    )

    # Fix prediction_snapshot_id FK to include ON DELETE CASCADE
    execute(
      "ALTER TABLE prediction_outcomes DROP CONSTRAINT prediction_outcomes_prediction_snapshot_id_fkey; " <>
        "ALTER TABLE prediction_outcomes ADD CONSTRAINT prediction_outcomes_prediction_snapshot_id_fkey " <>
        "FOREIGN KEY (prediction_snapshot_id) REFERENCES prediction_snapshots(id) ON DELETE CASCADE",
      "ALTER TABLE prediction_outcomes DROP CONSTRAINT prediction_outcomes_prediction_snapshot_id_fkey; " <>
        "ALTER TABLE prediction_outcomes ADD CONSTRAINT prediction_outcomes_prediction_snapshot_id_fkey " <>
        "FOREIGN KEY (prediction_snapshot_id) REFERENCES prediction_snapshots(id)"
    )
  end
end
