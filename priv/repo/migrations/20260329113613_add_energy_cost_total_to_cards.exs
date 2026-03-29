defmodule Pokevestment.Repo.Migrations.AddEnergyCostTotalToCards do
  use Ecto.Migration

  def change do
    alter table(:cards) do
      add :energy_cost_total, :integer, null: false, default: 0
    end
  end
end
