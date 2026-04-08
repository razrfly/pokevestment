defmodule Pokevestment.ML.Scorer do
  @moduledoc """
  Scores all cards using a trained XGBoost booster.
  Assigns investment signals (STRONG_BUY, BUY, HOLD, OVERVALUED, INSUFFICIENT_DATA)
  and computes per-card SHAP-based drivers.
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.Series
  alias Pokevestment.ML.{ExplanationEngine, HorizonProjector, Preprocessing, Trainer}

  @top_n_drivers 5

  @doc """
  Scores all cards in the full assembled DataFrame.
  Cards without prices get INSUFFICIENT_DATA. Cards with prices get model predictions.

  Returns `{:ok, predictions_list}` where each entry is a map matching the CardPrediction schema.
  """
  def score_all(booster, full_df, metadata, opts \\ []) do
    version = Keyword.get(opts, :version, "v1.0.0")
    prediction_date = Keyword.get(opts, :prediction_date, Date.utc_today())
    feature_columns = metadata.feature_columns
    encodings = metadata.encodings

    # Split into cards with and without prices
    has_price_df =
      DF.filter_with(full_df, fn ldf -> Series.is_not_nil(ldf["log_price"]) end)

    no_price_df =
      DF.filter_with(full_df, fn ldf -> Series.is_nil(ldf["log_price"]) end)

    # Score cards with prices
    priced_predictions = score_priced_cards(booster, has_price_df, feature_columns, encodings, version, prediction_date)

    # Build INSUFFICIENT_DATA entries for cards without prices
    no_price_predictions = build_insufficient_data(no_price_df, version, prediction_date)

    {:ok, priced_predictions ++ no_price_predictions}
  end

  @doc """
  Assigns an investment signal based on the value ratio.
  """
  def assign_signal(_ratio, false), do: "INSUFFICIENT_DATA"
  def assign_signal(ratio, true) when ratio >= 1.3, do: "STRONG_BUY"
  def assign_signal(ratio, true) when ratio >= 1.1, do: "BUY"
  def assign_signal(ratio, true) when ratio >= 0.9, do: "HOLD"
  def assign_signal(_ratio, true), do: "OVERVALUED"

  # --- Private ---

  @shap_batch_size 500

  defp score_priced_cards(booster, df, feature_columns, encodings, version, prediction_date) do
    card_ids = df |> DF.pull("card_id") |> Series.to_list()
    current_prices = df |> DF.pull("canonical_price") |> Series.to_list()

    price_sources =
      if "price_source" in DF.names(df),
        do: df |> DF.pull("price_source") |> Series.to_list(),
        else: List.duplicate(nil, length(card_ids))

    price_currencies =
      if "price_currency" in DF.names(df),
        do: df |> DF.pull("price_currency") |> Series.to_list(),
        else: List.duplicate(nil, length(card_ids))

    # Extract feature columns for HorizonProjector opts
    volatilities = safe_pull_list(df, "price_volatility", length(card_ids))
    days_since_releases = safe_pull_list(df, "days_since_release", length(card_ids))
    meta_shares = safe_pull_list(df, "meta_share_30d", length(card_ids))

    # Encode the DataFrame using training-time encodings
    encoded_df = encode_for_scoring(df, encodings)

    # Select only the feature columns used in training, in the same order
    available_cols = DF.names(encoded_df)
    n = DF.n_rows(encoded_df)

    columns_map =
      Map.new(feature_columns, fn col ->
        if col in available_cols do
          {col, DF.pull(encoded_df, col) |> Series.to_list()}
        else
          {col, List.duplicate(0, n)}
        end
      end)

    features_df = DF.new(columns_map) |> DF.select(feature_columns)

    # Convert to tensor and predict (predictions are cheap, do all at once)
    x = Trainer.df_to_tensor(features_df)
    predictions = EXGBoost.predict(booster, x) |> Nx.flatten() |> Nx.to_flat_list()

    n_features = length(feature_columns)

    # Build prediction maps, computing SHAP in batches to avoid OOM
    card_ids
    |> Enum.with_index()
    |> Enum.chunk_every(@shap_batch_size)
    |> Enum.flat_map(fn chunk ->
      batch_indices = Enum.map(chunk, fn {_id, idx} -> idx end)
      batch_start = hd(batch_indices)
      batch_len = length(batch_indices)

      # Slice the feature tensor for this batch and compute SHAP
      batch_x = Nx.slice_along_axis(x, batch_start, batch_len, axis: 0)
      batch_shap = EXGBoost.predict(booster, batch_x, pred_contribs: true)

      chunk
      |> Enum.with_index()
      |> Enum.map(fn {{card_id, global_idx}, local_idx} ->
        predicted_log = Enum.at(predictions, global_idx)
        predicted_fair_value = :math.exp(predicted_log)
        current_price = Enum.at(current_prices, global_idx) || 0.0

        # Handle nil or zero current price
        current_price_float =
          case current_price do
            %Decimal{} -> Decimal.to_float(current_price)
            x when is_number(x) -> x / 1
            _ -> 0.0
          end

        {value_ratio, signal_strength, signal} =
          if current_price_float > 0 do
            ratio = predicted_fair_value / current_price_float
            strength = abs(ratio - 1.0)
            {ratio, strength, assign_signal(ratio, true)}
          else
            {nil, nil, "INSUFFICIENT_DATA"}
          end

        # Extract per-card SHAP drivers from batch
        card_shap = Nx.slice_along_axis(batch_shap, local_idx, 1, axis: 0) |> Nx.flatten()
        feature_shap = Nx.slice_along_axis(card_shap, 0, n_features, axis: 0) |> Nx.to_flat_list()

        {top_positive, top_negative, umbrella_breakdown} =
          compute_drivers(feature_columns, feature_shap)

        horizon_projections =
          HorizonProjector.project(current_price_float, predicted_fair_value,
            volatility: Enum.at(volatilities, global_idx) || 0.0,
            days_since_release: Enum.at(days_since_releases, global_idx) || 0,
            meta_share: Enum.at(meta_shares, global_idx) || 0.0
          )

        prediction_map = %{
          card_id: card_id,
          model_version: version,
          prediction_date: prediction_date,
          predicted_fair_value: safe_decimal(predicted_fair_value),
          current_price: safe_decimal(current_price_float),
          value_ratio: safe_decimal(value_ratio),
          signal_strength: safe_decimal(signal_strength),
          signal: signal,
          top_positive_drivers: top_positive,
          top_negative_drivers: top_negative,
          umbrella_breakdown: umbrella_breakdown,
          horizon_projections: horizon_projections,
          price_source: Enum.at(price_sources, global_idx),
          price_currency: Enum.at(price_currencies, global_idx)
        }

        explanation = ExplanationEngine.generate(prediction_map)
        Map.put(prediction_map, :explanation, explanation)
      end)
    end)
  end

  defp build_insufficient_data(df, version, prediction_date) do
    card_ids = df |> DF.pull("card_id") |> Series.to_list()

    Enum.map(card_ids, fn card_id ->
      prediction_map = %{
        card_id: card_id,
        model_version: version,
        prediction_date: prediction_date,
        predicted_fair_value: nil,
        current_price: nil,
        value_ratio: nil,
        signal_strength: nil,
        signal: "INSUFFICIENT_DATA",
        top_positive_drivers: %{},
        top_negative_drivers: %{},
        umbrella_breakdown: %{},
        horizon_projections: %{},
        price_source: nil,
        price_currency: nil
      }

      Map.put(prediction_map, :explanation, ExplanationEngine.generate(prediction_map))
    end)
  end

  defp encode_for_scoring(df, encodings) do
    # Apply categorical encodings from training
    categorical_columns = Preprocessing.categorical_columns()

    df =
      Enum.reduce(categorical_columns, df, fn col, acc ->
        if col in DF.names(acc) do
          encoding = Map.get(encodings, col, %{})

          encoded =
            acc
            |> DF.pull(col)
            |> Series.to_list()
            |> Enum.map(fn val -> Map.get(encoding, val, 0) end)
            |> Series.from_list()

          DF.put(acc, col, encoded)
        else
          acc
        end
      end)

    # Encode booleans
    Preprocessing.encode_booleans(df, Preprocessing.boolean_columns())
  end

  defp compute_drivers(feature_columns, shap_values) do
    umbrella = Preprocessing.umbrella_map()

    pairs =
      feature_columns
      |> Enum.zip(shap_values)
      |> Enum.sort_by(fn {_f, v} -> v end, :desc)

    top_positive =
      pairs
      |> Enum.filter(fn {_f, v} -> v > 0 end)
      |> Enum.take(@top_n_drivers)
      |> Map.new(fn {f, v} -> {f, Float.round(v, 6)} end)

    top_negative =
      pairs
      |> Enum.reverse()
      |> Enum.filter(fn {_f, v} -> v < 0 end)
      |> Enum.take(@top_n_drivers)
      |> Map.new(fn {f, v} -> {f, Float.round(v, 6)} end)

    umbrella_breakdown =
      pairs
      |> Enum.reduce(%{}, fn {feat, val}, acc ->
        category = Map.get(umbrella, feat, "other")
        Map.update(acc, category, val, &(&1 + val))
      end)
      |> Map.new(fn {k, v} -> {k, Float.round(v, 6)} end)

    {top_positive, top_negative, umbrella_breakdown}
  end

  defp safe_pull_list(df, col, n) do
    if col in DF.names(df),
      do: df |> DF.pull(col) |> Series.to_list(),
      else: List.duplicate(nil, n)
  end

  defp safe_decimal(nil), do: nil
  defp safe_decimal(val) when is_float(val), do: Decimal.from_float(val)
  defp safe_decimal(val) when is_integer(val), do: Decimal.new(val)
end
