defmodule Pokevestment.Cards.CardType do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "card_types" do
    field :type_name, :string

    belongs_to :card, Pokevestment.Cards.Card, type: :string
  end

  @required_fields ~w(card_id type_name)a

  def changeset(card_type, attrs) do
    card_type
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:type_name, max: 20)
    |> foreign_key_constraint(:card_id)
  end
end
