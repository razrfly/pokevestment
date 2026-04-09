defmodule Pokevestment.Ingestion.TransformerPptTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Ingestion.Transformer

  describe "normalize_condition/1" do
    test "normalizes Near Mint variants" do
      assert Transformer.normalize_condition("Near Mint Holofoil") == "near-mint"
      assert Transformer.normalize_condition("Near Mint") == "near-mint"
      assert Transformer.normalize_condition("Near Mint Normal") == "near-mint"
    end

    test "normalizes Lightly Played variants" do
      assert Transformer.normalize_condition("Lightly Played Holofoil") == "lightly-played"
      assert Transformer.normalize_condition("Lightly Played") == "lightly-played"
    end

    test "normalizes other conditions" do
      assert Transformer.normalize_condition("Moderately Played Holofoil") == "moderately-played"
      assert Transformer.normalize_condition("Heavily Played") == "heavily-played"
      assert Transformer.normalize_condition("Damaged") == "damaged"
    end

    test "returns aggregate for nil, empty, or unknown" do
      assert Transformer.normalize_condition(nil) == "aggregate"
      assert Transformer.normalize_condition("") == "aggregate"
      assert Transformer.normalize_condition("Unknown Condition") == "aggregate"
    end
  end

  describe "normalize_ppt_variant/1" do
    test "normalizes known variants to kebab-case" do
      assert Transformer.normalize_ppt_variant("Holofoil") == "holofoil"
      assert Transformer.normalize_ppt_variant("Normal") == "normal"
      assert Transformer.normalize_ppt_variant("Reverse Holofoil") == "reverse-holofoil"
    end

    test "defaults nil to normal" do
      assert Transformer.normalize_ppt_variant(nil) == "normal"
    end

    test "lowercases and kebab-cases unknown variants" do
      assert Transformer.normalize_ppt_variant("1st Edition") == "1st-edition"
    end
  end

  describe "build_prices_from_ppt/1" do
    @sample_ppt_card %{
      "externalCatalogId" => "me02.5-284",
      "tcgPlayerId" => "676096",
      "tcgPlayerUrl" => "https://www.tcgplayer.com/product/676096",
      "lastScrapedAt" => "2026-04-08T23:49:24.384Z",
      "dataCompleteness" => "complete",
      "prices" => %{
        "market" => 1133.98,
        "low" => 1127.5,
        "sellers" => 2,
        "listings" => 0,
        "primaryPrinting" => "Holofoil",
        "lastUpdated" => "2026-04-08T23:49:24.384Z",
        "variants" => %{
          "Holofoil" => %{
            "Near Mint Holofoil" => %{"price" => 1152.57, "listings" => nil},
            "Lightly Played Holofoil" => %{"price" => 1022.22, "listings" => nil}
          }
        }
      }
    }

    test "returns {sold, listing} tuple" do
      {sold, listing} = Transformer.build_prices_from_ppt(@sample_ppt_card)
      assert is_list(sold)
      assert is_list(listing)
    end

    test "generates aggregate sold price" do
      {sold, _} = Transformer.build_prices_from_ppt(@sample_ppt_card)

      agg = Enum.find(sold, fn s -> s.condition == "aggregate" end)
      assert agg
      assert agg.card_id == "me02.5-284"
      assert agg.marketplace == "tcgplayer"
      assert agg.api_source == "pokemonpricetracker"
      assert agg.variant == "holofoil"
      assert agg.currency_original == "USD"
      assert Decimal.eq?(agg.price, Decimal.from_float(1133.98))
      assert agg.product_id == 676_096
    end

    test "generates per-condition sold prices" do
      {sold, _} = Transformer.build_prices_from_ppt(@sample_ppt_card)

      nm = Enum.find(sold, fn s -> s.condition == "near-mint" end)
      assert nm
      assert Decimal.eq?(nm.price, Decimal.from_float(1152.57))
      assert nm.variant == "holofoil"

      lp = Enum.find(sold, fn s -> s.condition == "lightly-played" end)
      assert lp
      assert Decimal.eq?(lp.price, Decimal.from_float(1022.22))
    end

    test "generates aggregate listing price" do
      {_, listing} = Transformer.build_prices_from_ppt(@sample_ppt_card)

      agg = Enum.find(listing, fn l -> l.condition == "aggregate" end)
      assert agg
      assert Decimal.eq?(agg.price_low, Decimal.from_float(1127.5))
    end

    test "stores full API response in aggregate row metadata" do
      {sold, _} = Transformer.build_prices_from_ppt(@sample_ppt_card)

      agg = Enum.find(sold, fn s -> s.condition == "aggregate" end)
      assert agg.metadata["ppt_response"]
      assert agg.metadata["marketplace_url"] == "https://www.tcgplayer.com/product/676096"
    end

    test "stores small metadata on condition rows" do
      {sold, _} = Transformer.build_prices_from_ppt(@sample_ppt_card)

      nm = Enum.find(sold, fn s -> s.condition == "near-mint" end)
      assert nm.metadata["marketplace_url"]
      refute nm.metadata["ppt_response"]
    end

    test "returns empty for nil input" do
      assert Transformer.build_prices_from_ppt(nil) == {[], []}
    end

    test "returns empty for card without externalCatalogId" do
      card = Map.delete(@sample_ppt_card, "externalCatalogId")
      assert Transformer.build_prices_from_ppt(card) == {[], []}
    end

    test "handles history data" do
      card =
        Map.put(@sample_ppt_card, "priceHistory", %{
          "variants" => %{
            "Holofoil" => %{
              "Near Mint" => %{
                "history" => [
                  %{"date" => "2026-04-07T00:00:00.000Z", "market" => 1171.89, "volume" => 2},
                  %{"date" => "2026-04-06T00:00:00.000Z", "market" => 1150.0, "volume" => 3}
                ]
              }
            }
          }
        })

      {sold, _} = Transformer.build_prices_from_ppt(card)

      history = Enum.filter(sold, fn s -> s.snapshot_date != Date.utc_today() end)
      assert length(history) >= 2

      april_7 = Enum.find(history, fn s -> s.snapshot_date == ~D[2026-04-07] end)
      assert april_7
      assert april_7.condition == "near-mint"
      assert Decimal.eq?(april_7.price, Decimal.from_float(1171.89))
      assert april_7.metadata["volume"] == 2
    end
  end
end
