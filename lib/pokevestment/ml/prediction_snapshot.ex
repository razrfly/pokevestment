defmodule Pokevestment.ML.PredictionSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "prediction_snapshots" do
    field :model_version, :string
    field :prediction_date, :date
    field :predicted_fair_value, :decimal
    field :current_price, :decimal
    field :value_ratio, :decimal
    field :signal_strength, :decimal
    field :signal, :string
    field :features_snapshot, :map
    field :actual_price, :decimal
    field :actual_return, :decimal
    field :outcome, :string
    field :horizon_projections, :map
    field :explanation, :map
    field :price_currency, :string
    field :price_source, :string

    belongs_to :card, Pokevestment.Cards.Card, type: :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(card_id model_version prediction_date signal)a
  @optional_fields ~w(predicted_fair_value current_price value_ratio signal_strength features_snapshot actual_price actual_return outcome horizon_projections explanation price_currency price_source)a

  @valid_signals ~w(STRONG_BUY BUY HOLD OVERVALUED INSUFFICIENT_DATA)

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:model_version, max: 20)
    |> validate_length(:signal, max: 20)
    |> validate_length(:outcome, max: 20)
    |> validate_inclusion(:signal, @valid_signals)
    |> foreign_key_constraint(:card_id)
  end
end
