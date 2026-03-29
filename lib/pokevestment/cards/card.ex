defmodule Pokevestment.Cards.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "cards" do
    field :name, :string
    field :local_id, :string
    field :category, :string
    field :rarity, :string
    field :hp, :integer
    field :stage, :string
    field :suffix, :string
    field :illustrator, :string
    field :evolves_from, :string
    field :retreat_cost, :integer
    field :regulation_mark, :string
    field :energy_type, :string
    field :trainer_type, :string
    field :legal_standard, :boolean, default: false
    field :legal_expanded, :boolean, default: false
    field :is_secret_rare, :boolean, default: false
    field :generation, :integer
    field :variants, :map
    field :variants_detailed, {:array, :map}
    field :attacks, {:array, :map}
    field :abilities, {:array, :map}
    field :weaknesses, {:array, :map}
    field :resistances, {:array, :map}
    field :image_url, :string
    field :api_updated_at, :utc_datetime
    field :metadata, :map

    # ML feature columns
    field :attack_count, :integer, default: 0
    field :total_attack_damage, :integer, default: 0
    field :max_attack_damage, :integer, default: 0
    field :has_ability, :boolean, default: false
    field :ability_count, :integer, default: 0
    field :weakness_count, :integer, default: 0
    field :resistance_count, :integer, default: 0

    # Variant feature columns
    field :first_edition, :boolean, default: false
    field :is_shadowless, :boolean, default: false
    field :has_first_edition_stamp, :boolean, default: false

    # Art type feature columns
    field :art_type, :string, default: "standard"
    field :is_full_art, :boolean, default: false
    field :is_alternate_art, :boolean, default: false

    # Language availability
    field :language_count, :integer, default: 1

    # Energy cost feature
    field :energy_cost_total, :integer, default: 0

    belongs_to :set, Pokevestment.Cards.Set, type: :string
    has_many :card_types, Pokevestment.Cards.CardType
    has_many :card_dex_ids, Pokevestment.Cards.CardDexId
    has_many :price_snapshots, Pokevestment.Pricing.PriceSnapshot

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id name local_id category set_id)a
  # Pipeline-computed fields (attack_count through energy_cost_total) are set by
  # FeatureExtractor during import and backfill tasks. They're castable because
  # the full import pipeline sets them via Card.changeset.
  @optional_fields ~w(rarity hp stage suffix illustrator evolves_from retreat_cost regulation_mark energy_type trainer_type legal_standard legal_expanded is_secret_rare generation variants variants_detailed attacks abilities weaknesses resistances image_url api_updated_at metadata attack_count total_attack_damage max_attack_damage has_ability ability_count weakness_count resistance_count first_edition is_shadowless has_first_edition_stamp art_type is_full_art is_alternate_art energy_cost_total)a
  # language_count is only set by the backfill_language_counts task via Repo.update_all

  def changeset(card, attrs) do
    card
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:id, max: 30)
    |> validate_length(:name, max: 150)
    |> validate_length(:local_id, max: 20)
    |> validate_length(:category, max: 20)
    |> unique_constraint([:set_id, :local_id])
    |> foreign_key_constraint(:set_id)
  end
end
