defmodule Pokevestment.ML.FeatureDescriptionsTest do
  use ExUnit.Case, async: true

  alias Pokevestment.ML.FeatureDescriptions

  describe "label/1" do
    test "returns known label for registered features" do
      assert FeatureDescriptions.label("meta_share_30d") == "30-day Meta Share"
      assert FeatureDescriptions.label("hp") == "HP"
      assert FeatureDescriptions.label("rarity") == "Rarity"
      assert FeatureDescriptions.label("price_volatility") == "Price Volatility"
    end

    test "humanizes unknown feature names" do
      assert FeatureDescriptions.label("some_unknown_feature") == "Some Unknown Feature"
    end
  end

  describe "explain_direction/2" do
    test "returns high explanation for positive SHAP" do
      result = FeatureDescriptions.explain_direction("meta_share_30d", 0.15)
      assert result =~ "Heavily played"
    end

    test "returns low explanation for negative SHAP" do
      result = FeatureDescriptions.explain_direction("meta_share_30d", -0.05)
      assert result =~ "Rarely seen"
    end

    test "handles unknown features with generic message" do
      result = FeatureDescriptions.explain_direction("unknown_feat", 0.1)
      assert result =~ "increases predicted value"

      result = FeatureDescriptions.explain_direction("unknown_feat", -0.1)
      assert result =~ "decreases predicted value"
    end

    test "treats zero as positive direction" do
      result = FeatureDescriptions.explain_direction("hp", 0.0)
      assert result =~ "High HP"
    end
  end

  describe "get/1" do
    test "returns description map for known features" do
      desc = FeatureDescriptions.get("meta_share_30d")
      assert desc.label == "30-day Meta Share"
      assert is_binary(desc.high)
      assert is_binary(desc.low)
      assert desc.category == "tournament_meta"
    end

    test "returns nil for unknown features" do
      assert FeatureDescriptions.get("nonexistent") == nil
    end
  end

  describe "category/1" do
    test "returns category for known features" do
      assert FeatureDescriptions.category("meta_share_30d") == "tournament_meta"
      assert FeatureDescriptions.category("rarity") == "rarity_collectibility"
      assert FeatureDescriptions.category("hp") == "card_attributes"
      assert FeatureDescriptions.category("price_volatility") == "price_momentum"
      assert FeatureDescriptions.category("days_since_release") == "supply_proxy"
      assert FeatureDescriptions.category("is_legendary") == "species"
      assert FeatureDescriptions.category("illustrator_frequency") == "illustrator"
    end

    test "returns other for unknown features" do
      assert FeatureDescriptions.category("unknown") == "other"
    end
  end

  describe "all/0" do
    test "returns a map with many features" do
      all = FeatureDescriptions.all()
      assert is_map(all)
      assert map_size(all) > 30
    end

    test "every feature has required fields" do
      for {_name, desc} <- FeatureDescriptions.all() do
        assert is_binary(desc.label)
        assert is_binary(desc.description)
        assert is_binary(desc.high)
        assert is_binary(desc.low)
        assert is_binary(desc.category)
      end
    end
  end
end
