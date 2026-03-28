defmodule Pokevestment.Repo.Migrations.CreatePriceSnapshots do
  use Ecto.Migration

  def change do
    create table(:price_snapshots) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false
      add :source, :string, size: 20, null: false
      add :variant, :string, size: 30, null: false
      add :snapshot_date, :date, null: false
      add :currency, :string, size: 3, null: false
      add :price_low, :decimal, precision: 10, scale: 2
      add :price_mid, :decimal, precision: 10, scale: 2
      add :price_high, :decimal, precision: 10, scale: 2
      add :price_market, :decimal, precision: 10, scale: 2
      add :price_direct_low, :decimal, precision: 10, scale: 2
      add :price_avg, :decimal, precision: 10, scale: 2
      add :price_trend, :decimal, precision: 10, scale: 2
      add :price_avg1, :decimal, precision: 10, scale: 2
      add :price_avg7, :decimal, precision: 10, scale: 2
      add :price_avg30, :decimal, precision: 10, scale: 2
      add :product_id, :integer
      add :source_updated_at, :utc_datetime
      add :metadata, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:price_snapshots, [:card_id, :source, :variant, :snapshot_date])
    create index(:price_snapshots, [:card_id, :source])
    create index(:price_snapshots, [:snapshot_date])
    create index(:price_snapshots, [:card_id, :snapshot_date])
    create index(:price_snapshots, [:card_id, :variant, :snapshot_date])
  end
end
