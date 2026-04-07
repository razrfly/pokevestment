defmodule Pokevestment.Workers.DataQualityCheck do
  @moduledoc """
  Oban worker for daily data quality monitoring.

  Runs at 7 AM UTC (after DailyPriceSync, before TournamentSync) and
  logs a structured summary of data integrity checks. Monitoring only —
  always returns `:ok`.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Pokevestment.Ingestion.DataQuality

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    results =
      try do
        DataQuality.run_all_checks()
      rescue
        e ->
          Logger.error(
            "[DataQualityCheck] DataQuality.run_all_checks failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
          )

          reraise e, __STACKTRACE__
      end

    warnings =
      results
      |> Enum.filter(fn {_check, %{status: status}} -> status == :warning end)
      |> Enum.map(fn {check, %{detail: detail}} -> "#{check}: #{detail}" end)

    summary =
      results
      |> Enum.map(fn {check, %{status: status, detail: detail}} ->
        "#{check}=#{status} (#{detail})"
      end)
      |> Enum.join("; ")

    if warnings == [] do
      Logger.info("[DataQualityCheck] All checks passed. #{summary}")
    else
      Logger.warning(
        "[DataQualityCheck] #{length(warnings)} warning(s): #{Enum.join(warnings, "; ")}"
      )

      Logger.info("[DataQualityCheck] Full summary: #{summary}")
    end

    :ok
  end
end
