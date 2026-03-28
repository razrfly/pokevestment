defmodule Pokevestment.Repo.Migrations.CreatePokemonSpecies do
  use Ecto.Migration

  def change do
    create table(:pokemon_species, primary_key: false) do
      add :id, :integer, primary_key: true
      add :name, :string, size: 50, null: false
      add :generation, :integer, null: false
      add :is_legendary, :boolean, null: false, default: false
      add :is_mythical, :boolean, null: false, default: false
      add :is_baby, :boolean, null: false, default: false
      add :color, :string, size: 20
      add :habitat, :string, size: 30
      add :shape, :string, size: 30
      add :capture_rate, :integer
      add :base_happiness, :integer
      add :growth_rate, :string, size: 30
      add :flavor_text, :text
      add :genus, :string, size: 50
      add :sprite_url, :text
      add :evolves_from_species_id, references(:pokemon_species, on_delete: :nilify_all)
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pokemon_species, [:name])
    create index(:pokemon_species, [:generation])
    create index(:pokemon_species, [:evolves_from_species_id])
  end
end
