defmodule Mix.Tasks.Pokevestment.PriceSync do
  @moduledoc """
  Manually trigger a daily price sync via the Pokemon TCG API.

  ## Usage

      mix pokevestment.price_sync
  """

  use Mix.Task

  import Pokevestment.Helpers, only: [format_duration: 1]

  @shortdoc "Sync current card prices via Pokemon TCG API"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Starting price sync...")

    case Pokevestment.Ingestion.PriceSync.run() do
      {:ok, summary} ->
        Mix.shell().info("\nPrice sync complete in #{format_duration(summary.elapsed_ms)}")
        Mix.shell().info("  Sets mapped:        #{summary.total}")
        Mix.shell().info("  Sets processed:     #{summary.processed}")
        Mix.shell().info("  Prices inserted:    #{summary.prices_inserted}")

        if summary.failed != [] do
          Mix.shell().info("  Failed sets:        #{length(summary.failed)}")
        end

      {:error, reason} ->
        Mix.raise("Price sync failed: #{inspect(reason)}")
    end
  end
end
