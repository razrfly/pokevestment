defmodule Pokevestment.PredictionsTest do
  use Pokevestment.DataCase, async: true

  alias Pokevestment.Predictions

  describe "top_buys/1" do
    test "returns empty list when no predictions exist" do
      assert Predictions.top_buys() == []
    end

    test "respects limit parameter" do
      assert Predictions.top_buys(3) == []
    end
  end

  describe "global_signal_summary/0" do
    test "returns empty map when no predictions exist" do
      assert Predictions.global_signal_summary() == %{}
    end
  end

  describe "top_sets_by_signals/1" do
    test "returns empty list when no predictions exist" do
      assert Predictions.top_sets_by_signals() == []
    end
  end

  describe "homepage_stats/0" do
    test "returns zero counts on empty database" do
      stats = Predictions.homepage_stats()

      assert stats.cards == 0
      assert stats.sets == 0
      assert stats.tournaments == 0
    end
  end

  describe "last_prediction_date/0" do
    test "returns nil when no predictions exist" do
      assert Predictions.last_prediction_date() == nil
    end
  end
end
