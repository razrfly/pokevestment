defmodule Pokevestment.Repo.Migrations.AddHorizonDaysCheckConstraint do
  use Ecto.Migration

  def change do
    create constraint(:prediction_outcomes, :prediction_outcomes_horizon_days_positive,
             check: "horizon_days > 0"
           )
  end
end
