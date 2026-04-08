defmodule Pokevestment.Repo.Migrations.CreateSoldAndListingPrices do
  use Ecto.Migration

  def change do
    create table(:sold_prices) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false
      add :marketplace, :string, size: 20, null: false
      add :api_source, :string, size: 30, null: false
      add :variant, :string, size: 30, null: false
      add :snapshot_date, :date, null: false
      add :currency_original, :string, size: 3, null: false
      add :price, :decimal, precision: 10, scale: 2
      add :price_avg_1d, :decimal, precision: 10, scale: 2
      add :price_avg_7d, :decimal, precision: 10, scale: 2
      add :price_avg_30d, :decimal, precision: 10, scale: 2
      add :price_usd, :decimal, precision: 10, scale: 2
      add :exchange_rate, :decimal, precision: 10, scale: 6
      add :exchange_rate_date, :date
      add :product_id, :integer
      add :source_updated_at, :utc_datetime
      add :metadata, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:sold_prices, [:card_id, :marketplace, :variant, :snapshot_date])
    create index(:sold_prices, [:card_id, :snapshot_date])
    create index(:sold_prices, [:snapshot_date])
    create index(:sold_prices, [:card_id, :marketplace])

    create table(:listing_prices) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false
      add :marketplace, :string, size: 20, null: false
      add :api_source, :string, size: 30, null: false
      add :variant, :string, size: 30, null: false
      add :snapshot_date, :date, null: false
      add :currency_original, :string, size: 3, null: false
      add :price_low, :decimal, precision: 10, scale: 2
      add :price_mid, :decimal, precision: 10, scale: 2
      add :price_high, :decimal, precision: 10, scale: 2
      add :price_direct_low, :decimal, precision: 10, scale: 2
      add :price_low_usd, :decimal, precision: 10, scale: 2
      add :price_mid_usd, :decimal, precision: 10, scale: 2
      add :price_high_usd, :decimal, precision: 10, scale: 2
      add :exchange_rate, :decimal, precision: 10, scale: 6
      add :exchange_rate_date, :date
      add :product_id, :integer
      add :source_updated_at, :utc_datetime
      add :metadata, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:listing_prices, [:card_id, :marketplace, :variant, :snapshot_date])
    create index(:listing_prices, [:card_id, :snapshot_date])
    create index(:listing_prices, [:snapshot_date])
  end
end
