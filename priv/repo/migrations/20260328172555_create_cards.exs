defmodule Pokevestment.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards, primary_key: false) do
      add :id, :string, size: 30, primary_key: true
      add :name, :string, size: 150, null: false
      add :local_id, :string, size: 20, null: false
      add :category, :string, size: 20, null: false
      add :set_id, references(:sets, type: :string, on_delete: :restrict), null: false
      add :rarity, :string, size: 50
      add :hp, :integer
      add :stage, :string, size: 20
      add :suffix, :string, size: 30
      add :illustrator, :string, size: 100
      add :evolves_from, :string, size: 150
      add :retreat_cost, :integer
      add :regulation_mark, :string, size: 5
      add :energy_type, :string, size: 20
      add :trainer_type, :string, size: 20
      add :legal_standard, :boolean, default: false
      add :legal_expanded, :boolean, default: false
      add :is_secret_rare, :boolean, null: false, default: false
      add :generation, :integer
      add :variants, :map
      add :variants_detailed, {:array, :map}
      add :attacks, {:array, :map}
      add :abilities, {:array, :map}
      add :weaknesses, {:array, :map}
      add :resistances, {:array, :map}
      add :image_url, :text
      add :api_updated_at, :utc_datetime
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:cards, [:set_id])
    create index(:cards, [:name])
    create index(:cards, [:category])
    create index(:cards, [:rarity])
    create index(:cards, [:illustrator])
    create index(:cards, [:regulation_mark])
    create index(:cards, [:generation])
    create unique_index(:cards, [:set_id, :local_id])

    # Partial index for secret rare cards
    create index(:cards, [:is_secret_rare], where: "is_secret_rare = true")
  end
end
