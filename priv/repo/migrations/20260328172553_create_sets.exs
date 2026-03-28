defmodule Pokevestment.Repo.Migrations.CreateSets do
  use Ecto.Migration

  def change do
    create table(:sets, primary_key: false) do
      add :id, :string, size: 30, primary_key: true
      add :name, :string, size: 100, null: false
      add :series_id, references(:series, type: :string, on_delete: :restrict), null: false
      add :release_date, :date
      add :card_count_official, :integer
      add :card_count_total, :integer
      add :logo_url, :text
      add :symbol_url, :text
      add :ptcgo_code, :string, size: 10
      add :legal_standard, :boolean, default: false
      add :legal_expanded, :boolean, default: false
      add :card_count_breakdown, :map
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:sets, [:series_id])
    create index(:sets, [:release_date])
  end
end
