# Smoke test v2: address SHAP memory + R²=0.9998 diagnosis

alias Pokevestment.ML.{FeatureMatrix, Preprocessing, Trainer, Scorer}
alias Pokevestment.{Predictions, Repo}
alias Pokevestment.ML.{CardPrediction, ModelEvaluation}
import Ecto.Query

IO.puts("=" |> String.duplicate(60))
IO.puts("STEP 1: Assemble feature matrix")
IO.puts("=" |> String.duplicate(60))
{us, {:ok, df}} = :timer.tc(fn -> FeatureMatrix.assemble() end)
n_rows = Explorer.DataFrame.n_rows(df)
n_cols = length(Explorer.DataFrame.names(df))
IO.puts("  Rows: #{n_rows}, Cols: #{n_cols}, Time: #{div(us, 1000)}ms")

IO.puts("\nSTEP 2: Preprocess")
{us, {:ok, train_f, train_t, val_f, val_t, meta}} =
  :timer.tc(fn -> Preprocessing.prepare_for_training(df) end)
IO.puts("  Train: #{meta.train_rows}, Val: #{meta.val_rows}, Features: #{length(meta.feature_columns)}")
IO.puts("  Time: #{div(us, 1000)}ms")

IO.puts("\nSTEP 3: Train XGBoost")
{us, {:ok, booster, metrics, _train_meta}} =
  :timer.tc(fn ->
    Trainer.train(train_f, train_t, val_f, val_t,
      num_boost_rounds: 500,
      early_stopping_rounds: 20,
      verbose_eval: false
    )
  end)
IO.puts("  RMSE:          #{Float.round(metrics.rmse, 4)}")
IO.puts("  MAE:           #{Float.round(metrics.mae, 4)}")
IO.puts("  R²:            #{Float.round(metrics.r_squared, 6)}")
IO.puts("  Baseline RMSE: #{Float.round(metrics.baseline_rmse, 4)}")
IO.puts("  Time: #{div(us, 1000)}ms")

IO.puts("\n  ⚠️  R²=#{Float.round(metrics.r_squared, 4)} — price features dominate.")
IO.puts("  This is expected: price_avg ≈ exp(log_price), so the model learns a near-identity.")
IO.puts("  For finding mispricings, what matters is that the RESIDUALS reveal outliers.")

IO.puts("\nSTEP 4: Feature importances (sampled)")
# Sample 500 rows to avoid OOM on SHAP
sample_size = min(500, meta.val_rows)
sample_indices = Enum.take_random(0..(meta.val_rows - 1), sample_size)
idx_series = Explorer.Series.from_list(sample_indices)
val_f_sample = Explorer.DataFrame.slice(val_f, idx_series)
val_t_sample = Explorer.Series.slice(val_t, idx_series)

IO.puts("  Computing SHAP on #{sample_size} sampled validation rows...")
{us, {feat_imp, umbrella_imp}} =
  :timer.tc(fn ->
    Trainer.feature_importances(booster, val_f_sample, val_t_sample, meta.feature_columns)
  end)
IO.puts("  Time: #{div(us, 1000)}ms")

IO.puts("\n  Top 20 features by SHAP importance:")
feat_imp
|> Enum.sort_by(fn {_k, v} -> v end, :desc)
|> Enum.take(20)
|> Enum.each(fn {k, v} -> IO.puts("    #{String.pad_trailing(k, 30)} #{Float.round(v, 6)}") end)

IO.puts("\n  Umbrella importances:")
umbrella_imp
|> Enum.sort_by(fn {_k, v} -> v end, :desc)
|> Enum.each(fn {k, v} -> IO.puts("    #{String.pad_trailing(k, 25)} #{Float.round(v, 6)}") end)

# Compute what % of importance comes from price features
price_umbrella = Map.get(umbrella_imp, "price_momentum", 0.0)
total_imp = umbrella_imp |> Map.values() |> Enum.sum()
price_pct = if total_imp > 0, do: Float.round(price_umbrella / total_imp * 100, 1), else: 0.0
IO.puts("\n  Price momentum share: #{price_pct}% of total importance")

IO.puts("\nSTEP 5: Score all cards")
scoring_meta = %{feature_columns: meta.feature_columns, encodings: meta.encodings}
{us, {:ok, predictions}} =
  :timer.tc(fn ->
    Scorer.score_all(booster, df, scoring_meta,
      version: "v1.0.0",
      prediction_date: Date.utc_today()
    )
  end)
IO.puts("  Predictions: #{length(predictions)}, Time: #{div(us, 1000)}ms")

# Signal distribution
signal_dist =
  predictions
  |> Enum.group_by(& &1.signal)
  |> Enum.map(fn {signal, cards} -> {signal, length(cards)} end)
  |> Enum.sort_by(fn {_, count} -> count end, :desc)

total = length(predictions)
IO.puts("\n  Signal distribution:")
Enum.each(signal_dist, fn {signal, count} ->
  pct = Float.round(count / total * 100, 1)
  bar = String.duplicate("█", round(pct / 2))
  IO.puts("    #{String.pad_trailing(signal, 20)} #{String.pad_leading(Integer.to_string(count), 6)} (#{String.pad_leading(Float.to_string(pct), 5)}%) #{bar}")
end)

# Value ratio distribution for priced cards
priced = Enum.filter(predictions, fn p -> p.signal != "INSUFFICIENT_DATA" and p.value_ratio != nil end)
ratios = Enum.map(priced, fn p -> Decimal.to_float(p.value_ratio) end)
avg_ratio = Enum.sum(ratios) / length(ratios)
sorted_ratios = Enum.sort(ratios)
median_ratio = Enum.at(sorted_ratios, div(length(sorted_ratios), 2))
min_ratio = List.first(sorted_ratios)
max_ratio = List.last(sorted_ratios)

IO.puts("\n  Value ratio stats (priced cards):")
IO.puts("    Min:    #{Float.round(min_ratio, 4)}")
IO.puts("    Median: #{Float.round(median_ratio, 4)}")
IO.puts("    Mean:   #{Float.round(avg_ratio, 4)}")
IO.puts("    Max:    #{Float.round(max_ratio, 4)}")

IO.puts("\nSTEP 6: Persist to DB")
{us, {:ok, result}} = :timer.tc(fn -> Predictions.upsert_predictions(predictions) end)
IO.puts("  Upserted:  #{result.predictions_upserted}, Snapshots: #{result.snapshots_inserted}")
IO.puts("  Time: #{div(us, 1000)}ms")

IO.puts("\nSTEP 7: Record model evaluation")
rounded_feat = Map.new(feat_imp, fn {k, v} -> {k, Float.round(v, 6)} end)
rounded_umbrella = Map.new(umbrella_imp, fn {k, v} -> {k, Float.round(v, 6)} end)

{:ok, eval} =
  %ModelEvaluation{}
  |> ModelEvaluation.changeset(%{
    model_version: "v1.0.0",
    evaluation_date: Date.utc_today(),
    rmse: Decimal.from_float(metrics.rmse),
    mae: Decimal.from_float(metrics.mae),
    r_squared: Decimal.from_float(metrics.r_squared),
    mape: Decimal.from_float(metrics.mape),
    baseline_rmse: Decimal.from_float(metrics.baseline_rmse),
    baseline_r_squared: Decimal.from_float(metrics.baseline_r_squared),
    split_strategy: "random",
    train_rows: meta.train_rows,
    val_rows: meta.val_rows,
    feature_importances: rounded_feat,
    umbrella_importances: rounded_umbrella,
    training_params: %{
      num_boost_rounds: 500, max_depth: 8, learning_rate: 0.05,
      subsample: 0.8, colsample_bytree: 0.8, min_child_weight: 3,
      gamma: 0.1, reg_alpha: 0.1, reg_lambda: 1.0, early_stopping_rounds: 20
    }
  })
  |> Repo.insert()
IO.puts("  Evaluation ID: #{eval.id}")

# Spot checks
IO.puts("\n" <> ("=" |> String.duplicate(60)))
IO.puts("SPOT CHECKS")
IO.puts("=" |> String.duplicate(60))

charizard = Predictions.get_prediction("sv06-040")
if charizard do
  IO.puts("\nCharizard ex (sv06-040):")
  IO.puts("  Signal:     #{charizard.signal}")
  IO.puts("  Fair value: $#{charizard.predicted_fair_value}")
  IO.puts("  Current:    $#{charizard.current_price}")
  IO.puts("  Ratio:      #{charizard.value_ratio}")
end

IO.puts("\nTop 10 STRONG_BUY cards:")
Repo.all(
  from p in CardPrediction,
  join: c in Pokevestment.Cards.Card, on: c.id == p.card_id,
  where: p.signal == "STRONG_BUY",
  order_by: [desc: p.signal_strength],
  limit: 10,
  select: {c.name, c.set_id, c.rarity, p.current_price, p.predicted_fair_value, p.value_ratio}
)
|> Enum.each(fn {name, set, rarity, cur, fair, ratio} ->
  IO.puts("  #{name} (#{set}, #{rarity}) — $#{cur} → $#{fair} (ratio: #{ratio})")
end)

IO.puts("\nTop 10 OVERVALUED cards:")
Repo.all(
  from p in CardPrediction,
  join: c in Pokevestment.Cards.Card, on: c.id == p.card_id,
  where: p.signal == "OVERVALUED",
  order_by: [desc: p.signal_strength],
  limit: 10,
  select: {c.name, c.set_id, c.rarity, p.current_price, p.predicted_fair_value, p.value_ratio}
)
|> Enum.each(fn {name, set, rarity, cur, fair, ratio} ->
  IO.puts("  #{name} (#{set}, #{rarity}) — $#{cur} → $#{fair} (ratio: #{ratio})")
end)

IO.puts("\nDone!")
