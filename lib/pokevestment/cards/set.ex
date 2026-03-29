defmodule Pokevestment.Cards.Set do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}

  schema "sets" do
    field :name, :string
    field :release_date, :date
    field :card_count_official, :integer
    field :card_count_total, :integer
    field :logo_url, :string
    field :symbol_url, :string
    field :ptcgo_code, :string
    field :legal_standard, :boolean, default: false
    field :legal_expanded, :boolean, default: false
    field :card_count_breakdown, :map
    field :metadata, :map

    # ML feature columns (set-level supply proxies)
    field :secret_rare_count, :integer
    field :secret_rare_ratio, :decimal
    field :era, :string

    belongs_to :series, Pokevestment.Cards.Series, type: :string
    has_many :cards, Pokevestment.Cards.Card

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(id name series_id)a
  @optional_fields ~w(release_date card_count_official card_count_total logo_url symbol_url ptcgo_code legal_standard legal_expanded card_count_breakdown metadata secret_rare_count secret_rare_ratio era)a

  def changeset(set, attrs) do
    set
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:id, max: 30)
    |> validate_length(:name, max: 100)
    |> validate_length(:ptcgo_code, max: 10)
    |> validate_length(:era, max: 20)
    |> foreign_key_constraint(:series_id)
  end
end
