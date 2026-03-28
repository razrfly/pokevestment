defmodule Pokevestment.Pricing.PriceSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "price_snapshots" do
    field :source, :string
    field :variant, :string
    field :snapshot_date, :date
    field :currency, :string
    field :price_low, :decimal
    field :price_mid, :decimal
    field :price_high, :decimal
    field :price_market, :decimal
    field :price_direct_low, :decimal
    field :price_avg, :decimal
    field :price_trend, :decimal
    field :price_avg1, :decimal
    field :price_avg7, :decimal
    field :price_avg30, :decimal
    field :product_id, :integer
    field :source_updated_at, :utc_datetime
    field :metadata, :map

    belongs_to :card, Pokevestment.Cards.Card, type: :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(card_id source variant snapshot_date currency)a
  @optional_fields ~w(price_low price_mid price_high price_market price_direct_low price_avg price_trend price_avg1 price_avg7 price_avg30 product_id source_updated_at metadata)a

  def changeset(price_snapshot, attrs) do
    price_snapshot
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:source, max: 20)
    |> validate_length(:variant, max: 30)
    |> validate_length(:currency, max: 3)
    |> unique_constraint([:card_id, :source, :variant, :snapshot_date])
    |> foreign_key_constraint(:card_id)
  end
end
