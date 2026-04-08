defmodule Pokevestment.Pricing.ListingIsolationTest do
  @moduledoc """
  Regression test for Issue #86: listing data must NEVER enter the ML pipeline.

  This test inserts a card with ONLY listing prices (no sold prices)
  and verifies that PriceFeatures returns nil canonical_price for it,
  proving listing data cannot contaminate ML training targets.
  """
  use Pokevestment.DataCase

  alias Pokevestment.Repo
  alias Pokevestment.Cards.{Series, Set, Card}
  alias Pokevestment.Pricing.{SoldPrice, ListingPrice}
  alias Pokevestment.ML.PriceFeatures

  setup do
    Repo.insert!(%Series{id: "sv", name: "Scarlet & Violet"})

    Repo.insert!(%Set{
      id: "sv06",
      name: "Twilight Masquerade",
      series_id: "sv",
      release_date: ~D[2024-05-24],
      card_count_official: 167,
      card_count_total: 210,
      era: "sv"
    })

    # Card A: has both sold + listing data
    Repo.insert!(%Card{
      id: "sv06-040",
      name: "Charizard ex",
      local_id: "040",
      set_id: "sv06",
      category: "Pokemon"
    })

    # Card B: has ONLY listing data (no sold prices)
    Repo.insert!(%Card{
      id: "sv06-155",
      name: "Boss's Orders",
      local_id: "155",
      set_id: "sv06",
      category: "Trainer"
    })

    today = Date.utc_today()

    # Card A gets a sold price
    Repo.insert!(%SoldPrice{
      card_id: "sv06-040",
      marketplace: "tcgplayer",
      api_source: "pokemontcg.io",
      variant: "holofoil",
      snapshot_date: today,
      currency_original: "USD",
      price: Decimal.from_float(90.0),
      price_usd: Decimal.from_float(90.0)
    })

    # Card B gets ONLY listing prices — no sold prices at all
    Repo.insert!(%ListingPrice{
      card_id: "sv06-155",
      marketplace: "tcgplayer",
      api_source: "pokemontcg.io",
      variant: "holofoil",
      snapshot_date: today,
      currency_original: "USD",
      price_low: Decimal.from_float(3.0),
      price_mid: Decimal.from_float(5.0),
      price_high: Decimal.from_float(8.0),
      price_low_usd: Decimal.from_float(3.0),
      price_mid_usd: Decimal.from_float(5.0),
      price_high_usd: Decimal.from_float(8.0),
      exchange_rate: Decimal.new(1),
      exchange_rate_date: today
    })

    %{today: today}
  end

  test "card with only listing data does NOT appear in PriceFeatures output" do
    price_map = PriceFeatures.compute_all()

    # Card A (has sold price) should appear
    assert Map.has_key?(price_map, "sv06-040")
    assert price_map["sv06-040"]["canonical_price"] == 90.0

    # Card B (listing only) must NOT appear — this is the critical assertion
    refute Map.has_key?(price_map, "sv06-155"),
           "REGRESSION: Card with only listing data appeared in PriceFeatures! " <>
             "Listing data is leaking into the ML pipeline."
  end

  test "listing_prices table has data but sold_prices excludes listing-only card" do
    # Verify listing data actually exists in the database
    listing_count = Repo.aggregate(ListingPrice, :count)
    assert listing_count == 1

    # Verify sold data exists only for Card A
    sold_count = Repo.aggregate(SoldPrice, :count)
    assert sold_count == 1

    sold_card_ids =
      Repo.all(from sp in SoldPrice, select: sp.card_id)

    assert "sv06-040" in sold_card_ids
    refute "sv06-155" in sold_card_ids
  end

  test "price_usd is used as canonical_price, not raw price" do
    # Insert a EUR sold price for a new card to verify USD normalization
    Repo.insert!(%Card{
      id: "sv06-198",
      name: "Fire Energy",
      local_id: "198",
      set_id: "sv06",
      category: "Energy"
    })

    Repo.insert!(%SoldPrice{
      card_id: "sv06-198",
      marketplace: "cardmarket",
      api_source: "tcgdex",
      variant: "normal",
      snapshot_date: Date.utc_today(),
      currency_original: "EUR",
      price: Decimal.from_float(10.0),
      price_usd: Decimal.from_float(10.80),
      exchange_rate: Decimal.from_float(1.08),
      exchange_rate_date: Date.utc_today()
    })

    price_map = PriceFeatures.compute_all()

    # canonical_price should be the USD-normalized value (10.80), not the EUR value (10.0)
    assert_in_delta price_map["sv06-198"]["canonical_price"], 10.80, 0.01
  end
end
