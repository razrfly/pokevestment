defmodule Pokevestment.Cards.CardDexId do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "card_dex_ids" do
    field :dex_id, :integer

    belongs_to :card, Pokevestment.Cards.Card, type: :string

    belongs_to :species, Pokevestment.Pokemon.Species,
      foreign_key: :dex_id,
      references: :id,
      define_field: false
  end

  @required_fields ~w(card_id dex_id)a

  def changeset(card_dex_id, attrs) do
    card_dex_id
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:card_id)
    |> foreign_key_constraint(:dex_id)
  end
end
