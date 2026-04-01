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

  describe "Pipeline.run/1" do
    test "runs full pipeline and persists predictions" do
      {:ok, summary} = Pipeline.run(
        version: "v1.0.0-test",
        num_boost_rounds: 10,
        early_stopping_rounds: 5,
        verbose_eval: false
      )

      assert summary.model_version == "v1.0.0-test"
      assert summary.predictions_count == 3
      assert is_map(summary.metrics)
      assert summary.metrics.rmse >= 0
      assert summary.predictions_upserted == 3
      assert summary.snapshots_inserted == 3
      assert summary.elapsed_ms > 0

      # Model file should exist
      assert File.exists?("priv/models/xgboost_v1.0.0-test.json") || File.exists?("priv/models/xgboost_v1.0.0-test")

      # CardPrediction rows in DB
      predictions = Repo.all(CardPrediction)
      assert length(predictions) == 3

      # ModelEvaluation row in DB
      evaluations = Repo.all(ModelEvaluation)
      assert length(evaluations) == 1
      eval = hd(evaluations)
      assert eval.model_version == "v1.0.0-test"
      assert eval.train_rows > 0
      assert eval.val_rows > 0

      # Cleanup model file
      File.rm("priv/models/xgboost_v1.0.0-test.json")
      File.rm("priv/models/xgboost_v1.0.0-test")
    end
  end
end
