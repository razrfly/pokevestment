defmodule Pokevestment.ML.PredictionOutcome do
  @moduledoc """
  Records the actual outcome of a prediction after a configurable maturity window.

  Each row links back to a `PredictionSnapshot` and captures the actual price
  at the outcome date, the realized return, and whether the signal was correct.
  The `horizon_days` field (default 30) specifies which time horizon this outcome
  evaluates, enabling multi-horizon accountability (e.g. 7d, 30d, 90d).

  The `outcome_price_source` and `outcome_price_currency` fields record which
  price variant was used for evaluation (e.g. "tcgplayer" / "USD"), since the
  closest available price may come from a different source than the original.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "prediction_outcomes" do
    field :model_version, :string
    field :prediction_date, :date
    field :outcome_date, :date
    field :predicted_fair_value, :decimal
    field :price_at_prediction, :decimal
    field :price_at_outcome, :decimal
    field :actual_return, :decimal
    field :signal, :string
    field :signal_correct, :boolean
    field :outcome_price_source, :string
    field :outcome_price_currency, :string
    field :horizon_days, :integer, default: 30

    belongs_to :prediction_snapshot, Pokevestment.ML.PredictionSnapshot
    belongs_to :card, Pokevestment.Cards.Card, type: :string

    timestamps(type: :utc_datetime)
  end

  @cast_fields ~w(model_version prediction_date outcome_date signal predicted_fair_value price_at_prediction price_at_outcome actual_return signal_correct outcome_price_source outcome_price_currency horizon_days)a
  @required_fields ~w(model_version prediction_date outcome_date signal)a

  def changeset(outcome, attrs) do
    outcome
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:model_version, max: 20)
    |> validate_length(:signal, max: 20)
    |> unique_constraint([:prediction_snapshot_id, :horizon_days])
    |> foreign_key_constraint(:prediction_snapshot_id)
    |> foreign_key_constraint(:card_id)
  end
end
