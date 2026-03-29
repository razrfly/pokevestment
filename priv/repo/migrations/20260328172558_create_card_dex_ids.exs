defmodule Pokevestment.Repo.Migrations.CreateCardDexIds do
  use Ecto.Migration

  def change do
    create table(:card_dex_ids, primary_key: false) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :dex_id, references(:pokemon_species, on_delete: :restrict),
        null: false,
        primary_key: true
    end

    create index(:card_dex_ids, [:dex_id])
  end
end
