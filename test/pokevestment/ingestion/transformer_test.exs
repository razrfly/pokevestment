defmodule Pokevestment.Ingestion.TransformerTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Ingestion.Transformer

  # --- normalize_variant/1 ---

  describe "normalize_variant/1" do
    test "converts camelCase variants to kebab-case" do
      assert Transformer.normalize_variant("reverseHolofoil") == "reverse-holofoil"
      assert Transformer.normalize_variant("1stEdition") == "1st-edition"
      assert Transformer.normalize_variant("1stEditionHolofoil") == "1st-edition-holofoil"
      assert Transformer.normalize_variant("1stEditionNormal") == "1st-edition-normal"
      assert Transformer.normalize_variant("unlimitedHolofoil") == "unlimited-holofoil"
    end

    test "passes through already-correct names" do
      assert Transformer.normalize_variant("normal") == "normal"
      assert Transformer.normalize_variant("holofoil") == "holofoil"
      assert Transformer.normalize_variant("reverse-holofoil") == "reverse-holofoil"
      assert Transformer.normalize_variant("unlimited") == "unlimited"
    end
  end

  # --- build_tcgplayer_snapshots (variant normalization) ---

  describe "build_price_snapshots/2 TCGdex path" do
    test "normalizes variant names from TCGdex pricing" do
      pricing = %{
        "tcgplayer" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "USD",
          "reverseHolofoil" => %{
            "lowPrice" => 1.0,
            "midPrice" => 2.0,
            "highPrice" => 3.0,
            "marketPrice" => 2.5
          },
          "1stEditionHolofoil" => %{
            "lowPrice" => 10.0,
            "midPrice" => 20.0,
            "highPrice" => 30.0,
            "marketPrice" => 25.0
          }
        }
      }

      snapshots = Transformer.build_price_snapshots("test-001", pricing)

      variants = Enum.map(snapshots, & &1.variant)
      assert "reverse-holofoil" in variants
      assert "1st-edition-holofoil" in variants
      refute "reverseHolofoil" in variants
      refute "1stEditionHolofoil" in variants
    end
  end

  # --- build_cardmarket_snapshots (garbage holo filtering) ---

  describe "build_price_snapshots/2 cardmarket holo filtering" do
    test "rejects holo row when all holo values are zero" do
      pricing = %{
        "cardmarket" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "EUR",
          "low" => 1.0,
          "avg" => 2.0,
          "trend" => 1.5,
          "avg-holo" => 0,
          "low-holo" => 0,
          "trend-holo" => 0,
          "avg1-holo" => 0,
          "avg7-holo" => 0,
          "avg30-holo" => 0
        }
      }

      snapshots = Transformer.build_price_snapshots("test-001", pricing)
      variants = Enum.map(snapshots, & &1.variant)
      assert "normal" in variants
      refute "holo" in variants
    end

    test "rejects holo row when all holo values are nil" do
      pricing = %{
        "cardmarket" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "EUR",
          "low" => 1.0,
          "avg" => 2.0,
          "trend" => 1.5
        }
      }

      snapshots = Transformer.build_price_snapshots("test-001", pricing)
      variants = Enum.map(snapshots, & &1.variant)
      assert "normal" in variants
      refute "holo" in variants
    end

    test "includes holo row when at least one value is positive" do
      pricing = %{
        "cardmarket" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "EUR",
          "low" => 1.0,
          "avg" => 2.0,
          "trend" => 1.5,
          "avg-holo" => 5.0,
          "low-holo" => nil,
          "trend-holo" => nil,
          "avg1-holo" => nil,
          "avg7-holo" => nil,
          "avg30-holo" => nil
        }
      }

      snapshots = Transformer.build_price_snapshots("test-001", pricing)
      variants = Enum.map(snapshots, & &1.variant)
      assert "normal" in variants
      assert "holo" in variants
    end
  end

  # --- parse_datetime/1 ---

  describe "parse_datetime/1" do
    test "parses ISO 8601 format" do
      assert %DateTime{year: 2026, month: 4, day: 1} =
               Transformer.parse_datetime("2026-04-01T00:00:00Z")
    end

    test "parses YYYY/MM/DD slash format from Pokemon TCG API" do
      result = Transformer.parse_datetime("2026/04/06")
      assert %DateTime{year: 2026, month: 4, day: 6} = result
      assert result.hour == 0
      assert result.minute == 0
    end

    test "returns nil for nil input" do
      assert Transformer.parse_datetime(nil) == nil
    end

    test "returns nil for invalid strings" do
      assert Transformer.parse_datetime("not-a-date") == nil
      assert Transformer.parse_datetime("") == nil
    end

    test "returns nil for malformed slash date" do
      assert Transformer.parse_datetime("2026/13/01") == nil
      assert Transformer.parse_datetime("2026/04") == nil
    end
  end

  # --- Pokemon TCG API path (variant normalization + holo filtering) ---

  describe "build_price_snapshots_from_ptcg/3 variant normalization" do
    test "normalizes variant names from Pokemon TCG API" do
      tcgplayer = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "reverseHolofoil" => %{"low" => 1.0, "mid" => 2.0, "high" => 3.0, "market" => 2.5},
          "1stEditionNormal" => %{"low" => 5.0, "mid" => 10.0, "high" => 15.0, "market" => 12.0}
        }
      }

      snapshots = Transformer.build_price_snapshots_from_ptcg("test-001", tcgplayer, nil)

      variants = Enum.map(snapshots, & &1.variant)
      assert "reverse-holofoil" in variants
      assert "1st-edition-normal" in variants
      refute "reverseHolofoil" in variants
      refute "1stEditionNormal" in variants
    end
  end

  describe "build_price_snapshots_from_ptcg/3 cardmarket holo filtering" do
    test "rejects holo row when all reverseHolo values are zero" do
      cardmarket = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "lowPrice" => 1.0,
          "averageSellPrice" => 2.0,
          "trendPrice" => 1.5,
          "reverseHoloAvg1" => 0,
          "reverseHoloAvg7" => 0,
          "reverseHoloAvg30" => 0,
          "reverseHoloLow" => 0,
          "reverseHoloTrend" => 0,
          "reverseHoloSell" => 0
        }
      }

      snapshots = Transformer.build_price_snapshots_from_ptcg("test-001", nil, cardmarket)

      variants = Enum.map(snapshots, & &1.variant)
      assert "normal" in variants
      refute "holo" in variants
    end
  end
end
