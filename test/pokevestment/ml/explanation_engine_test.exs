defmodule Pokevestment.ML.ExplanationEngineTest do
  use ExUnit.Case, async: true

  alias Pokevestment.ML.ExplanationEngine

  @base_prediction %{
    signal: "STRONG_BUY",
    current_price: Decimal.from_float(8.50),
    predicted_fair_value: Decimal.from_float(12.40),
    value_ratio: Decimal.from_float(1.46),
    price_currency: "USD",
    top_positive_drivers: %{
      "meta_share_30d" => 0.14,
      "tournament_appearances" => 0.08,
      "is_full_art" => 0.05
    },
    top_negative_drivers: %{
      "price_volatility" => -0.03,
      "days_since_release" => -0.01
    }
  }

  describe "generate/1 with INSUFFICIENT_DATA" do
    test "returns structured map with empty reasons" do
      result = ExplanationEngine.generate(%{signal: "INSUFFICIENT_DATA"})

      assert is_map(result)
      assert result["summary"] =~ "Not enough pricing data"
      assert result["positive_reasons"] == []
      assert result["negative_reasons"] == []
    end
  end

  describe "generate/1 with STRONG_BUY" do
    test "returns structured map with summary and reasons" do
      result = ExplanationEngine.generate(@base_prediction)

      assert is_map(result)
      assert is_binary(result["summary"])
      assert is_list(result["positive_reasons"])
      assert is_list(result["negative_reasons"])
    end

    test "summary mentions undervalued and includes prices" do
      result = ExplanationEngine.generate(@base_prediction)

      assert result["summary"] =~ "significantly undervalued"
      assert result["summary"] =~ "$8.50"
      assert result["summary"] =~ "$12.40"
      assert result["summary"] =~ "upside"
    end

    test "includes up to 3 positive reasons" do
      result = ExplanationEngine.generate(@base_prediction)

      assert length(result["positive_reasons"]) <= 3
      assert length(result["positive_reasons"]) > 0

      for reason <- result["positive_reasons"] do
        assert is_binary(reason["feature"])
        assert is_binary(reason["label"])
        assert is_binary(reason["explanation"])
      end
    end

    test "includes up to 2 negative reasons" do
      result = ExplanationEngine.generate(@base_prediction)

      assert length(result["negative_reasons"]) <= 2

      for reason <- result["negative_reasons"] do
        assert is_binary(reason["feature"])
        assert is_binary(reason["label"])
        assert is_binary(reason["explanation"])
      end
    end

    test "summary mentions counter-argument from top negative driver" do
      result = ExplanationEngine.generate(@base_prediction)
      assert result["summary"] =~ "However"
    end
  end

  describe "generate/1 with BUY" do
    test "says undervalued (not significantly)" do
      prediction = Map.put(@base_prediction, :signal, "BUY")
      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "undervalued"
      refute result["summary"] =~ "significantly undervalued"
    end
  end

  describe "generate/1 with HOLD" do
    test "says fairly priced" do
      prediction = Map.put(@base_prediction, :signal, "HOLD")
      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "fairly priced"
    end
  end

  describe "generate/1 with OVERVALUED" do
    test "says overpriced and mentions downside" do
      prediction = Map.put(@base_prediction, :signal, "OVERVALUED")
      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "overpriced"
      assert result["summary"] =~ "downside"
    end

    test "mentions positive support if available" do
      prediction = Map.put(@base_prediction, :signal, "OVERVALUED")
      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "support"
    end
  end

  describe "generate/1 with no drivers" do
    test "handles empty driver maps" do
      prediction = %{
        signal: "HOLD",
        current_price: Decimal.from_float(5.0),
        predicted_fair_value: Decimal.from_float(5.0),
        price_currency: "USD",
        top_positive_drivers: %{},
        top_negative_drivers: %{}
      }

      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "fairly priced"
      assert result["positive_reasons"] == []
      assert result["negative_reasons"] == []
    end
  end

  describe "generate/1 with EUR currency" do
    test "uses euro symbol in summary" do
      prediction = Map.put(@base_prediction, :price_currency, "EUR")
      result = ExplanationEngine.generate(prediction)

      assert result["summary"] =~ "\u20AC"
    end
  end

  describe "generate/1 with nil/missing fields" do
    test "returns nil for unmatched input" do
      assert ExplanationEngine.generate(%{}) == nil
      assert ExplanationEngine.generate(nil) == nil
    end

    test "handles nil prices gracefully" do
      prediction = %{
        signal: "STRONG_BUY",
        current_price: nil,
        predicted_fair_value: nil,
        price_currency: nil,
        top_positive_drivers: %{},
        top_negative_drivers: %{}
      }

      result = ExplanationEngine.generate(prediction)
      assert is_binary(result["summary"])
    end
  end
end
