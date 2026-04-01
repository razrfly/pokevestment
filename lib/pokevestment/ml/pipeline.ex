defmodule Pokevestment.ML.Pipeline do
  @moduledoc """
  Orchestrates the full ML pipeline: assemble features → preprocess → train → score → persist.
  """

  require Logger

  alias Pokevestment.Repo
  alias Pokevestment.ML.{FeatureMatrix, Preprocessing, Trainer, Scorer, ModelEvaluation}
  alias Pokevestment.Predictions

  @models_dir "priv/models"

  @doc """
  Runs the complete ML pipeline.

  ## Options
    * `:version` - model version string (default "v1.0.0")
    * `:val_fraction` - validation split fraction (default 0.2)
    * All EXGBoost hyperparams are passed through to Trainer.train/5
  """
  def run(opts \\ []) do
    version = Keyword.get(opts, :version, "v1.0.0")
    val_fraction = Keyword.get(opts, :val_fraction, 0.2)
    prediction_date = Keyword.get(opts, :prediction_date, Date.utc_today())

    Logger.info("[ML Pipeline] Starting pipeline #{version}")
    pipeline_start = System.monotonic_time(:millisecond)

    with {:ok, df} <- step_assemble(),
         {:ok, train_f, train_t, val_f, val_t, prep_meta} <-
           step_preprocess(df, val_fraction: val_fraction),
         {:ok, booster, metrics, train_meta} <-
           step_train(train_f, train_t, val_f, val_t, opts),
         :ok <- step_save_model(booster, version),
         {feature_importances, umbrella_importances} <-
           step_feature_importances(booster, val_f, val_t, prep_meta.feature_columns),
         {:ok, predictions_list} <-
           step_score(booster, df, prep_meta, train_meta, version, prediction_date),
         {:ok, persist_result} <- step_persist(predictions_list),
         {:ok, evaluation} <-
           step_record_evaluation(
             version,
             prediction_date,
             metrics,
             feature_importances,
             umbrella_importances,
             prep_meta,
             opts
           ) do
      elapsed = System.monotonic_time(:millisecond) - pipeline_start

      summary = %{
        model_version: version,
        predictions_count: length(predictions_list),
        predictions_upserted: persist_result.predictions_upserted,
        snapshots_inserted: persist_result.snapshots_inserted,
        metrics: metrics,
        feature_importances: feature_importances,
        umbrella_importances: umbrella_importances,
        evaluation_id: evaluation.id,
        elapsed_ms: elapsed
      }

      Logger.info("[ML Pipeline] Complete in #{elapsed}ms — #{length(predictions_list)} cards scored")
      {:ok, summary}
    end
  end

  defp step_assemble do
    Logger.info("[ML Pipeline] Step 1: Assembling feature matrix")
    start = System.monotonic_time(:millisecond)
    result = FeatureMatrix.assemble()
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, df} ->
        Logger.info("[ML Pipeline]   Assembled #{Explorer.DataFrame.n_rows(df)} rows in #{elapsed}ms")
        {:ok, df}

      error ->
        error
    end
  end

  defp step_preprocess(df, opts) do
    Logger.info("[ML Pipeline] Step 2: Preprocessing for training")
    start = System.monotonic_time(:millisecond)
    result = Preprocessing.prepare_for_training(df, opts)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, train_f, train_t, val_f, val_t, meta} ->
        Logger.info("[ML Pipeline]   Train: #{meta.train_rows} rows, Val: #{meta.val_rows} rows (#{elapsed}ms)")
        {:ok, train_f, train_t, val_f, val_t, meta}

      error ->
        error
    end
  end

  defp step_train(train_f, train_t, val_f, val_t, opts) do
    Logger.info("[ML Pipeline] Step 3: Training XGBoost model")
    start = System.monotonic_time(:millisecond)
    result = Trainer.train(train_f, train_t, val_f, val_t, opts)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, booster, metrics, meta} ->
        Logger.info("[ML Pipeline]   RMSE=#{Float.round(metrics.rmse, 4)}, R²=#{Float.round(metrics.r_squared, 4)} (#{elapsed}ms)")
        {:ok, booster, metrics, meta}

      error ->
        error
    end
  end

  defp step_save_model(booster, version) do
    Logger.info("[ML Pipeline] Step 4: Saving model")
    File.mkdir_p!(@models_dir)
    # EXGBoost.write_model appends .json automatically
    path = Path.join(@models_dir, "xgboost_#{version}")
    EXGBoost.write_model(booster, path, overwrite: true)
    Logger.info("[ML Pipeline]   Saved to #{path}")
    :ok
  end

  defp step_feature_importances(booster, val_f, val_t, feature_columns) do
    Logger.info("[ML Pipeline] Step 4b: Computing feature importances")
    Trainer.feature_importances(booster, val_f, val_t, feature_columns)
  end

  defp step_score(booster, full_df, prep_meta, _train_meta, version, prediction_date) do
    Logger.info("[ML Pipeline] Step 5: Scoring all cards")
    start = System.monotonic_time(:millisecond)

    scoring_meta = %{
      feature_columns: prep_meta.feature_columns,
      encodings: prep_meta.encodings
    }

    result =
      Scorer.score_all(booster, full_df, scoring_meta,
        version: version,
        prediction_date: prediction_date
      )

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, predictions} ->
        Logger.info("[ML Pipeline]   Scored #{length(predictions)} cards (#{elapsed}ms)")
        {:ok, predictions}

      error ->
        error
    end
  end

  defp step_persist(predictions_list) do
    Logger.info("[ML Pipeline] Step 6: Persisting predictions")
    start = System.monotonic_time(:millisecond)
    result = Predictions.upsert_predictions(predictions_list)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, counts} ->
        Logger.info("[ML Pipeline]   Upserted #{counts.predictions_upserted}, snapshots #{counts.snapshots_inserted} (#{elapsed}ms)")
        {:ok, counts}

      error ->
        error
    end
  end

  defp step_record_evaluation(version, date, metrics, feat_imp, umbrella_imp, prep_meta, opts) do
    Logger.info("[ML Pipeline] Step 7: Recording model evaluation")

    training_params = %{
      num_boost_rounds: opts[:num_boost_rounds] || 500,
      max_depth: opts[:max_depth] || 8,
      learning_rate: opts[:learning_rate] || 0.05,
      subsample: opts[:subsample] || 0.8,
      colsample_bytree: opts[:colsample_bytree] || 0.8,
      min_child_weight: opts[:min_child_weight] || 3,
      gamma: opts[:gamma] || 0.1,
      reg_alpha: opts[:reg_alpha] || 0.1,
      reg_lambda: opts[:reg_lambda] || 1.0,
      early_stopping_rounds: opts[:early_stopping_rounds] || 20,
      val_fraction: opts[:val_fraction] || 0.2
    }

    # Round importance values for JSON storage
    rounded_feat = Map.new(feat_imp, fn {k, v} -> {k, Float.round(v, 6)} end)
    rounded_umbrella = Map.new(umbrella_imp, fn {k, v} -> {k, Float.round(v, 6)} end)

    attrs = %{
      model_version: version,
      evaluation_date: date,
      rmse: safe_metric(metrics.rmse),
      mae: safe_metric(metrics.mae),
      r_squared: safe_metric(metrics.r_squared),
      mape: safe_metric(metrics.mape),
      baseline_rmse: safe_metric(metrics.baseline_rmse),
      baseline_r_squared: safe_metric(metrics.baseline_r_squared),
      split_strategy: "random",
      train_rows: prep_meta.train_rows,
      val_rows: prep_meta.val_rows,
      feature_importances: rounded_feat,
      umbrella_importances: rounded_umbrella,
      training_params: training_params
    }

    %ModelEvaluation{}
    |> ModelEvaluation.changeset(attrs)
    |> Repo.insert()
  end

  # Cap metric values to fit decimal(10,6) columns (max 9999.999999)
  # MAPE can overflow when log_price values are near zero
  @max_metric_value 9999.0
  defp safe_metric(val) when is_float(val) do
    val
    |> min(@max_metric_value)
    |> max(-@max_metric_value)
    |> Decimal.from_float()
  end

  defp safe_metric(val) when is_integer(val), do: Decimal.new(val)
  defp safe_metric(nil), do: nil
end
