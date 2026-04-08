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

  # --- build_prices/3 TCGdex path (variant normalization + sold/listing separation) ---

  describe "build_prices/3 TCGdex TCGPlayer path" do
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

      {sold, listing} = Transformer.build_prices("test-001", pricing, "tcgdex")

      sold_variants = Enum.map(sold, & &1.variant)
      assert "reverse-holofoil" in sold_variants
      assert "1st-edition-holofoil" in sold_variants
      refute "reverseHolofoil" in sold_variants
      refute "1stEditionHolofoil" in sold_variants

      listing_variants = Enum.map(listing, & &1.variant)
      assert "reverse-holofoil" in listing_variants
      assert "1st-edition-holofoil" in listing_variants
    end

    test "separates market price into sold and low/mid/high into listing" do
      pricing = %{
        "tcgplayer" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "USD",
          "normal" => %{
            "lowPrice" => 1.0,
            "midPrice" => 2.0,
            "highPrice" => 3.0,
            "marketPrice" => 2.5
          }
        }
      }

      {sold, listing} = Transformer.build_prices("test-001", pricing, "tcgdex")

      assert length(sold) == 1
      assert hd(sold).price == Decimal.from_float(2.5)
      assert hd(sold).marketplace == "tcgplayer"

      assert length(listing) == 1
      assert hd(listing).price_low == Decimal.from_float(1.0)
      assert hd(listing).price_mid == Decimal.from_float(2.0)
      assert hd(listing).price_high == Decimal.from_float(3.0)
    end
  end

  describe "build_prices/3 TCGdex Cardmarket path" do
    test "separates avg into sold and low into listing" do
      pricing = %{
        "cardmarket" => %{
          "updated" => "2026-04-01T00:00:00Z",
          "unit" => "EUR",
          "low" => 1.0,
          "avg" => 2.0,
          "trend" => 1.5,
          "avg1" => 2.1,
          "avg7" => 1.9,
          "avg30" => 1.8
        }
      }

      {sold, listing} = Transformer.build_prices("test-001", pricing, "tcgdex")

      assert length(sold) == 1
      s = hd(sold)
      assert s.price == Decimal.from_float(2.0)
      assert s.price_avg_1d == Decimal.from_float(2.1)
      assert s.price_avg_7d == Decimal.from_float(1.9)
      assert s.price_avg_30d == Decimal.from_float(1.8)
      assert s.marketplace == "cardmarket"
      assert s.currency_original == "EUR"

      assert length(listing) == 1
      l = hd(listing)
      assert l.price_low == Decimal.from_float(1.0)
      assert l.metadata["trend_price"] != nil
    end

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

      {sold, listing} = Transformer.build_prices("test-001", pricing, "tcgdex")
      sold_variants = Enum.map(sold, & &1.variant)
      listing_variants = Enum.map(listing, & &1.variant)
      assert "normal" in sold_variants
      refute "holo" in sold_variants
      refute "holo" in listing_variants
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

      {sold, listing} = Transformer.build_prices("test-001", pricing, "tcgdex")
      sold_variants = Enum.map(sold, & &1.variant)
      listing_variants = Enum.map(listing, & &1.variant)
      assert "normal" in sold_variants
      refute "holo" in sold_variants
      refute "holo" in listing_variants
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

      {sold, _listing} = Transformer.build_prices("test-001", pricing, "tcgdex")
      sold_variants = Enum.map(sold, & &1.variant)
      assert "normal" in sold_variants
      assert "holo" in sold_variants
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

  # --- Pokemon TCG API path (build_prices_from_ptcg/3) ---

  describe "build_prices_from_ptcg/3 TCGPlayer variant normalization" do
    test "normalizes variant names from Pokemon TCG API" do
      tcgplayer = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "reverseHolofoil" => %{"low" => 1.0, "mid" => 2.0, "high" => 3.0, "market" => 2.5},
          "1stEditionNormal" => %{"low" => 5.0, "mid" => 10.0, "high" => 15.0, "market" => 12.0}
        }
      }

      {sold, listing} = Transformer.build_prices_from_ptcg("test-001", tcgplayer, nil)

      sold_variants = Enum.map(sold, & &1.variant)
      assert "reverse-holofoil" in sold_variants
      assert "1st-edition-normal" in sold_variants
      refute "reverseHolofoil" in sold_variants
      refute "1stEditionNormal" in sold_variants

      listing_variants = Enum.map(listing, & &1.variant)
      assert "reverse-holofoil" in listing_variants
      assert "1st-edition-normal" in listing_variants
    end

    test "separates market into sold and low/mid/high into listing" do
      tcgplayer = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "normal" => %{"low" => 1.0, "mid" => 2.0, "high" => 3.0, "market" => 2.5}
        }
      }

      {sold, listing} = Transformer.build_prices_from_ptcg("test-001", tcgplayer, nil)

      assert length(sold) == 1
      assert hd(sold).price == Decimal.from_float(2.5)
      assert hd(sold).marketplace == "tcgplayer"
      assert hd(sold).api_source == "pokemontcg.io"

      assert length(listing) == 1
      assert hd(listing).price_low == Decimal.from_float(1.0)
    end
  end

  describe "build_prices_from_ptcg/3 Cardmarket path" do
    test "separates averageSellPrice into sold and lowPrice into listing" do
      cardmarket = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "averageSellPrice" => 2.0,
          "lowPrice" => 1.0,
          "trendPrice" => 1.5,
          "avg1" => 2.1,
          "avg7" => 1.9,
          "avg30" => 1.8
        }
      }

      {sold, listing} = Transformer.build_prices_from_ptcg("test-001", nil, cardmarket)

      assert length(sold) == 1
      s = hd(sold)
      assert s.price == Decimal.from_float(2.0)
      assert s.marketplace == "cardmarket"
      assert s.currency_original == "EUR"
      assert s.price_avg_1d == Decimal.from_float(2.1)

      assert length(listing) == 1
      l = hd(listing)
      assert l.price_low == Decimal.from_float(1.0)
    end

    test "rejects reverse-holo row when all reverseHolo values are zero" do
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

      {sold, listing} = Transformer.build_prices_from_ptcg("test-001", nil, cardmarket)

      sold_variants = Enum.map(sold, & &1.variant)
      listing_variants = Enum.map(listing, & &1.variant)
      assert "normal" in sold_variants
      refute "reverse-holofoil" in sold_variants
      refute "reverse-holofoil" in listing_variants
    end

    test "includes reverse-holo when at least one reverseHolo value is positive" do
      cardmarket = %{
        "updatedAt" => "2026/04/06",
        "prices" => %{
          "lowPrice" => 1.0,
          "averageSellPrice" => 2.0,
          "trendPrice" => 1.5,
          "reverseHoloSell" => 5.0,
          "reverseHoloAvg1" => nil,
          "reverseHoloAvg7" => nil,
          "reverseHoloAvg30" => nil,
          "reverseHoloLow" => nil,
          "reverseHoloTrend" => nil
        }
      }

      {sold, _listing} = Transformer.build_prices_from_ptcg("test-001", nil, cardmarket)

      sold_variants = Enum.map(sold, & &1.variant)
      assert "normal" in sold_variants
      assert "reverse-holofoil" in sold_variants
    end
  end

  describe "build_prices_from_ptcg/3 returns empty for nil inputs" do
    test "returns empty tuples when both sources are nil" do
      assert {[], []} = Transformer.build_prices_from_ptcg("test-001", nil, nil)
    end
  end
end
