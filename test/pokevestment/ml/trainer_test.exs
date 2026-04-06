defmodule Pokevestment.ML.TrainerTest do
  use Pokevestment.DataCase

  alias Pokevestment.Repo
  alias Pokevestment.Cards.{Series, Set, Card, CardType, CardDexId}
  alias Pokevestment.Pokemon.Species
  alias Pokevestment.Pricing.PriceSnapshot
  alias Pokevestment.Tournaments.{Tournament, TournamentStanding, TournamentDeckCard}
  alias Pokevestment.ML.{FeatureMatrix, Preprocessing, Trainer, Scorer, Pipeline}
  alias Pokevestment.ML.{CardPrediction, ModelEvaluation}

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

    # Species
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

    # Card types
    Repo.insert!(%CardType{card_id: "sv06-040", type_name: "Fire"})
    Repo.insert!(%CardType{card_id: "sv06-040", type_name: "Dragon"})

    # Price snapshots
    today = Date.utc_today()

    # TCGPlayer snapshots (should be preferred)
    for {card_id, market} <- [{"sv06-040", 90.0}, {"sv06-155", 5.00}, {"sv06-198", 0.20}] do
      Repo.insert!(%PriceSnapshot{
        card_id: card_id,
        source: "tcgplayer",
        variant: "holofoil",
        currency: "USD",
        snapshot_date: today,
        price_low: Decimal.from_float(market * 0.85),
        price_mid: Decimal.from_float(market * 0.95),
        price_high: Decimal.from_float(market * 1.2),
        price_market: Decimal.from_float(market)
      })
    end

    # CardMarket snapshots (fallback)
    for {card_id, avg} <- [{"sv06-040", 45.0}, {"sv06-155", 2.50}, {"sv06-198", 0.10}] do
      Repo.insert!(%PriceSnapshot{
        card_id: card_id,
        source: "cardmarket",
        variant: "normal",
        currency: "EUR",
        snapshot_date: today,
        price_avg: Decimal.from_float(avg),
        price_low: Decimal.from_float(avg * 0.8),
        price_high: Decimal.from_float(avg * 1.3),
        price_mid: Decimal.from_float(avg),
        price_avg1: Decimal.from_float(avg * 1.02),
        price_avg7: Decimal.from_float(avg * 0.95),
        price_avg30: Decimal.from_float(avg * 0.90)
      })
    end

    # Tournament
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

    :ok
  end

  describe "Trainer.train/5" do
    test "trains a model and returns metrics" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, train_t, val_f, val_t, _meta} = Preprocessing.prepare_for_training(df)

      {:ok, booster, metrics, _train_meta} =
        Trainer.train(train_f, train_t, val_f, val_t,
          num_boost_rounds: 10,
          early_stopping_rounds: 5,
          verbose_eval: false
        )

      assert booster != nil
      assert is_map(metrics)
      assert Map.has_key?(metrics, :rmse)
      assert Map.has_key?(metrics, :mae)
      assert Map.has_key?(metrics, :r_squared)
      assert Map.has_key?(metrics, :mape)
      assert Map.has_key?(metrics, :baseline_rmse)
      assert Map.has_key?(metrics, :baseline_r_squared)

      # All metrics should be numbers
      assert is_number(metrics.rmse)
      assert is_number(metrics.mae)
      assert is_number(metrics.r_squared)
    end
  end

  describe "Trainer.feature_importances/4" do
    test "returns feature and umbrella importance maps" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, train_t, val_f, val_t, meta} = Preprocessing.prepare_for_training(df)

      {:ok, booster, _metrics, _train_meta} =
        Trainer.train(train_f, train_t, val_f, val_t,
          num_boost_rounds: 10,
          early_stopping_rounds: 5,
          verbose_eval: false
        )

      {feat_imp, umbrella_imp} =
        Trainer.feature_importances(booster, val_f, val_t, meta.feature_columns)

      assert is_map(feat_imp)
      assert map_size(feat_imp) > 0

      # All importance values should be non-negative floats
      Enum.each(feat_imp, fn {_name, val} ->
        assert is_float(val)
        assert val >= 0
      end)

      assert is_map(umbrella_imp)
      assert map_size(umbrella_imp) > 0
    end
  end

  describe "Scorer.assign_signal/2" do
    test "STRONG_BUY for ratio >= 1.3" do
      assert Scorer.assign_signal(1.5, true) == "STRONG_BUY"
      assert Scorer.assign_signal(1.3, true) == "STRONG_BUY"
    end

    test "BUY for ratio >= 1.1 and < 1.3" do
      assert Scorer.assign_signal(1.15, true) == "BUY"
      assert Scorer.assign_signal(1.1, true) == "BUY"
    end

    test "HOLD for ratio >= 0.9 and < 1.1" do
      assert Scorer.assign_signal(1.0, true) == "HOLD"
      assert Scorer.assign_signal(0.9, true) == "HOLD"
    end

    test "OVERVALUED for ratio < 0.9" do
      assert Scorer.assign_signal(0.8, true) == "OVERVALUED"
      assert Scorer.assign_signal(0.5, true) == "OVERVALUED"
    end

    test "INSUFFICIENT_DATA when no price" do
      assert Scorer.assign_signal(1.5, false) == "INSUFFICIENT_DATA"
      assert Scorer.assign_signal(nil, false) == "INSUFFICIENT_DATA"
    end
  end

  describe "Scorer.score_all/4" do
    test "scores all cards and returns valid predictions" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, train_t, val_f, val_t, meta} = Preprocessing.prepare_for_training(df)

      {:ok, booster, _metrics, _train_meta} =
        Trainer.train(train_f, train_t, val_f, val_t,
          num_boost_rounds: 10,
          early_stopping_rounds: 5,
          verbose_eval: false
        )

      scoring_meta = %{
        feature_columns: meta.feature_columns,
        encodings: meta.encodings
      }

      {:ok, predictions} = Scorer.score_all(booster, df, scoring_meta)

      # Should have 3 predictions (all cards have prices)
      assert length(predictions) == 3

      valid_signals = ~w(STRONG_BUY BUY HOLD OVERVALUED INSUFFICIENT_DATA)

      Enum.each(predictions, fn pred ->
        assert Map.has_key?(pred, :card_id)
        assert Map.has_key?(pred, :signal)
        assert Map.has_key?(pred, :predicted_fair_value)
        assert Map.has_key?(pred, :value_ratio)
        assert Map.has_key?(pred, :top_positive_drivers)
        assert Map.has_key?(pred, :top_negative_drivers)
        assert Map.has_key?(pred, :umbrella_breakdown)
        assert pred.signal in valid_signals
      end)
    end
  end

  describe "Preprocessing.prepare_for_training/2 temporal split" do
    test "temporal split puts oldest cards in training and newest in validation" do
      {:ok, df} = FeatureMatrix.assemble()
      {:ok, train_f, _train_t, val_f, _val_t, meta} =
        Preprocessing.prepare_for_training(df, split_strategy: :temporal)

      assert meta.split_strategy == "temporal"
      assert meta.train_rows > 0
      assert meta.val_rows > 0

      # Validation rows should have lower days_since_release (newer cards)
      # than training rows on average, if the column survived encoding
      if "days_since_release" in Explorer.DataFrame.names(train_f) do
        train_days = train_f |> Explorer.DataFrame.pull("days_since_release") |> Explorer.Series.to_list()
        val_days = val_f |> Explorer.DataFrame.pull("days_since_release") |> Explorer.Series.to_list()

        train_avg = Enum.sum(Enum.reject(train_days, &is_nil/1)) / max(length(Enum.reject(train_days, &is_nil/1)), 1)
        val_avg = Enum.sum(Enum.reject(val_days, &is_nil/1)) / max(length(Enum.reject(val_days, &is_nil/1)), 1)

        # Training set should have older cards (higher days_since_release)
        assert train_avg >= val_avg
      end
    end

    test "temporal split raises when days_since_release is missing" do
      require Explorer.DataFrame, as: DF

      # Build a minimal DataFrame without days_since_release
      df = DF.new(%{log_price: [1.0, 2.0, 3.0], some_feature: [1, 2, 3]})

      assert_raise ArgumentError, ~r/days_since_release/, fn ->
        Preprocessing.prepare_for_training(df, split_strategy: :temporal)
      end
    end

    test "temporal split raises on invalid val_fraction" do
      {:ok, df} = FeatureMatrix.assemble()

      assert_raise ArgumentError, ~r/val_fraction/, fn ->
        Preprocessing.prepare_for_training(df, split_strategy: :temporal, val_fraction: 0.0)
      end

      assert_raise ArgumentError, ~r/val_fraction/, fn ->
        Preprocessing.prepare_for_training(df, split_strategy: :temporal, val_fraction: 1.0)
      end
    end
  end

  describe "Pipeline.run/1" do
    test "runs full pipeline and persists predictions" do
      version = "v1.0.0-test-#{System.unique_integer([:positive])}"

      on_exit(fn ->
        File.rm("priv/models/xgboost_#{version}.json")
        File.rm("priv/models/xgboost_#{version}")
      end)

      {:ok, summary} = Pipeline.run(
        version: version,
        num_boost_rounds: 10,
        early_stopping_rounds: 5,
        verbose_eval: false
      )

      assert summary.model_version == version
      assert summary.predictions_count == 3
      assert is_map(summary.metrics)
      assert summary.metrics.rmse >= 0
      assert summary.predictions_upserted == 3
      assert summary.snapshots_inserted == 3
      assert summary.elapsed_ms > 0

      # Model file should exist
      assert File.exists?("priv/models/xgboost_#{version}.json") || File.exists?("priv/models/xgboost_#{version}")

      # CardPrediction rows in DB
      predictions = Repo.all(CardPrediction)
      assert length(predictions) == 3

      # All cards have prices, so none should be INSUFFICIENT_DATA
      assert Enum.all?(predictions, &(&1.signal != "INSUFFICIENT_DATA"))

      # Every prediction should have tcgplayer/USD metadata (TCGPlayer is preferred source)
      Enum.each(predictions, fn pred ->
        assert pred.price_source == "tcgplayer"
        assert pred.price_currency == "USD"
      end)

      # ModelEvaluation row in DB
      evaluations = Repo.all(ModelEvaluation)
      assert length(evaluations) == 1
      eval = hd(evaluations)
      assert eval.model_version == version
      assert eval.train_rows > 0
      assert eval.val_rows > 0
    end
  end
end
