defmodule PokevestmentWeb.Router do
  use PokevestmentWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", PokevestmentWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end
end
