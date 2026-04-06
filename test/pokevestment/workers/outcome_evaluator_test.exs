defmodule Pokevestment.Workers.OutcomeEvaluatorTest do
  use Pokevestment.DataCase, async: true

  alias Pokevestment.Workers.OutcomeEvaluator

  describe "perform/1" do
    test "returns :ok with no mature snapshots" do
      assert :ok = OutcomeEvaluator.perform(%Oban.Job{})
    end

    test "returns :ok with empty database" do
      # Verify no prediction_outcomes are created when there are no snapshots
      assert :ok = OutcomeEvaluator.perform(%Oban.Job{})
      assert Pokevestment.Repo.aggregate(Pokevestment.ML.PredictionOutcome, :count) == 0
    end
  end
end
