defmodule Pokevestment.Repo.Migrations.AddLanguageCountToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :language_count, :integer, null: false, default: 1
    end

    create index(:cards, [:language_count])
  end
end
