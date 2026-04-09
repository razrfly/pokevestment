defmodule Pokevestment.Repo.Migrations.AddConditionToPrices do
  use Ecto.Migration

  def change do
    # --- sold_prices ---
    alter table(:sold_prices) do
      add :condition, :string, size: 30, null: false, default: "aggregate"
    end

    drop unique_index(:sold_prices, [:card_id, :marketplace, :variant, :snapshot_date])

    create unique_index(:sold_prices,
      [:card_id, :marketplace, :variant, :condition, :snapshot_date],
      name: :sold_prices_card_mkt_var_cond_date_idx
    )

    # --- listing_prices ---
    alter table(:listing_prices) do
      add :condition, :string, size: 30, null: false, default: "aggregate"
    end

    drop unique_index(:listing_prices, [:card_id, :marketplace, :variant, :snapshot_date])

    create unique_index(:listing_prices,
      [:card_id, :marketplace, :variant, :condition, :snapshot_date],
      name: :listing_prices_card_mkt_var_cond_date_idx
    )
  end
end
