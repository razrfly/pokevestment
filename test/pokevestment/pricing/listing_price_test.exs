defmodule Pokevestment.Pricing.ListingPriceTest do
  use Pokevestment.DataCase

  alias Pokevestment.Pricing.ListingPrice

  @valid_attrs %{
    card_id: "sv06-040",
    marketplace: "tcgplayer",
    api_source: "pokemontcg.io",
    variant: "holofoil",
    snapshot_date: ~D[2026-04-07],
    currency_original: "USD",
    price_low: Decimal.new("76.50"),
    price_mid: Decimal.new("85.50"),
    price_high: Decimal.new("108.00")
  }

  setup do
    Pokevestment.Repo.insert!(%Pokevestment.Cards.Series{id: "sv", name: "Scarlet & Violet"})

    Pokevestment.Repo.insert!(%Pokevestment.Cards.Set{
      id: "sv06",
      name: "Twilight Masquerade",
      series_id: "sv",
      release_date: ~D[2024-05-24],
      card_count_official: 167,
      card_count_total: 210,
      era: "sv"
    })

    Pokevestment.Repo.insert!(%Pokevestment.Cards.Card{
      id: "sv06-040",
      name: "Charizard ex",
      local_id: "040",
      set_id: "sv06",
      category: "Pokemon"
    })

    :ok
  end

  describe "changeset/2" do
    test "valid attrs produce a valid changeset" do
      changeset = ListingPrice.changeset(%ListingPrice{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires all required fields" do
      changeset = ListingPrice.changeset(%ListingPrice{}, %{})
      refute changeset.valid?

      errors = errors_on(changeset)
      assert errors[:card_id]
      assert errors[:marketplace]
      assert errors[:api_source]
      assert errors[:variant]
      assert errors[:snapshot_date]
      assert errors[:currency_original]
    end

    test "validates at least one listing price field is positive" do
      attrs = Map.drop(@valid_attrs, [:price_low, :price_mid, :price_high])
      changeset = ListingPrice.changeset(%ListingPrice{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:price_low]
    end

    test "accepts price_mid as the sole positive price" do
      attrs =
        @valid_attrs
        |> Map.drop([:price_low, :price_high])
        |> Map.put(:price_mid, Decimal.new("85.50"))

      changeset = ListingPrice.changeset(%ListingPrice{}, attrs)
      assert changeset.valid?
    end

    test "validates marketplace max length" do
      attrs = Map.put(@valid_attrs, :marketplace, String.duplicate("x", 21))
      changeset = ListingPrice.changeset(%ListingPrice{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:marketplace]
    end

    test "validates currency_original max length" do
      attrs = Map.put(@valid_attrs, :currency_original, "EURX")
      changeset = ListingPrice.changeset(%ListingPrice{}, attrs)
      refute changeset.valid?
      assert errors_on(changeset)[:currency_original]
    end

    test "inserts and enforces unique constraint" do
      {:ok, _} =
        %ListingPrice{}
        |> ListingPrice.changeset(@valid_attrs)
        |> Pokevestment.Repo.insert()

      {:error, changeset} =
        %ListingPrice{}
        |> ListingPrice.changeset(@valid_attrs)
        |> Pokevestment.Repo.insert()

      assert errors_on(changeset)[:card_id]
    end
  end
end
