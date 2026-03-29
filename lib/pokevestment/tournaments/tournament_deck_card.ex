defmodule Pokevestment.Tournaments.TournamentDeckCard do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "tournament_deck_cards" do
    field :card_category, :string
    field :card_name, :string
    field :set_code, :string
    field :card_number, :string
    field :count, :integer

    belongs_to :tournament_standing, Pokevestment.Tournaments.TournamentStanding
    belongs_to :card, Pokevestment.Cards.Card, type: :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(tournament_standing_id card_category card_name set_code card_number count)a
  @optional_fields ~w(card_id)a

  def changeset(deck_card, attrs) do
    deck_card
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:card_category, max: 10)
    |> validate_length(:card_name, max: 150)
    |> validate_length(:set_code, max: 10)
    |> validate_length(:card_number, max: 20)
    |> validate_number(:count, greater_than: 0)
    |> foreign_key_constraint(:tournament_standing_id)
    |> foreign_key_constraint(:card_id)
  end
end
