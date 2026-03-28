defmodule Pokevestment.Cards.Series do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "series" do
    field :name, :string
    field :logo_url, :string
    field :metadata, :map

    has_many :sets, Pokevestment.Cards.Set

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id name)a
  @optional_fields ~w(logo_url metadata)a

  def changeset(series, attrs) do
    series
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:id, max: 30)
    |> validate_length(:name, max: 100)
  end
end
