defmodule Pokevestment.ML.HorizonProjectorTest do
  use ExUnit.Case, async: true

  alias Pokevestment.ML.HorizonProjector

  @horizons ~w(1 7 30 90 365)

  describe "project/3" do
    test "returns projections for all 5 horizons" do
      result = HorizonProjector.project(10.0, 15.0)
      assert map_size(result) == 5
      assert Enum.all?(@horizons, &Map.has_key?(result, &1))
    end

    test "each horizon has projected_price, projected_return, and confidence" do
      result = HorizonProjector.project(10.0, 15.0)

      for {_horizon, data} <- result do
        assert %Decimal{} = data["projected_price"]
        assert %Decimal{} = data["projected_return"]
        assert data["confidence"] in ["low", "medium", "high"]
      end
    end

    test "projected prices converge toward fair value over longer horizons" do
      result = HorizonProjector.project(10.0, 20.0)

      prices =
        @horizons
        |> Enum.map(fn h -> {h, Decimal.to_float(result[h]["projected_price"])} end)

      # Each horizon should be closer to fair value than the previous
      for [{_h1, p1}, {_h2, p2}] <- Enum.chunk_every(prices, 2, 1, :discard) do
        assert p2 >= p1
      end
    end

    test "returns positive returns when fair value > current price" do
      result = HorizonProjector.project(10.0, 15.0)

      for {_horizon, data} <- result do
        assert Decimal.compare(data["projected_return"], Decimal.new(0)) == :gt
      end
    end

    test "returns negative returns when fair value < current price" do
      result = HorizonProjector.project(15.0, 10.0)

      for {_horizon, data} <- result do
        assert Decimal.compare(data["projected_return"], Decimal.new(0)) == :lt
      end
    end

    test "returns empty map for zero current price" do
      assert HorizonProjector.project(0, 15.0) == %{}
    end

    test "returns empty map for negative current price" do
      assert HorizonProjector.project(-5, 15.0) == %{}
    end

    test "returns empty map for nil inputs" do
      assert HorizonProjector.project(nil, 15.0) == %{}
      assert HorizonProjector.project(10.0, nil) == %{}
    end

    test "accepts volatility option" do
      low_vol = HorizonProjector.project(10.0, 15.0, volatility: 0.05)
      high_vol = HorizonProjector.project(10.0, 15.0, volatility: 0.9)

      # Higher volatility increases lambda, so convergence is faster
      low_30d = Decimal.to_float(low_vol["30"]["projected_price"])
      high_30d = Decimal.to_float(high_vol["30"]["projected_price"])
      assert high_30d > low_30d
    end

    test "accepts days_since_release option" do
      new_card = HorizonProjector.project(10.0, 15.0, days_since_release: 30)
      old_card = HorizonProjector.project(10.0, 15.0, days_since_release: 400)

      # Older cards get faster convergence
      new_90d = Decimal.to_float(new_card["90"]["projected_price"])
      old_90d = Decimal.to_float(old_card["90"]["projected_price"])
      assert old_90d > new_90d
    end

    test "accepts meta_share option" do
      no_meta = HorizonProjector.project(10.0, 15.0, meta_share: 0.0)
      high_meta = HorizonProjector.project(10.0, 15.0, meta_share: 0.05)

      no_30d = Decimal.to_float(no_meta["30"]["projected_price"])
      high_30d = Decimal.to_float(high_meta["30"]["projected_price"])
      assert high_30d > no_30d
    end

    test "confidence is high for short horizons with low volatility and old cards" do
      result = HorizonProjector.project(10.0, 15.0, volatility: 0.1, days_since_release: 200)
      assert result["1"]["confidence"] == "high"
      assert result["7"]["confidence"] == "high"
    end

    test "confidence is low for long horizons with high volatility and new cards" do
      result = HorizonProjector.project(10.0, 15.0, volatility: 0.5, days_since_release: 10)
      assert result["365"]["confidence"] == "low"
    end

    test "handles integer inputs" do
      result = HorizonProjector.project(10, 15)
      assert map_size(result) == 5
    end

    test "handles Decimal opts via ensure_float" do
      result = HorizonProjector.project(10.0, 15.0, volatility: Decimal.from_float(0.2))
      assert map_size(result) == 5
    end
  end
end
