defmodule Pokevestment.ML.Accountability do
  @moduledoc """
  Query functions for model accountability and outcome tracking.

  All functions return empty/zero-value results gracefully when no data exists.
  """

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.ML.{PredictionOutcome, PredictionSnapshot, ModelEvaluation}
  alias Pokevestment.Pricing.PriceSnapshot

  @doc """
  Signal accuracy breakdown by signal type.

  Returns `%{"STRONG_BUY" => %{total: n, correct: n, accuracy: float}, ...}` or `%{}`.
  """
  def signal_accuracy(model_version \\ "v1.0.0") do
    from(po in PredictionOutcome,
      where: po.model_version == ^model_version,
      where: not is_nil(po.signal_correct),
      group_by: po.signal,
      select: {
        po.signal,
        %{
          total: count(po.id),
          correct: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", po.signal_correct))
        }
      }
    )
    |> Repo.all()
    |> Map.new(fn {signal, %{total: total, correct: correct}} ->
      accuracy = if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0
      {signal, %{total: total, correct: correct, accuracy: accuracy}}
    end)
  end

  @doc """
  Signal calibration — mean and median actual returns per signal type.

  Returns `%{"STRONG_BUY" => %{mean_return: float, median_return: float}, ...}` or `%{}`.
  """
  def signal_calibration(model_version \\ "v1.0.0") do
    from(po in PredictionOutcome,
      where: po.model_version == ^model_version,
      where: not is_nil(po.actual_return),
      group_by: po.signal,
      select: {
        po.signal,
        %{
          mean_return: avg(po.actual_return),
          median_return:
            fragment("PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ?)", po.actual_return)
        }
      }
    )
    |> Repo.all()
    |> Map.new(fn {signal, stats} ->
      {signal,
       %{
         mean_return: decimal_to_float(stats.mean_return),
         median_return: decimal_to_float(stats.median_return)
       }}
    end)
  end

  @doc """
  Accuracy over time in rolling windows.

  Returns list of `%{period_end: date, accuracy: float, sample_size: integer}` or `[]`.
  """
  def accuracy_over_time(model_version \\ "v1.0.0", window_days \\ 30) do
    from(po in PredictionOutcome,
      where: po.model_version == ^model_version,
      where: not is_nil(po.signal_correct),
      select: %{
        period_end:
          fragment(
            "DATE_TRUNC('day', ? + INTERVAL '1 day' * (? - 1)) + INTERVAL '1 day' * (? - 1)",
            po.outcome_date,
            ^window_days,
            ^window_days
          ),
        outcome_date: po.outcome_date,
        signal_correct: po.signal_correct
      }
    )
    |> Repo.all()
    |> group_into_windows(window_days)
  end

  @doc """
  Latest model evaluation record.

  Returns `%ModelEvaluation{}` or `nil`.
  """
  def latest_evaluation(model_version \\ "v1.0.0") do
    from(me in ModelEvaluation,
      where: me.model_version == ^model_version,
      order_by: [desc: me.evaluation_date],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Pipeline health status — last completed job per worker class.

  Returns list of `%{worker: string, completed_at: datetime, state: string}`.
  """
  def pipeline_status do
    workers = [
      "Pokevestment.Workers.DailyPriceSync",
      "Pokevestment.Workers.TournamentSync",
      "Pokevestment.Workers.DailyPrediction",
      "Pokevestment.Workers.OutcomeEvaluator"
    ]

    from(j in "oban_jobs",
      where: j.worker in ^workers,
      where: j.state == "completed",
      distinct: j.worker,
      order_by: [asc: j.worker, desc: j.completed_at],
      select: %{
        worker: j.worker,
        completed_at: j.completed_at,
        state: j.state
      }
    )
    |> Repo.all()
  end

  @doc """
  How many prediction snapshots are mature (>=30 days old) and ready for evaluation.

  Returns `%{mature_snapshots: n, evaluated: n, pending_evaluation: n, earliest_maturity: date | nil}`.
  """
  def outcome_readiness(model_version \\ "v1.0.0") do
    today = Date.utc_today()
    cutoff = Date.add(today, -30)

    mature_count =
      from(ps in PredictionSnapshot,
        where: ps.model_version == ^model_version,
        where: ps.prediction_date <= ^cutoff,
        where: ps.signal != "INSUFFICIENT_DATA",
        where: not is_nil(ps.current_price) and ps.current_price > 0,
        select: count(ps.id)
      )
      |> Repo.one()

    # Count outcomes that match the same eligible snapshot population
    evaluated_count =
      from(po in PredictionOutcome,
        join: ps in PredictionSnapshot,
        on: po.prediction_snapshot_id == ps.id,
        where: ps.model_version == ^model_version,
        where: ps.prediction_date <= ^cutoff,
        where: ps.signal != "INSUFFICIENT_DATA",
        where: not is_nil(ps.current_price) and ps.current_price > 0,
        select: count(po.id)
      )
      |> Repo.one()

    earliest =
      from(ps in PredictionSnapshot,
        where: ps.model_version == ^model_version,
        where: ps.signal != "INSUFFICIENT_DATA",
        where: not is_nil(ps.current_price) and ps.current_price > 0,
        select: min(ps.prediction_date)
      )
      |> Repo.one()

    earliest_maturity = if earliest, do: Date.add(earliest, 30), else: nil

    %{
      mature_snapshots: mature_count || 0,
      evaluated: evaluated_count || 0,
      pending_evaluation: max((mature_count || 0) - (evaluated_count || 0), 0),
      earliest_maturity: earliest_maturity
    }
  end

  @doc """
  Date range of available price history.

  Returns `%{earliest: date, latest: date, days: integer}` or `%{earliest: nil, latest: nil, days: 0}`.
  """
  def price_history_range do
    result =
      from(ps in PriceSnapshot,
        select: %{earliest: min(ps.snapshot_date), latest: max(ps.snapshot_date)}
      )
      |> Repo.one()

    case result do
      %{earliest: nil} ->
        %{earliest: nil, latest: nil, days: 0}

      %{earliest: earliest, latest: latest} ->
        %{earliest: earliest, latest: latest, days: Date.diff(latest, earliest)}
    end
  end

  # --- Private Helpers ---

  defp group_into_windows(rows, window_days) do
    if rows == [] do
      []
    else
      dates = Enum.map(rows, & &1.outcome_date)
      min_date = Enum.min(dates, Date)
      max_date = Enum.max(dates, Date)

      # Generate window boundaries
      Stream.iterate(min_date, &Date.add(&1, window_days))
      |> Enum.take_while(&(Date.compare(&1, max_date) != :gt))
      |> Enum.map(fn window_start ->
        window_end = Date.add(window_start, window_days - 1)

        in_window =
          Enum.filter(rows, fn r ->
            Date.compare(r.outcome_date, window_start) != :lt and
              Date.compare(r.outcome_date, window_end) != :gt
          end)

        total = length(in_window)
        correct = Enum.count(in_window, & &1.signal_correct)
        accuracy = if total > 0, do: Float.round(correct / total * 100, 1), else: 0.0

        %{period_end: window_end, accuracy: accuracy, sample_size: total}
      end)
      |> Enum.filter(&(&1.sample_size > 0))
    end
  end

  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_float(n), do: n
  defp decimal_to_float(n) when is_integer(n), do: n / 1
end
