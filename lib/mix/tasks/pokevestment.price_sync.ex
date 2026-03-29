defmodule Mix.Tasks.Pokevestment.PriceSync do
  @moduledoc """
  Manually trigger a daily price sync from TCGdex.

  ## Usage

      mix pokevestment.price_sync
  """

  use Mix.Task

  @shortdoc "Sync current card prices from TCGdex"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Starting price sync...")

    case Pokevestment.Ingestion.PriceSync.run() do
      {:ok, summary} ->
        Mix.shell().info("\nPrice sync complete in #{format_duration(summary.elapsed_ms)}")
        Mix.shell().info("  Total cards:        #{summary.total}")
        Mix.shell().info("  Processed:          #{summary.processed}")
        Mix.shell().info("  Snapshots inserted: #{summary.snapshots_inserted}")

        if summary.failed != [] do
          Mix.shell().info("  Failed:             #{length(summary.failed)}")
        end

      {:error, reason} ->
        Mix.shell().error("Price sync failed: #{inspect(reason)}")
    end
  end

  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
