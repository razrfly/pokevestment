defmodule Pokevestment.Tournaments.Tournament do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tournaments" do
    field :external_id, :string
    field :name, :string
    field :format, :string
    field :tournament_date, :utc_datetime
    field :player_count, :integer
    field :organizer_id, :integer
    field :metadata, :map

    has_many :standings, Pokevestment.Tournaments.TournamentStanding

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(external_id name)a
  @optional_fields ~w(format tournament_date player_count organizer_id metadata)a

  def changeset(tournament, attrs) do
    tournament
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:external_id, max: 30)
    |> validate_length(:name, max: 255)
    |> validate_length(:format, max: 20)
    |> unique_constraint(:external_id)
  end
end
