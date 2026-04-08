defmodule Pokevestment.ML.CardPrediction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [inserted_at: false]

  schema "card_predictions" do
    field :card_id, :string, primary_key: true
    field :model_version, :string
    field :prediction_date, :date
    field :predicted_fair_value, :decimal
    field :current_price, :decimal
    field :value_ratio, :decimal
    field :signal_strength, :decimal
    field :signal, :string
    field :top_positive_drivers, :map
    field :top_negative_drivers, :map
    field :umbrella_breakdown, :map
    field :horizon_projections, :map
    field :explanation, :map
    field :price_currency, :string
    field :price_source, :string

    belongs_to :card, Pokevestment.Cards.Card,
      type: :string,
      define_field: false,
      foreign_key: :card_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(card_id model_version prediction_date signal)a
  @optional_fields ~w(predicted_fair_value current_price value_ratio signal_strength top_positive_drivers top_negative_drivers umbrella_breakdown horizon_projections explanation price_currency price_source)a

  @valid_signals ~w(STRONG_BUY BUY HOLD OVERVALUED INSUFFICIENT_DATA)

  def changeset(prediction, attrs) do
    prediction
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:card_id, max: 30)
    |> validate_length(:model_version, max: 20)
    |> validate_length(:signal, max: 20)
    |> validate_inclusion(:signal, @valid_signals)
    |> foreign_key_constraint(:card_id)
  end
end
