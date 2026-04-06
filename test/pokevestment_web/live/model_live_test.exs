defmodule PokevestmentWeb.ModelLiveTest do
  use PokevestmentWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "ModelLive.Index" do
    test "renders successfully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ "Model accountability"
    end

    test "shows trust level banner", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      # Empty DB → LOW trust
      assert html =~ "LOW"
      assert html =~ "Model has not yet been validated"
    end

    test "shows empty training metrics state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ "No model evaluation recorded yet"
      assert html =~ "Run the ML pipeline"
    end

    test "shows waiting state for signal accuracy", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ "Waiting for outcome data"
      assert html =~ "Signal accuracy will appear here"
    end

    test "shows pipeline health with all 4 workers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ "Pipeline Health"
      assert html =~ "Price Sync"
      assert html =~ "Tournament Sync"
      assert html =~ "ML Predictions"
      assert html =~ "Outcome Evaluator"
    end

    test "shows all 8 accountability checklist items", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ "Accountability Checklist"
      assert html =~ "Model evaluation metrics recorded per run"
      assert html =~ "Baseline comparison (mean predictor) logged"
      assert html =~ "SHAP feature importances computed per run"
      assert html =~ "Prediction snapshots stored (append-only)"
      assert html =~ "Outcome tracking deployed"
      assert html =~ "Temporal train/val split"
      assert html =~ "Walk-forward backtest"
      assert html =~ "Sacred holdout set"
    end

    test "shows Models nav link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/models")

      assert html =~ ~s(href="/models")
      assert html =~ "Models"
    end
  end
end
