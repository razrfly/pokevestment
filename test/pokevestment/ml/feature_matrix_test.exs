defmodule Pokevestment.ML.FeatureMatrixTest do
  use Pokevestment.DataCase

  alias Pokevestment.Repo
  alias Pokevestment.Cards.{Series, Set, Card, CardType, CardDexId}
  alias Pokevestment.Pokemon.Species
  alias Pokevestment.Pricing.SoldPrice
  alias Pokevestment.Tournaments.{Tournament, TournamentStanding, TournamentDeckCard}
  alias Pokevestment.ML.{FeatureMatrix, Preprocessing}

  @now DateTime.utc_now() |> DateTime.truncate(:second)

  setup do
    # Series
    Repo.insert!(%Series{id: "sv", name: "Scarlet & Violet"})

    # Set
    Repo.insert!(%Set{
      id: "sv06",
      name: "Twilight Masquerade",
      series_id: "sv",
      release_date: ~D[2024-05-24],
      card_count_official: 167,
      card_count_total: 210,
      era: "sv",
      secret_rare_count: 43,
      secret_rare_ratio: Decimal.new("0.257")
    })

    # Cards: 1 Pokemon, 1 Trainer, 1 Energy
    pokemon_card =
      Repo.insert!(%Card{
        id: "sv06-040",
        name: "Charizard ex",
        local_id: "040",
        set_id: "sv06",
        category: "Pokemon",
        rarity: "Double rare",
        hp: 330,
        stage: "Stage 2",
        illustrator: "PLANETA Mochizuki",
        evolves_from: "Charmeleon",
        retreat_cost: 2,
        energy_type: "Fire",
        attack_count: 2,
        total_attack_damage: 330,
        max_attack_damage: 180,
        has_ability: true,
        ability_count: 1,
        weakness_count: 1,
        resistance_count: 0,
        energy_cost_total: 5,
        art_type: "ultra",
        is_full_art: true,
        is_alternate_art: true,
        is_secret_rare: false,
        language_count: 6,
        legal_standard: true,
        legal_expanded: true
      })

    trainer_card =
      Repo.insert!(%Card{
        id: "sv06-155",
        name: "Boss's Orders",
        local_id: "155",
        set_id: "sv06",
        category: "Trainer",
        rarity: "Uncommon",
        illustrator: "Yusuke Ohmura",
        attack_count: 0,
        total_attack_damage: 0,
        max_attack_damage: 0,
        has_ability: false,
        ability_count: 0,
        weakness_count: 0,
        resistance_count: 0,
        energy_cost_total: 0,
        art_type: "standard",
        language_count: 6,
        legal_standard: true,
        legal_expanded: true
      })

    energy_card =
      Repo.insert!(%Card{
        id: "sv06-198",
        name: "Fire Energy",
        local_id: "198",
        set_id: "sv06",
        category: "Energy",
        rarity: "None",
        illustrator: "N/A",
        attack_count: 0,
        total_attack_damage: 0,
        max_attack_damage: 0,
        has_ability: false,
        ability_count: 0,
        weakness_count: 0,
        resistance_count: 0,
        energy_cost_total: 0,
        art_type: "standard",
        language_count: 6,
        legal_standard: true,
        legal_expanded: true
      })

    # Species for the Pokemon card
    Repo.insert!(%Species{
      id: 6,
      name: "charizard",
      generation: 1,
      capture_rate: 45,
      base_happiness: 70,
      is_legendary: false,
      is_mythical: false,
      is_baby: false,
      growth_rate: "medium-slow"
    })

    Repo.insert!(%CardDexId{card_id: "sv06-040", dex_id: 6})

    # Card types for the Pokemon card
    Repo.insert!(%CardType{card_id: "sv06-040", type_name: "Fire"})
    Repo.insert!(%CardType{card_id: "sv06-040", type_name: "Dragon"})

    # Sold prices
    today = Date.utc_today()

    # TCGPlayer sold prices (should be preferred)
    for {card_id, market} <- [{"sv06-040", 90.0}, {"sv06-155", 5.00}, {"sv06-198", 0.20}] do
      Repo.insert!(%SoldPrice{
        card_id: card_id,
        marketplace: "tcgplayer",
        api_source: "pokemontcg.io",
        variant: "holofoil",
        currency_original: "USD",
        snapshot_date: today,
        price: Decimal.from_float(market),
        price_usd: Decimal.from_float(market)
      })
    end

    # CardMarket sold prices (fallback)
    for {card_id, avg} <- [{"sv06-040", 45.0}, {"sv06-155", 2.50}, {"sv06-198", 0.10}] do
      # Simulate EUR->USD conversion (rate ~1.08)
      usd = avg * 1.08
      Repo.insert!(%SoldPrice{
        card_id: card_id,
        marketplace: "cardmarket",
        api_source: "tcgdex",
        variant: "normal",
        currency_original: "EUR",
        snapshot_date: today,
        price: Decimal.from_float(avg),
        price_usd: Decimal.from_float(usd),
        price_avg_1d: Decimal.from_float(avg * 1.02),
        price_avg_7d: Decimal.from_float(avg * 0.95),
        price_avg_30d: Decimal.from_float(avg * 0.90),
        exchange_rate: Decimal.from_float(1.08),
        exchange_rate_date: today
      })
    end

    # Tournament with standing + deck cards
    tournament =
      Repo.insert!(%Tournament{
        external_id: "test-001",
        name: "Test Regional",
        format: "STANDARD",
        tournament_date: @now,
        player_count: 64
      })

    standing =
      Repo.insert!(%TournamentStanding{
        tournament_id: tournament.id,
        player_name: "Test Player",
        placing: 3,
        wins: 6,
        losses: 2,
        ties: 0,
        deck_archetype_id: "charizard-ex"
      })

    Repo.insert!(%TournamentDeckCard{
      tournament_standing_id: standing.id,
      card_id: "sv06-040",
      card_category: "Pokemon",
      card_name: "Charizard ex",
      set_code: "TWM",
      card_number: "40",
      count: 2
    })

    Repo.insert!(%TournamentDeckCard{
      tournament_standing_id: standing.id,
      card_id: "sv06-155",
      card_category: "Trainer",
      card_name: "Boss's Orders",
      set_code: "TWM",
      card_number: "155",
      count: 2
    })

    %{
      pokemon_card: pokemon_card,
      trainer_card: trainer_card,
      energy_card: energy_card
    }
  end

  describe "FeatureMatrix.assemble/0" do
    test "returns {:ok, df} with correct row count" do
      {:ok, df} = FeatureMatrix.assemble()
      assert Explorer.DataFrame.n_rows(df) == 3
    end

    test "contains expected columns" do
      {:ok, df} = FeatureMatrix.assemble()
      names = Explorer.DataFrame.names(df)

      # Card attributes
      assert "card_id" in names
      assert "category" in names
      assert "hp" in names
      assert "attack_count" in names

      # Species features
      assert "species_generation" in names
      assert "is_legendary" in names

      # Tournament features
      assert "tournament_appearances" in names
      assert "meta_share_total" in names

      # Price features
      assert "log_price" in names
      assert "price_momentum_7d" in names

      # Derived features
      assert "days_since_release" in names
      assert "has_evolution" in names
      assert "set_age_bucket" in names

      # Illustrator features
      assert "illustrator_frequency" in names
    end

    test "Pokemon card has species features populated" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      gen = pokemon_row |> Explorer.DataFrame.pull("species_generation") |> Explorer.Series.to_list()
      assert gen == [1]

      dex_count = pokemon_row |> Explorer.DataFrame.pull("dex_id_count") |> Explorer.Series.to_list()
      assert dex_count == [1]
    end

    test "Trainer card has nil species features" do
      {:ok, df} = FeatureMatrix.assemble()

      trainer_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-155")
        end)

      gen = trainer_row |> Explorer.DataFrame.pull("species_generation") |> Explorer.Series.to_list()
      assert gen == [nil]
    end

    test "Pokemon card has tournament features > 0" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      appearances =
        pokemon_row
        |> Explorer.DataFrame.pull("tournament_appearances")
        |> Explorer.Series.to_list()

      assert hd(appearances) > 0
    end

    test "Energy card has zero tournament features" do
      {:ok, df} = FeatureMatrix.assemble()

      energy_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-198")
        end)

      appearances =
        energy_row
        |> Explorer.DataFrame.pull("tournament_appearances")
        |> Explorer.Series.to_list()

      assert hd(appearances) == 0
    end

    test "all cards have log_price set" do
      {:ok, df} = FeatureMatrix.assemble()

      log_prices =
        df
        |> Explorer.DataFrame.pull("log_price")
        |> Explorer.Series.to_list()

      assert Enum.all?(log_prices, &(not is_nil(&1)))
      # log_price can be negative for cards < $1 (e.g., log(0.10) ≈ -2.3)
      assert Enum.all?(log_prices, &is_float/1)
    end

    test "TCGPlayer price is preferred over CardMarket" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      source =
        pokemon_row
        |> Explorer.DataFrame.pull("price_source")
        |> Explorer.Series.to_list()

      assert hd(source) == "tcgplayer"

      currency =
        pokemon_row
        |> Explorer.DataFrame.pull("price_currency")
        |> Explorer.Series.to_list()

      assert hd(currency) == "USD"

      # canonical_price should be the TCGPlayer market price (~90.0), not CardMarket avg (~45.0)
      canonical =
        pokemon_row
        |> Explorer.DataFrame.pull("canonical_price")
        |> Explorer.Series.to_list()

      assert hd(canonical) > 80.0
    end

    test "price momentum uses Cardmarket rolling averages even when canonical price is from TCGPlayer" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      # Canonical price should come from TCGPlayer
      source =
        pokemon_row
        |> Explorer.DataFrame.pull("price_source")
        |> Explorer.Series.to_list()

      assert hd(source) == "tcgplayer"

      # Rolling averages come from Cardmarket via separate CTE, so momentum is computed
      # even when canonical_price is from TCGPlayer
      momentum =
        pokemon_row
        |> Explorer.DataFrame.pull("price_momentum_7d")
        |> Explorer.Series.to_list()

      assert hd(momentum) != nil
    end

    test "derived features are correct" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      # has_evolution should be true (evolves_from: "Charmeleon")
      has_evo =
        pokemon_row
        |> Explorer.DataFrame.pull("has_evolution")
        |> Explorer.Series.to_list()

      assert hd(has_evo) == true

      # set_age_bucket: released 2024-05-24, should be "established" or "vintage"
      bucket =
        pokemon_row
        |> Explorer.DataFrame.pull("set_age_bucket")
        |> Explorer.Series.to_list()

      assert hd(bucket) in ["established", "vintage"]

      # days_since_release should be positive
      days =
        pokemon_row
        |> Explorer.DataFrame.pull("days_since_release")
        |> Explorer.Series.to_list()

      assert hd(days) > 0
    end

    test "type_count is correct for Pokemon card" do
      {:ok, df} = FeatureMatrix.assemble()

      pokemon_row =
        df
        |> Explorer.DataFrame.filter_with(fn ldf ->
          Explorer.Series.equal(ldf["card_id"], "sv06-040")
        end)

      type_count =
        pokemon_row
        |> Explorer.DataFrame.pull("type_count")
        |> Explorer.Series.to_list()

      assert hd(type_count) == 2
    end
  end

  describe "Preprocessing.prepare_for_training/1" do
    test "filters to cards with prices and separates target" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, train_t, val_f, val_t, meta} = Preprocessing.prepare_for_training(df)

      # All 3 cards have prices, so total should be 3
      assert meta.total_rows == 3
      assert meta.train_rows + meta.val_rows == 3

      # Target should not be in features
      refute "log_price" in Explorer.DataFrame.names(train_f)
      refute "log_price" in Explorer.DataFrame.names(val_f)

      # card_id should not be in features
      refute "card_id" in Explorer.DataFrame.names(train_f)

      # Target series should have values
      assert Explorer.Series.size(train_t) == meta.train_rows
      assert Explorer.Series.size(val_t) == meta.val_rows
    end

    test "categorical columns are encoded as integers" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, _train_t, _val_f, _val_t, meta} = Preprocessing.prepare_for_training(df)

      # Check that encodings map was created
      assert is_map(meta.encodings)
      assert Map.has_key?(meta.encodings, "category")

      # Category column should now be integers
      dtype = train_f |> Explorer.DataFrame.pull("category") |> Explorer.Series.dtype()
      assert match?({:s, _}, dtype) or match?({:u, _}, dtype) or dtype == :integer
    end

    test "encodings contain expected values" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, _train_f, _train_t, _val_f, _val_t, meta} = Preprocessing.prepare_for_training(df)

      category_enc = meta.encodings["category"]
      assert is_map(category_enc)
      assert Map.has_key?(category_enc, "Pokemon")
      assert Map.has_key?(category_enc, "Trainer")
      assert Map.has_key?(category_enc, "Energy")
    end
  end

  describe "Preprocessing.umbrella_map/0" do
    test "covers all major feature categories" do
      umbrella = Preprocessing.umbrella_map()

      categories = umbrella |> Map.values() |> Enum.uniq() |> Enum.sort()

      assert "card_attributes" in categories
      assert "rarity_collectibility" in categories
      assert "tournament_meta" in categories
      assert "price_momentum" in categories
      assert "supply_proxy" in categories
      assert "species" in categories
      assert "illustrator" in categories
    end
  end
end
