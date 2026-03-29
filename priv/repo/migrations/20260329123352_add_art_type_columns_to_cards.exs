defmodule Pokevestment.Repo.Migrations.AddArtTypeColumnsToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :art_type, :string, size: 30, null: false, default: "standard"
      add :is_full_art, :boolean, null: false, default: false
      add :is_alternate_art, :boolean, null: false, default: false
    end

    create index(:cards, [:art_type])
    create index(:cards, [:is_full_art])
    create index(:cards, [:is_alternate_art])

    create index(:cards, [:art_type, :is_full_art, :is_alternate_art],
             name: :cards_art_feature_vector_index
           )
  end
end
