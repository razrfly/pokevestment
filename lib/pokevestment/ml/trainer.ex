defmodule Pokevestment.ML.Trainer do
  @moduledoc """
  Trains an XGBoost regression model on preprocessed feature DataFrames.
  Handles DataFrame→Tensor conversion, training, evaluation metrics, and SHAP-based feature importance.
  """

  require Logger
  require Explorer.DataFrame, as: DF
  alias Explorer.Series
  alias Pokevestment.ML.Preprocessing

  @doc """
  Trains an XGBoost booster on the given train/val DataFrames and target Series.
  Returns `{:ok, booster, metrics, metadata}`.
  """
  def train(train_features_df, train_target_series, val_features_df, val_target_series, opts \\ []) do
    train_x = df_to_tensor(train_features_df)
    train_y = series_to_tensor(train_target_series)
    val_x = df_to_tensor(val_features_df)
    val_y = series_to_tensor(val_target_series)

    booster =
      EXGBoost.train(train_x, train_y,
        num_boost_rounds: opts[:num_boost_rounds] || 500,
        objective: :reg_squarederror,
        evals: [{val_x, val_y, "validation"}],
        early_stopping_rounds: opts[:early_stopping_rounds] || 20,
        verbose_eval: opts[:verbose_eval] || false,
        max_depth: opts[:max_depth] || 8,
        learning_rate: opts[:learning_rate] || 0.05,
        subsample: opts[:subsample] || 0.8,
        colsample_bytree: opts[:colsample_bytree] || 0.8,
        min_child_weight: opts[:min_child_weight] || 3,
        gamma: opts[:gamma] || 0.1,
        reg_alpha: opts[:reg_alpha] || 0.1,
        reg_lambda: opts[:reg_lambda] || 1.0
      )

    metrics = evaluate(booster, val_features_df, val_target_series, %{train_y: train_y})

    metadata = %{
      train_x: train_x,
      train_y: train_y,
      val_x: val_x,
      val_y: val_y,
      feature_columns: DF.names(train_features_df)
    }

    {:ok, booster, metrics, metadata}
  end

  @doc """
  Computes regression metrics for the booster on a given feature DataFrame and target Series.
  Also computes baseline metrics (mean predictor).
  """
  def evaluate(booster, features_df, target_series, extra \\ %{}) do
    x = df_to_tensor(features_df)
    y_true = series_to_tensor(target_series)
    y_pred = EXGBoost.predict(booster, x)

    # Flatten predictions if needed
    y_pred = Nx.flatten(y_pred)
    y_true = Nx.flatten(y_true)

    mse = Scholar.Metrics.Regression.mean_square_error(y_true, y_pred)
    rmse = mse |> Nx.sqrt() |> Nx.to_number()
    mae = Scholar.Metrics.Regression.mean_absolute_error(y_true, y_pred) |> Nx.to_number()
    r_squared = Scholar.Metrics.Regression.r2_score(y_true, y_pred) |> Nx.to_number()

    mape =
      Scholar.Metrics.Regression.mean_absolute_percentage_error(y_true, y_pred) |> Nx.to_number()

    # Baseline: mean predictor
    train_y = Map.get(extra, :train_y, y_true)
    mean_val = Nx.mean(train_y) |> Nx.to_number()
    baseline_pred = Nx.broadcast(Nx.tensor(mean_val, type: Nx.type(y_true)), Nx.shape(y_true))

    baseline_mse = Scholar.Metrics.Regression.mean_square_error(y_true, baseline_pred)
    baseline_rmse = baseline_mse |> Nx.sqrt() |> Nx.to_number()

    baseline_r_squared =
      Scholar.Metrics.Regression.r2_score(y_true, baseline_pred) |> Nx.to_number()

    %{
      rmse: rmse,
      mae: mae,
      r_squared: r_squared,
      mape: mape,
      baseline_rmse: baseline_rmse,
      baseline_r_squared: baseline_r_squared
    }
  end

  @shap_max_samples 500

  @doc """
  Computes SHAP-based feature importances from the booster.
  Returns `{feature_importances, umbrella_importances}` where:
  - `feature_importances` is `%{feature_name => mean_abs_shap}`
  - `umbrella_importances` is `%{umbrella_category => summed_importance}`

  Samples up to #{@shap_max_samples} rows to avoid OOM on large datasets.
  """
  def feature_importances(booster, features_df, _target_series, feature_columns) do
    n_rows = DF.n_rows(features_df)

    # Sample down to avoid OOM on SHAP computation
    sampled_df =
      if n_rows > @shap_max_samples do
        sample_indices =
          0..(n_rows - 1)
          |> Enum.take_random(@shap_max_samples)
          |> Explorer.Series.from_list()

        DF.slice(features_df, sample_indices)
      else
        features_df
      end

    x = df_to_tensor(sampled_df)
    n_features = length(feature_columns)

    # pred_contribs returns {n_samples, n_features + 1} - last column is bias
    shap_values = EXGBoost.predict(booster, x, pred_contribs: true)

    # Slice off the bias column, take mean absolute SHAP per feature
    feature_shap = Nx.slice_along_axis(shap_values, 0, n_features, axis: 1)
    mean_abs_shap = feature_shap |> Nx.abs() |> Nx.mean(axes: [0])

    # Build feature → importance map
    shap_list = mean_abs_shap |> Nx.to_flat_list()

    feature_importances =
      feature_columns
      |> Enum.zip(shap_list)
      |> Map.new()

    # Aggregate by umbrella category
    umbrella = Preprocessing.umbrella_map()

    umbrella_importances =
      feature_importances
      |> Enum.reduce(%{}, fn {feat, imp}, acc ->
        category = Map.get(umbrella, feat, "other")
        Map.update(acc, category, imp, &(&1 + imp))
      end)

    {feature_importances, umbrella_importances}
  end

  @doc """
  Converts an Explorer DataFrame to an Nx tensor.
  Fills nils with 0.0 and casts all columns to {:f, 64}.
  """
  def df_to_tensor(df) do
    columns = DF.names(df)

    tensors =
      Enum.map(columns, fn col ->
        df
        |> DF.pull(col)
        |> series_to_tensor()
      end)

    Nx.stack(tensors, axis: 1)
  end

  @doc """
  Converts an Explorer Series to an Nx tensor.
  Fills nils with 0.0 and casts to {:f, 64}.
  """
  def series_to_tensor(series) do
    series
    |> Series.cast({:f, 64})
    |> Series.fill_missing(0.0)
    |> Series.to_tensor()
  end
end
