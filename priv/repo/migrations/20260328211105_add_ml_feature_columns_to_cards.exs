defmodule Pokevestment.Repo.Migrations.AddMlFeatureColumnsToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :attack_count, :integer, null: false, default: 0
      add :total_attack_damage, :integer, null: false, default: 0
      add :max_attack_damage, :integer, null: false, default: 0
      add :has_ability, :boolean, null: false, default: false
      add :ability_count, :integer, null: false, default: 0
      add :weakness_count, :integer, null: false, default: 0
      add :resistance_count, :integer, null: false, default: 0
    end

    create index(:cards, [:attack_count])
    create index(:cards, [:has_ability])
    create index(:cards, [:total_attack_damage])
    create index(:cards, [:max_attack_damage])

    create index(:cards, [:attack_count, :has_ability, :weakness_count, :resistance_count],
      name: :cards_ml_feature_vector_index
    )
  end
end
