defmodule Pokevestment.Ingestion.FeatureExtractorTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Ingestion.FeatureExtractor

  describe "compute_art_features/1" do
    # Standard rarities
    test "Common maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Common"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "Uncommon maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Uncommon"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "Rare maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Rare"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "None maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "None"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    # Holo rarities
    test "Holo Rare maps to holo" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Holo Rare"}) ==
               %{art_type: "holo", is_full_art: false, is_alternate_art: false}
    end

    test "Rare Holo maps to holo" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Rare Holo"}) ==
               %{art_type: "holo", is_full_art: false, is_alternate_art: false}
    end

    # Premium holo
    test "Rare Holo LV.X maps to premium_holo" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Rare Holo LV.X"}) ==
               %{art_type: "premium_holo", is_full_art: true, is_alternate_art: false}
    end

    test "LEGEND maps to premium_holo" do
      assert FeatureExtractor.compute_art_features(%{rarity: "LEGEND"}) ==
               %{art_type: "premium_holo", is_full_art: true, is_alternate_art: false}
    end

    # Mechanic ultra
    test "Holo Rare V maps to mechanic_ultra" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Holo Rare V"}) ==
               %{art_type: "mechanic_ultra", is_full_art: true, is_alternate_art: false}
    end

    test "Holo Rare VMAX maps to mechanic_ultra" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Holo Rare VMAX"}) ==
               %{art_type: "mechanic_ultra", is_full_art: true, is_alternate_art: false}
    end

    test "Holo Rare VSTAR maps to mechanic_ultra" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Holo Rare VSTAR"}) ==
               %{art_type: "mechanic_ultra", is_full_art: true, is_alternate_art: false}
    end

    # Full art / Ultra Rare
    test "Ultra Rare maps to full_art" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Ultra Rare"}) ==
               %{art_type: "full_art", is_full_art: true, is_alternate_art: true}
    end

    test "Full Art Trainer maps to full_art" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Full Art Trainer"}) ==
               %{art_type: "full_art", is_full_art: true, is_alternate_art: true}
    end

    # Illustration rares
    test "Illustration rare maps to illustration" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Illustration rare"}) ==
               %{art_type: "illustration", is_full_art: true, is_alternate_art: true}
    end

    test "Special illustration rare maps to special_illustration" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Special illustration rare"}) ==
               %{art_type: "special_illustration", is_full_art: true, is_alternate_art: true}
    end

    # Hyper rare
    test "Hyper rare maps to hyper_rare" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Hyper rare"}) ==
               %{art_type: "hyper_rare", is_full_art: true, is_alternate_art: true}
    end

    # Amazing Rare
    test "Amazing Rare maps to amazing" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Amazing Rare"}) ==
               %{art_type: "amazing", is_full_art: false, is_alternate_art: true}
    end

    # Shiny rarities — is_full_art varies
    test "Shiny rare has is_full_art false" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Shiny rare"}) ==
               %{art_type: "shiny", is_full_art: false, is_alternate_art: true}
    end

    test "Shiny rare V has is_full_art true" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Shiny rare V"}) ==
               %{art_type: "shiny", is_full_art: true, is_alternate_art: true}
    end

    test "Shiny rare VMAX has is_full_art true" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Shiny rare VMAX"}) ==
               %{art_type: "shiny", is_full_art: true, is_alternate_art: true}
    end

    test "Shiny Ultra Rare has is_full_art true" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Shiny Ultra Rare"}) ==
               %{art_type: "shiny", is_full_art: true, is_alternate_art: true}
    end

    # Crown, Secret, ACE SPEC
    test "Crown maps correctly" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Crown"}) ==
               %{art_type: "crown", is_full_art: true, is_alternate_art: true}
    end

    test "Secret Rare maps correctly" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Secret Rare"}) ==
               %{art_type: "secret", is_full_art: true, is_alternate_art: true}
    end

    test "ACE SPEC Rare maps to ace_spec" do
      assert FeatureExtractor.compute_art_features(%{rarity: "ACE SPEC Rare"}) ==
               %{art_type: "ace_spec", is_full_art: false, is_alternate_art: false}
    end

    # Double/Mega ultra
    test "Double rare maps to ultra" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Double rare"}) ==
               %{art_type: "ultra", is_full_art: true, is_alternate_art: true}
    end

    test "Mega Hyper Rare maps to ultra" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Mega Hyper Rare"}) ==
               %{art_type: "ultra", is_full_art: true, is_alternate_art: true}
    end

    # Pocket TCG diamond rarities
    test "One Diamond maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "One Diamond"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "Four Diamond maps to holo" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Four Diamond"}) ==
               %{art_type: "holo", is_full_art: false, is_alternate_art: false}
    end

    # Pocket TCG star rarities
    test "One Star maps to illustration" do
      assert FeatureExtractor.compute_art_features(%{rarity: "One Star"}) ==
               %{art_type: "illustration", is_full_art: true, is_alternate_art: true}
    end

    test "Two Star maps to special_illustration" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Two Star"}) ==
               %{art_type: "special_illustration", is_full_art: true, is_alternate_art: true}
    end

    test "Three Star maps to crown" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Three Star"}) ==
               %{art_type: "crown", is_full_art: true, is_alternate_art: true}
    end

    # Pocket TCG shiny rarities
    test "One Shiny maps to shiny with is_full_art false" do
      assert FeatureExtractor.compute_art_features(%{rarity: "One Shiny"}) ==
               %{art_type: "shiny", is_full_art: false, is_alternate_art: true}
    end

    test "Two Shiny maps to shiny with is_full_art true" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Two Shiny"}) ==
               %{art_type: "shiny", is_full_art: true, is_alternate_art: true}
    end

    # Miscellaneous unmapped
    test "Classic Collection maps to standard with alt art" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Classic Collection"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: true}
    end

    test "Radiant Rare maps to amazing" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Radiant Rare"}) ==
               %{art_type: "amazing", is_full_art: false, is_alternate_art: true}
    end

    test "Black White Rare maps to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Black White Rare"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    # Defaults / fallbacks
    test "nil rarity defaults to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: nil}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "missing rarity key defaults to standard" do
      assert FeatureExtractor.compute_art_features(%{}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    test "unknown rarity falls back to standard" do
      assert FeatureExtractor.compute_art_features(%{rarity: "Super Duper Rare"}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end

    # String-keyed map support
    test "accepts string-keyed map" do
      assert FeatureExtractor.compute_art_features(%{"rarity" => "Illustration rare"}) ==
               %{art_type: "illustration", is_full_art: true, is_alternate_art: true}
    end

    test "string-keyed nil rarity defaults to standard" do
      assert FeatureExtractor.compute_art_features(%{"rarity" => nil}) ==
               %{art_type: "standard", is_full_art: false, is_alternate_art: false}
    end
  end

  describe "compute_set_features/1" do
    test "normal set computes secret rare count, ratio, and era" do
      result =
        FeatureExtractor.compute_set_features(%{
          card_count_official: 200,
          card_count_total: 250,
          series_id: "sv"
        })

      assert result.secret_rare_count == 50
      assert Decimal.equal?(result.secret_rare_ratio, Decimal.div(50, 200))
      assert result.era == "sv"
    end

    test "promo set with official=0 has nil ratio but valid count" do
      result =
        FeatureExtractor.compute_set_features(%{
          card_count_official: 0,
          card_count_total: 10,
          series_id: "mc"
        })

      assert result.secret_rare_count == 10
      assert result.secret_rare_ratio == nil
      assert result.era == "promo"
    end

    test "nil counts produce nil outputs except era" do
      result =
        FeatureExtractor.compute_set_features(%{
          card_count_official: nil,
          card_count_total: nil,
          series_id: "bw"
        })

      assert result.secret_rare_count == nil
      assert result.secret_rare_ratio == nil
      assert result.era == "bw"
    end

    test "col maps to hgss era" do
      result =
        FeatureExtractor.compute_set_features(%{
          card_count_official: 95,
          card_count_total: 106,
          series_id: "col"
        })

      assert result.era == "hgss"
    end

    test "unknown series_id maps to nil era" do
      result =
        FeatureExtractor.compute_set_features(%{
          card_count_official: 100,
          card_count_total: 120,
          series_id: "unknown"
        })

      assert result.secret_rare_count == 20
      assert result.era == nil
    end

    test "accepts string-keyed maps" do
      result =
        FeatureExtractor.compute_set_features(%{
          "card_count_official" => 150,
          "card_count_total" => 180,
          "series_id" => "xy"
        })

      assert result.secret_rare_count == 30
      assert result.era == "xy"
    end
  end
end
