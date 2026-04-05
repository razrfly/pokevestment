defmodule PokevestmentWeb.Router do
  use PokevestmentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PokevestmentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PokevestmentWeb do
    pipe_through :browser

    live "/", HomeLive, :index

    live "/sets", SetLive.Index, :index
    live "/sets/:id", SetLive.Show, :show
  end

  scope "/api", PokevestmentWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end
end
