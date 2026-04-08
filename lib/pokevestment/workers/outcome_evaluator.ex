defmodule Pokevestment.Workers.OutcomeEvaluator do
  @moduledoc """
  Oban worker that evaluates prediction accuracy after 30 days.

  For each mature prediction snapshot (prediction_date <= today - 30),
  looks up the actual price at the outcome date and records whether
  the signal was correct.

  Runs daily at 10 AM UTC. Partial evaluation is fine — skipped
  snapshots (no price data available) retry the next day.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.ML.{PredictionOutcome, PredictionSnapshot}
  alias Pokevestment.Pricing.SoldPrice

  @batch_limit 10_000
  @lookback_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    cutoff_date = Date.add(today, -30)

    snapshots = fetch_mature_snapshots(cutoff_date)

    if snapshots == [] do
      Logger.info("[OutcomeEvaluator] 0 mature snapshots found")
      :ok
    else
      Logger.info("[OutcomeEvaluator] Found #{length(snapshots)} mature snapshots to evaluate")
      evaluate_batch(snapshots)
    end
  end

  defp fetch_mature_snapshots(cutoff_date) do
    from(ps in PredictionSnapshot,
      left_join: po in PredictionOutcome,
      on: po.prediction_snapshot_id == ps.id,
      where: ps.prediction_date <= ^cutoff_date,
      where: is_nil(po.id),
      where: ps.signal != "INSUFFICIENT_DATA",
      where: not is_nil(ps.current_price) and ps.current_price > 0,
      order_by: [asc: ps.prediction_date],
      limit: ^@batch_limit,
      select: ps
    )
    |> Repo.all()
  end

  defp evaluate_batch(snapshots) do
    # Collect all card_ids and their outcome dates for batch price lookup
    card_outcome_pairs =
      Enum.map(snapshots, fn ps ->
        {ps.card_id, Date.add(ps.prediction_date, 30)}
      end)

    outcome_prices = batch_lookup_prices(card_outcome_pairs)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {outcomes, skipped} =
      Enum.reduce(snapshots, {[], 0}, fn ps, {acc, skip_count} ->
        outcome_date = Date.add(ps.prediction_date, 30)
        price_key = {ps.card_id, outcome_date}

        case Map.get(outcome_prices, price_key) do
          nil ->
            {acc, skip_count + 1}

          %{price: price_at_outcome, source: source, currency: currency} ->
            price_at_prediction = Decimal.to_float(ps.current_price)
            price_out = Decimal.to_float(price_at_outcome)

            actual_return =
              if price_at_prediction > 0,
                do: (price_out - price_at_prediction) / price_at_prediction,
                else: 0.0

            signal_correct = evaluate_signal(ps.signal, actual_return)

            outcome = %{
              prediction_snapshot_id: ps.id,
              card_id: ps.card_id,
              model_version: ps.model_version,
              prediction_date: ps.prediction_date,
              outcome_date: outcome_date,
              predicted_fair_value: ps.predicted_fair_value,
              price_at_prediction: ps.current_price,
              price_at_outcome: price_at_outcome,
              actual_return: Decimal.from_float(Float.round(actual_return, 4)),
              signal: ps.signal,
              signal_correct: signal_correct,
              outcome_price_source: source,
              outcome_price_currency: currency,
              inserted_at: now
            }

            {[outcome | acc], skip_count}
        end
      end)

    inserted_count = batch_insert(outcomes)

    log_summary(outcomes, skipped, inserted_count)
    :ok
  end

  defp batch_lookup_prices(card_outcome_pairs) do
    # Group by card_id to build efficient queries
    card_ids = card_outcome_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    if card_ids == [] do
      %{}
    else
      # Find the date range we need
      outcome_dates = Enum.map(card_outcome_pairs, &elem(&1, 1))
      earliest = Enum.min(outcome_dates, Date)
      latest = Enum.max(outcome_dates, Date)
      lookback_start = Date.add(earliest, -@lookback_days)

      # Query sold_prices only — use price_usd for consistent currency
      # Variant priority matches price_features.ex exactly
      rows =
        from(sp in SoldPrice,
          where: sp.card_id in ^card_ids,
          where: sp.snapshot_date >= ^lookback_start,
          where: sp.snapshot_date <= ^latest,
          where: not is_nil(sp.price_usd) and sp.price_usd > 0,
          select: %{
            card_id: sp.card_id,
            snapshot_date: sp.snapshot_date,
            price: sp.price_usd,
            source: sp.marketplace,
            currency: "USD",
            variant: sp.variant
          },
          order_by: [
            asc: sp.card_id,
            desc: sp.snapshot_date,
            asc:
              fragment(
                """
                CASE
                  WHEN ? = 'tcgplayer' AND ? = 'normal' THEN 1
                  WHEN ? = 'tcgplayer' AND ? = 'holofoil' THEN 2
                  WHEN ? = 'tcgplayer' AND ? = 'reverse-holofoil' THEN 3
                  WHEN ? = 'cardmarket' AND ? = 'normal' THEN 4
                  WHEN ? = 'cardmarket' AND ? IN ('reverse-holofoil', 'holo') THEN 5
                  ELSE 6
                END
                """,
                sp.marketplace,
                sp.variant,
                sp.marketplace,
                sp.variant,
                sp.marketplace,
                sp.variant,
                sp.marketplace,
                sp.variant,
                sp.marketplace,
                sp.variant
              )
          ]
        )
        |> Repo.all()

      # Build a lookup: for each (card_id, outcome_date), find closest price <= outcome_date within lookback window
      price_by_card =
        rows
        |> Enum.group_by(& &1.card_id)

      Map.new(card_outcome_pairs, fn {card_id, outcome_date} ->
        earliest_acceptable = Date.add(outcome_date, -@lookback_days)

        price_entry =
          price_by_card
          |> Map.get(card_id, [])
          |> Enum.find(fn row ->
            Date.compare(row.snapshot_date, outcome_date) in [:lt, :eq] and
              Date.compare(row.snapshot_date, earliest_acceptable) in [:gt, :eq]
          end)

        key = {card_id, outcome_date}

        case price_entry do
          nil -> {key, nil}
          entry -> {key, %{price: entry.price, source: entry.source, currency: entry.currency}}
        end
      end)
    end
  end

  defp evaluate_signal("STRONG_BUY", actual_return), do: actual_return > 0.05
  defp evaluate_signal("BUY", actual_return), do: actual_return > 0.0
  defp evaluate_signal("HOLD", actual_return), do: abs(actual_return) < 0.10
  defp evaluate_signal("OVERVALUED", actual_return), do: actual_return < 0.0
  defp evaluate_signal(_, _), do: nil

  defp batch_insert([]), do: 0

  defp batch_insert(outcomes) do
    outcomes
    |> Enum.chunk_every(1000)
    |> Enum.reduce(0, fn chunk, total ->
      {count, _} =
        Repo.insert_all(PredictionOutcome, chunk,
          on_conflict: :nothing,
          conflict_target: [:prediction_snapshot_id]
        )

      total + count
    end)
  end

  defp log_summary(outcomes, skipped, inserted_count) do
    total = length(outcomes)

    signal_breakdown =
      outcomes
      |> Enum.group_by(& &1.signal)
      |> Enum.map(fn {signal, items} ->
        correct = Enum.count(items, & &1.signal_correct)
        total_signal = length(items)
        accuracy = if total_signal > 0, do: Float.round(correct / total_signal * 100, 1), else: 0.0
        "#{signal}: #{correct}/#{total_signal} (#{accuracy}%)"
      end)
      |> Enum.join(", ")

    Logger.info(
      "[OutcomeEvaluator] Evaluated #{total} snapshots, inserted #{inserted_count}, skipped #{skipped} (no price data). " <>
        "Accuracy: #{signal_breakdown}"
    )
  end
end
