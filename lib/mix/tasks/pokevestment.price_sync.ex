defmodule Mix.Tasks.Pokevestment.PriceSync do
  @moduledoc """
  Manually trigger a daily price sync from TCGdex.

  ## Usage

      mix pokevestment.price_sync
  """

  use Mix.Task

  import Pokevestment.Helpers, only: [format_duration: 1]

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

        if summary.exit_count > 0 do
          Mix.shell().info("  Timed out:          #{summary.exit_count}")
        end

      {:error, reason} ->
        Mix.raise("Price sync failed: #{inspect(reason)}")
    end
  end

end
