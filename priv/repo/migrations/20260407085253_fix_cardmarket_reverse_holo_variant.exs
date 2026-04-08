defmodule Pokevestment.Repo.Migrations.FixCardmarketReverseHoloVariant do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE price_snapshots
    SET variant = 'reverse-holofoil'
    WHERE source = 'cardmarket'
      AND variant = 'holo'
      AND metadata IS NOT NULL
    """)
  end

  def down do
    execute("""
    UPDATE price_snapshots
    SET variant = 'holo'
    WHERE source = 'cardmarket'
      AND variant = 'reverse-holofoil'
      AND metadata IS NOT NULL
    """)
  end
end
