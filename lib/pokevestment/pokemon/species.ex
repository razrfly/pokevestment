defmodule Pokevestment.Pokemon.Species do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}

  schema "pokemon_species" do
    field :name, :string
    field :generation, :integer
    field :is_legendary, :boolean, default: false
    field :is_mythical, :boolean, default: false
    field :is_baby, :boolean, default: false
    field :color, :string
    field :habitat, :string
    field :shape, :string
    field :capture_rate, :integer
    field :base_happiness, :integer
    field :growth_rate, :string
    field :flavor_text, :string
    field :genus, :string
    field :sprite_url, :string
    field :metadata, :map

    belongs_to :evolves_from_species, __MODULE__
    has_many :evolutions, __MODULE__, foreign_key: :evolves_from_species_id
    has_many :card_dex_ids, Pokevestment.Cards.CardDexId, foreign_key: :dex_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id name generation)a
  @optional_fields ~w(is_legendary is_mythical is_baby color habitat shape capture_rate base_happiness growth_rate flavor_text genus sprite_url evolves_from_species_id metadata)a

  def changeset(species, attrs) do
    species
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 50)
    |> validate_inclusion(:generation, 1..9)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:evolves_from_species_id)
  end
end
