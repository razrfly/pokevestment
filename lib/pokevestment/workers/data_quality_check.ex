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
    results = DataQuality.run_all_checks()

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
