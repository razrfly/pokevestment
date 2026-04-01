defmodule Pokevestment.Predictions do
  @moduledoc """
  Context module for card predictions. Provides query functions
  used by LiveView to display ML-generated investment signals.
  """

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Card
  alias Pokevestment.ML.CardPrediction
  alias Pokevestment.ML.PredictionSnapshot

  @doc """
  Lists predictions for all cards in a set, sorted by signal_strength DESC.

  ## Options
    * `:signal` - filter by signal value (e.g. "STRONG_BUY", "BUY")
    * `:limit` - max results (default 100)
  """
  def list_for_set(set_id, opts \\ []) do
    signal_filter = Keyword.get(opts, :signal)
    limit = Keyword.get(opts, :limit, 100)

    query =
      from p in CardPrediction,
        join: c in Card,
        on: c.id == p.card_id,
        where: c.set_id == ^set_id,
        order_by: [desc: p.signal_strength],
        limit: ^limit,
        preload: [card: c]

    query =
      if signal_filter do
        where(query, [p], p.signal == ^signal_filter)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single card prediction with the card preloaded.
  Returns nil if no prediction exists.
  """
  def get_prediction(card_id) do
    CardPrediction
    |> Repo.get(card_id)
    |> Repo.preload(:card)
  end

  @doc """
  Returns a summary of signal counts for a specific set.

  Returns a map like `%{"STRONG_BUY" => 2, "BUY" => 5, "HOLD" => 150}`.
  """
  def signal_summary_for_set(set_id) do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: c.set_id == ^set_id,
      group_by: p.signal,
      select: {p.signal, count(p.card_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns aggregated signal counts grouped by set_id.

  Returns a list of maps: `%{set_id: "sv06", signal: "BUY", count: 12}`.
  Only includes BUY and STRONG_BUY signals.
  """
  def signal_counts_by_set do
    from(p in CardPrediction,
      join: c in Card,
      on: c.id == p.card_id,
      where: p.signal in ["STRONG_BUY", "BUY"],
      group_by: [c.set_id, p.signal],
      select: %{set_id: c.set_id, signal: p.signal, count: count(p.card_id)}
    )
    |> Repo.all()
  end

  @doc """
  Batch upserts predictions into card_predictions (hot table) and inserts
  corresponding rows into prediction_snapshots (cold table).

  Expects a list of maps with prediction attributes.
  """
  def upsert_predictions(predictions_list) when is_list(predictions_list) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      prediction_count = upsert_card_predictions(predictions_list, now)
      snapshot_count = insert_prediction_snapshots(predictions_list, now)

      %{predictions_upserted: prediction_count, snapshots_inserted: snapshot_count}
    end)
  end

  defp upsert_card_predictions(predictions_list, now) do
    predictions_list
    |> Enum.map(fn attrs ->
      attrs
      |> Map.put(:updated_at, now)
    end)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} =
        Repo.insert_all(CardPrediction, chunk,
          on_conflict:
            {:replace_all_except, [:card_id]},
          conflict_target: :card_id
        )

      acc + count
    end)
  end

  defp insert_prediction_snapshots(predictions_list, now) do
    predictions_list
    |> Enum.map(fn attrs ->
      attrs
      |> Map.drop([:top_positive_drivers, :top_negative_drivers, :umbrella_breakdown])
      |> Map.put(:inserted_at, now)
    end)
    |> Enum.chunk_every(500)
    |> Enum.reduce(0, fn chunk, acc ->
      {count, _} = Repo.insert_all(PredictionSnapshot, chunk)
      acc + count
    end)
  end
end
