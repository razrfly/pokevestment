defmodule Pokevestment.Repo do
  use Ecto.Repo,
    otp_app: :pokevestment,
    adapter: Ecto.Adapters.Postgres
end
