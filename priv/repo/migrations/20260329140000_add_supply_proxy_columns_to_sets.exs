defmodule Pokevestment.Repo.Migrations.AddSupplyProxyColumnsToSets do
  use Ecto.Migration

  def change do
    alter table(:sets) do
      add :secret_rare_count, :integer
      add :secret_rare_ratio, :decimal, precision: 5, scale: 4
      add :era, :string, size: 20
    end

    create index(:sets, [:era])
  end
end
