defmodule Pokevestment.ML.Preprocessing do
  @moduledoc """
  Prepares the feature matrix DataFrame for XGBoost training.
  Handles categorical encoding, boolean casting, target separation, and train/val split.
  """

  require Explorer.DataFrame, as: DF
  alias Explorer.Series

  @categorical_columns ~w(category rarity era energy_type stage art_type set_age_bucket growth_rate)
  @boolean_columns ~w(has_ability is_full_art is_alternate_art is_secret_rare first_edition is_shadowless has_first_edition_stamp legal_standard legal_expanded is_legendary is_mythical is_baby has_evolution)
  @drop_columns ~w(card_id)
  @target_column "log_price"

  def categorical_columns, do: @categorical_columns
  def boolean_columns, do: @boolean_columns

  @doc """
  Full preprocessing pipeline: filter, encode, separate target, split.
  Returns `{:ok, train_features, train_target, val_features, val_target, metadata}`.
  """
  def prepare_for_training(df, opts \\ []) do
    val_fraction = Keyword.get(opts, :val_fraction, 0.2)

    # Filter rows without price data
    df = DF.filter_with(df, fn ldf -> Series.is_not_nil(ldf[@target_column]) end)

    # Encode categoricals and booleans
    {df, encodings} = encode_categoricals(df, @categorical_columns)
    df = encode_booleans(df, @boolean_columns)

    # Separate target and features
    target = DF.pull(df, @target_column)
    feature_cols = feature_columns(df)
    features = DF.select(df, feature_cols)

    # Split
    {train_features, train_target, val_features, val_target} =
      random_split(features, target, val_fraction)

    metadata = %{
      encodings: encodings,
      feature_columns: feature_cols,
      categorical_columns: @categorical_columns,
      boolean_columns: @boolean_columns,
      total_rows: Series.size(target),
      train_rows: DF.n_rows(train_features),
      val_rows: DF.n_rows(val_features)
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
      # Price momentum
      "price_avg" => "price_momentum",
      "price_low" => "price_momentum",
      "price_high" => "price_momentum",
      "price_mid" => "price_momentum",
      "price_market" => "price_momentum",
      "price_trend" => "price_momentum",
      "price_avg1" => "price_momentum",
      "price_avg7" => "price_momentum",
      "price_avg30" => "price_momentum",
      "price_momentum_7d" => "price_momentum",
      "price_momentum_30d" => "price_momentum",
      "price_volatility" => "price_momentum",
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
end
