defmodule PokevestmentWeb.PageController do
  use PokevestmentWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: {PokevestmentWeb.Layouts, :app})
  end
end
