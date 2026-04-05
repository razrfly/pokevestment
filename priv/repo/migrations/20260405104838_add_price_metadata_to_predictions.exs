defmodule Pokevestment.Repo.Migrations.AddPriceMetadataToPredictions do
  use Ecto.Migration

  def change do
    alter table(:card_predictions) do
      add :price_currency, :string, size: 3
      add :price_source, :string, size: 20
    end

    alter table(:prediction_snapshots) do
      add :price_currency, :string, size: 3
      add :price_source, :string, size: 20
    end
  end
end
