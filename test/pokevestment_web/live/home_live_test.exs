defmodule PokevestmentWeb.HomeLiveTest do
  use PokevestmentWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "HomeLive" do
    test "renders the homepage", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Data-driven Pokemon card investment insights"
      assert html =~ "Get Started"
    end

    test "displays features section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Tournament Meta Analysis"
      assert html =~ "Price Intelligence"
      assert html =~ "Investment Signals"
    end

    test "displays stats section with real counts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Cards Tracked"
      assert html =~ "Tournaments Analyzed"
      assert html =~ "Sets Covered"
    end

    test "displays CTA section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Ready to invest smarter?"
    end
  end
end
