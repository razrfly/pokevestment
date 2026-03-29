defmodule Pokevestment.Tournaments.TournamentStanding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tournament_standings" do
    field :player_name, :string
    field :player_handle, :string
    field :country, :string
    field :placing, :integer
    field :wins, :integer, default: 0
    field :losses, :integer, default: 0
    field :ties, :integer, default: 0
    field :dropped_round, :integer
    field :deck_archetype_id, :string
    field :deck_archetype_name, :string
    field :metadata, :map

    belongs_to :tournament, Pokevestment.Tournaments.Tournament
    has_many :deck_cards, Pokevestment.Tournaments.TournamentDeckCard

    timestamps(type: :utc_datetime)
  end

  @castable_fields ~w(player_name player_handle country placing wins losses ties dropped_round deck_archetype_id deck_archetype_name)a

  def changeset(standing, attrs) do
    standing
    |> cast(attrs, @castable_fields)
    |> maybe_put_metadata(attrs)
    |> validate_required([:tournament_id, :player_handle])
    |> validate_length(:player_name, max: 100)
    |> validate_length(:player_handle, max: 100)
    |> validate_length(:country, max: 2)
    |> validate_length(:deck_archetype_id, max: 100)
    |> validate_length(:deck_archetype_name, max: 150)
    |> unique_constraint([:tournament_id, :player_handle])
    |> foreign_key_constraint(:tournament_id)
  end

  # metadata is set explicitly by the ingestion pipeline, not via user-facing cast
  defp maybe_put_metadata(changeset, %{metadata: metadata}) when is_map(metadata) do
    put_change(changeset, :metadata, metadata)
  end

  defp maybe_put_metadata(changeset, _attrs), do: changeset
end
