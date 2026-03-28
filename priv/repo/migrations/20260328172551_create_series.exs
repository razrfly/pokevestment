defmodule Pokevestment.Repo.Migrations.CreateSeries do
  use Ecto.Migration

  def change do
    create table(:series, primary_key: false) do
      add :id, :string, size: 30, primary_key: true
      add :name, :string, size: 100, null: false
      add :logo_url, :text
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end
  end
end
