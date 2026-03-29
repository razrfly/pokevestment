defmodule Pokevestment.Repo.Migrations.AddVariantFeatureColumnsToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :first_edition, :boolean, null: false, default: false
      add :is_shadowless, :boolean, null: false, default: false
      add :has_first_edition_stamp, :boolean, null: false, default: false
    end

    create index(:cards, [:first_edition])
    create index(:cards, [:is_shadowless])
    create index(:cards, [:has_first_edition_stamp])
  end
end
