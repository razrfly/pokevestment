defmodule Pokevestment.ML.Preprocessing do
  @moduledoc """
  Prepares the feature matrix DataFrame for XGBoost training.
  Handles categorical encoding, boolean casting, target separation, and train/val split.
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.Series

  @categorical_columns ~w(category rarity era energy_type stage art_type set_age_bucket growth_rate price_currency)
  @boolean_columns ~w(has_ability is_full_art is_alternate_art is_secret_rare first_edition is_shadowless has_first_edition_stamp legal_standard legal_expanded is_legendary is_mythical is_baby has_evolution)
  # Drop identifier columns + raw price columns (target leakage — the model must
  # predict fair value from card fundamentals, not from the current price itself).
  # Derived features (momentum, volatility) are kept as valid trend signals.
  @drop_columns ~w(
    card_id canonical_price price_source
    price_avg_1d price_avg_7d price_avg_30d
  )
  @target_column "log_price"

  def categorical_columns, do: @categorical_columns
  def boolean_columns, do: @boolean_columns

  @doc """
  Full preprocessing pipeline: filter, encode, separate target, split.
  Returns `{:ok, train_features, train_target, val_features, val_target, metadata}`.
  """
  def prepare_for_training(df, opts \\ []) do
    val_fraction = Keyword.get(opts, :val_fraction, 0.2)
    split_strategy = Keyword.get(opts, :split_strategy, :random)

    # Filter rows without price data
    df = DF.filter_with(df, fn ldf -> Series.is_not_nil(ldf[@target_column]) end)

    # Validate temporal split preconditions
    if split_strategy == :temporal and "days_since_release" not in DF.names(df) do
      raise ArgumentError,
            "temporal split requires 'days_since_release' column but it is missing from the DataFrame"
    end

    # Capture days_since_release before encoding/dropping (needed for temporal split)
    days_series =
      if split_strategy == :temporal,
        do: DF.pull(df, "days_since_release"),
        else: nil

    # Encode categoricals and booleans
    {df, encodings} = encode_categoricals(df, @categorical_columns)
    df = encode_booleans(df, @boolean_columns)

    # Separate target and features
    target = DF.pull(df, @target_column)
    feature_cols = feature_columns(df)
    features = DF.select(df, feature_cols)

    # Split
    {train_features, train_target, val_features, val_target} =
      case split_strategy do
        :temporal ->
          temporal_split(features, target, val_fraction, days_series)

        :random ->
          random_split(features, target, val_fraction)
      end

    metadata = %{
      encodings: encodings,
      feature_columns: feature_cols,
      categorical_columns: @categorical_columns,
      boolean_columns: @boolean_columns,
      total_rows: Series.size(target),
      train_rows: DF.n_rows(train_features),
      val_rows: DF.n_rows(val_features),
      split_strategy: Atom.to_string(split_strategy)
    }

    {:ok, train_features, train_target, val_features, val_target, metadata}
  end

  @doc """
  Encodes categorical string columns as integers using sorted unique value mappings.
  Returns `{encoded_df, %{column_name => %{value => integer}}}`.
  """
  def encode_categoricals(df, columns) do
    Enum.reduce(columns, {df, %{}}, fn col, {acc_df, acc_enc} ->
      if col in DF.names(acc_df) do
        series = DF.pull(acc_df, col)
        unique_vals = series |> Series.distinct() |> Series.to_list() |> Enum.sort()

        # nil gets encoded as 0, real values start at 1
        encoding =
          unique_vals
          |> Enum.reject(&is_nil/1)
          |> Enum.with_index(1)
          |> Map.new()

        encoded =
          series
          |> Series.to_list()
          |> Enum.map(fn val -> Map.get(encoding, val, 0) end)
          |> Series.from_list()

        acc_df = DF.put(acc_df, col, encoded)
        {acc_df, Map.put(acc_enc, col, encoding)}
      else
        {acc_df, acc_enc}
      end
    end)
  end

  @doc """
  Encodes boolean columns as integers (true=1, false=0, nil=0).
  """
  def encode_booleans(df, columns) do
    Enum.reduce(columns, df, fn col, acc_df ->
      if col in DF.names(acc_df) do
        series = DF.pull(acc_df, col)

        encoded =
          series
          |> Series.to_list()
          |> Enum.map(fn
            true -> 1
            _ -> 0
          end)
          |> Series.from_list()

        DF.put(acc_df, col, encoded)
      else
        acc_df
      end
    end)
  end

  @doc """
  Returns the list of feature column names (excludes card_id and target).
  """
  def feature_columns(df) do
    DF.names(df) -- [@target_column | @drop_columns]
  end

  @doc """
  Maps feature names to umbrella categories for importance aggregation.
  """
  def umbrella_map do
    %{
      # Card attributes
      "hp" => "card_attributes",
      "retreat_cost" => "card_attributes",
      "attack_count" => "card_attributes",
      "total_attack_damage" => "card_attributes",
      "max_attack_damage" => "card_attributes",
      "has_ability" => "card_attributes",
      "ability_count" => "card_attributes",
      "weakness_count" => "card_attributes",
      "resistance_count" => "card_attributes",
      "energy_cost_total" => "card_attributes",
      "type_count" => "card_attributes",
      "stage" => "card_attributes",
      "category" => "card_attributes",
      "energy_type" => "card_attributes",
      # Rarity & collectibility
      "rarity" => "rarity_collectibility",
      "art_type" => "rarity_collectibility",
      "is_full_art" => "rarity_collectibility",
      "is_alternate_art" => "rarity_collectibility",
      "is_secret_rare" => "rarity_collectibility",
      "first_edition" => "rarity_collectibility",
      "is_shadowless" => "rarity_collectibility",
      "has_first_edition_stamp" => "rarity_collectibility",
      "language_count" => "rarity_collectibility",
      "secret_rare_ratio" => "rarity_collectibility",
      # Tournament / meta
      "tournament_appearances" => "tournament_meta",
      "total_deck_inclusions" => "tournament_meta",
      "avg_copies_per_deck" => "tournament_meta",
      "meta_share_total" => "tournament_meta",
      "meta_share_30d" => "tournament_meta",
      "meta_share_90d" => "tournament_meta",
      "archetype_count" => "tournament_meta",
      "top_8_appearances" => "tournament_meta",
      "top_8_rate" => "tournament_meta",
      "avg_placing" => "tournament_meta",
      "avg_win_rate" => "tournament_meta",
      "meta_trend" => "tournament_meta",
      "weighted_tournament_score" => "tournament_meta",
      # Price momentum (only derived features — raw prices are dropped to avoid leakage)
      "price_momentum_7d" => "price_momentum",
      "price_momentum_30d" => "price_momentum",
      "price_volatility" => "price_momentum",
      "price_currency" => "price_momentum",
      # Supply proxy
      "set_card_count" => "supply_proxy",
      "era" => "supply_proxy",
      "days_since_release" => "supply_proxy",
      "set_age_bucket" => "supply_proxy",
      "legal_standard" => "supply_proxy",
      "legal_expanded" => "supply_proxy",
      # Species
      "species_generation" => "species",
      "is_legendary" => "species",
      "is_mythical" => "species",
      "is_baby" => "species",
      "capture_rate" => "species",
      "base_happiness" => "species",
      "growth_rate" => "species",
      "dex_id_count" => "species",
      "has_evolution" => "species",
      # Illustrator
      "illustrator_frequency" => "illustrator",
      "illustrator_avg_price" => "illustrator"
    }
  end

  # --- Private Helpers ---

  defp temporal_split(features, target, val_fraction, days_series)
       when val_fraction > 0 and val_fraction < 1 do
    n = DF.n_rows(features)

    if n < 2 do
      raise ArgumentError, "temporal_split requires at least 2 rows, got #{n}"
    end

    # Sort by days_since_release descending (oldest cards first → newest in validation).
    # Nil values get sorted to training set by using a very high value (oldest).
    sort_values =
      days_series
      |> Series.to_list()
      |> Enum.with_index()
      |> Enum.sort_by(fn {val, _idx} ->
        # Descending by days_since_release: highest (oldest) first in training
        -(val || 999_999)
      end)

    sorted_indices = Enum.map(sort_values, fn {_val, idx} -> idx end)

    val_size = n |> Kernel.*(val_fraction) |> round() |> max(1) |> min(n - 1)
    train_size = n - val_size

    train_indices = Enum.take(sorted_indices, train_size)
    val_indices = Enum.drop(sorted_indices, train_size)

    train_idx_series = Series.from_list(train_indices)
    val_idx_series = Series.from_list(val_indices)

    train_features = DF.slice(features, train_idx_series)
    val_features = DF.slice(features, val_idx_series)
    train_target = Series.slice(target, train_idx_series)
    val_target = Series.slice(target, val_idx_series)

    {train_features, train_target, val_features, val_target}
  end

  defp temporal_split(_features, _target, val_fraction, _days_series) do
    raise ArgumentError,
          "temporal_split requires val_fraction to be > 0 and < 1, got #{inspect(val_fraction)}"
  end

  defp random_split(features, target, val_fraction) when val_fraction > 0 and val_fraction < 1 do
    n = DF.n_rows(features)

    if n < 2 do
      raise ArgumentError, "random_split requires at least 2 rows, got #{n}"
    end

    val_size = n |> Kernel.*(val_fraction) |> round() |> max(1) |> min(n - 1)
    train_size = n - val_size

    # Shuffle indices
    indices = Enum.shuffle(0..(n - 1))
    train_indices = Enum.take(indices, train_size)
    val_indices = Enum.drop(indices, train_size)

    train_idx_series = Series.from_list(train_indices)
    val_idx_series = Series.from_list(val_indices)

    train_features = DF.slice(features, train_idx_series)
    val_features = DF.slice(features, val_idx_series)
    train_target = Series.slice(target, train_idx_series)
    val_target = Series.slice(target, val_idx_series)

    {train_features, train_target, val_features, val_target}
  end

  defp random_split(_features, _target, val_fraction) do
    raise ArgumentError,
          "random_split requires val_fraction to be > 0 and < 1, got #{inspect(val_fraction)}"
  end
end
