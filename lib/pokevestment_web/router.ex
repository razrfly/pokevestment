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

  pipeline :admin do
    plug :admin_auth
  end

  scope "/", PokevestmentWeb do
    pipe_through :browser

    live "/", HomeLive, :index

    live "/sets", SetLive.Index, :index
    live "/sets/:id", SetLive.Show, :show
    live "/sets/:set_id/cards/:card_id", CardLive.Show, :show

    live "/models", ModelLive.Index, :index
  end

  scope "/api", PokevestmentWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Admin dashboard - protected with basic auth
  import Oban.Web.Router

  scope "/admin" do
    pipe_through [:browser, :admin]

    oban_dashboard("/oban")
  end

  defp admin_auth(conn, _opts) do
    if Application.get_env(:pokevestment, :admin_auth_disabled, false) do
      conn
    else
      username =
        case System.get_env("ADMIN_USERNAME") do
          nil -> "admin"
          val ->
            trimmed = String.trim(val)
            if trimmed == "", do: "admin", else: trimmed
        end

      password =
        case System.get_env("ADMIN_PASSWORD") do
          nil -> raise "ADMIN_PASSWORD must be set"
          val ->
            trimmed = String.trim(val)
            if trimmed == "", do: raise("ADMIN_PASSWORD must not be blank"), else: trimmed
        end

      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    end
  end
end
