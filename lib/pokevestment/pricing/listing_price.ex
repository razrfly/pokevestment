defmodule Pokevestment.Pricing.ListingPrice do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [updated_at: false]

  schema "listing_prices" do
    field :marketplace, :string
    field :api_source, :string
    field :variant, :string
    field :snapshot_date, :date
    field :currency_original, :string
    field :price_low, :decimal
    field :price_mid, :decimal
    field :price_high, :decimal
    field :price_direct_low, :decimal
    field :price_low_usd, :decimal
    field :price_mid_usd, :decimal
    field :price_high_usd, :decimal
    field :exchange_rate, :decimal
    field :exchange_rate_date, :date
    field :product_id, :integer
    field :source_updated_at, :utc_datetime
    field :metadata, :map

    belongs_to :card, Pokevestment.Cards.Card, type: :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(card_id marketplace api_source variant snapshot_date currency_original)a
  @optional_fields ~w(price_low price_mid price_high price_direct_low price_low_usd price_mid_usd price_high_usd exchange_rate exchange_rate_date product_id source_updated_at metadata)a

  def changeset(listing_price, attrs) do
    listing_price
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:marketplace, max: 20)
    |> validate_length(:api_source, max: 30)
    |> validate_length(:variant, max: 30)
    |> validate_length(:currency_original, max: 3)
    |> validate_has_positive_price()
    |> unique_constraint([:card_id, :marketplace, :variant, :snapshot_date])
    |> foreign_key_constraint(:card_id)
  end

  @price_fields ~w(price_low price_mid price_high)a

  defp validate_has_positive_price(changeset) do
    has_positive =
      Enum.any?(@price_fields, fn field ->
        val = get_field(changeset, field)
        val != nil and Decimal.gt?(val, Decimal.new(0))
      end)

    if has_positive do
      changeset
    else
      add_error(changeset, :price_low, "at least one listing price field must be positive")
    end
  end
end
