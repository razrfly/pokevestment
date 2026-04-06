defmodule Pokevestment.ML.AccountabilityTest do
  use Pokevestment.DataCase, async: true

  alias Pokevestment.ML.Accountability

  describe "signal_accuracy/1" do
    test "returns empty map when no outcomes exist" do
      assert Accountability.signal_accuracy() == %{}
    end

    test "returns empty map for unknown model version" do
      assert Accountability.signal_accuracy("v99.0.0") == %{}
    end
  end

  describe "signal_calibration/1" do
    test "returns empty map when no outcomes exist" do
      assert Accountability.signal_calibration() == %{}
    end
  end

  describe "accuracy_over_time/2" do
    test "returns empty list when no outcomes exist" do
      assert Accountability.accuracy_over_time() == []
    end

    test "returns empty list for unknown model version" do
      assert Accountability.accuracy_over_time("v99.0.0") == []
    end
  end

  describe "latest_evaluation/1" do
    test "returns nil when no evaluations exist" do
      assert Accountability.latest_evaluation() == nil
    end
  end

  describe "pipeline_status/0" do
    test "returns empty list when no jobs have run" do
      assert Accountability.pipeline_status() == []
    end
  end

  describe "outcome_readiness/0" do
    test "returns zero counts on empty database" do
      result = Accountability.outcome_readiness()

      assert result.mature_snapshots == 0
      assert result.evaluated == 0
      assert result.pending_evaluation == 0
      assert result.earliest_maturity == nil
    end
  end

  describe "price_history_range/0" do
    test "returns nil dates and zero days on empty database" do
      result = Accountability.price_history_range()

      assert result.earliest == nil
      assert result.latest == nil
      assert result.days == 0
    end
  end
end
