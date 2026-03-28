defmodule Pokevestment.Repo.Migrations.CreateCardTypes do
  use Ecto.Migration

  def change do
    create table(:card_types, primary_key: false) do
      add :card_id, references(:cards, type: :string, on_delete: :delete_all), null: false, primary_key: true
      add :type_name, :string, size: 20, null: false, primary_key: true
    end

    create index(:card_types, [:type_name])
  end
end
