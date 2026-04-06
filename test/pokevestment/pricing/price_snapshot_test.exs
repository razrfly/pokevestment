defmodule Pokevestment.Pricing.PriceSnapshotTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Pricing.PriceSnapshot

  @valid_attrs %{
    card_id: "sv06-001",
    source: "tcgplayer",
    variant: "normal",
    snapshot_date: ~D[2026-04-06],
    currency: "USD",
    price_market: Decimal.new("5.00")
  }

  describe "changeset/2 positive price validation" do
    test "valid with at least one positive price" do
      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, @valid_attrs)
      assert changeset.valid?
    end

    test "valid with price_low only" do
      attrs = Map.put(@valid_attrs, :price_low, Decimal.new("1.50")) |> Map.delete(:price_market)
      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)
      assert changeset.valid?
    end

    test "invalid with all nil prices" do
      attrs = Map.delete(@valid_attrs, :price_market)
      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)
      refute changeset.valid?
      assert {"at least one price field must be positive", _} = changeset.errors[:price_low]
    end

    test "invalid with only zero prices" do
      attrs =
        @valid_attrs
        |> Map.put(:price_market, Decimal.new("0"))
        |> Map.put(:price_low, Decimal.new("0"))

      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)
      refute changeset.valid?
    end

    test "valid with mix of nil and positive prices" do
      attrs =
        @valid_attrs
        |> Map.delete(:price_market)
        |> Map.put(:price_avg, Decimal.new("3.50"))

      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)
      assert changeset.valid?
    end
  end
end
