defmodule Pokevestment.ML.ModelEvaluation do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "model_evaluations" do
    field :model_version, :string
    field :evaluation_date, :date

    field :rmse, :decimal
    field :mae, :decimal
    field :r_squared, :decimal
    field :mape, :decimal

    field :baseline_rmse, :decimal
    field :baseline_r_squared, :decimal

    field :split_strategy, :string
    field :train_rows, :integer
    field :val_rows, :integer

    field :feature_importances, :map
    field :umbrella_importances, :map
    field :training_params, :map

    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(model_version evaluation_date)a
  @optional_fields ~w(rmse mae r_squared mape baseline_rmse baseline_r_squared split_strategy train_rows val_rows feature_importances umbrella_importances training_params notes)a

  def changeset(evaluation, attrs) do
    evaluation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:model_version, max: 20)
    |> validate_length(:split_strategy, max: 20)
  end
end
