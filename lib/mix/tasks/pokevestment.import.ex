defmodule Mix.Tasks.Pokevestment.Import do
  @moduledoc """
  Import data from TCGdex and PokeAPI into the database.

  ## Usage

      mix pokevestment.import                  # Full import (all entities)
      mix pokevestment.import series           # Import series only
      mix pokevestment.import sets             # Import sets only
      mix pokevestment.import species          # Import Pokemon species only
      mix pokevestment.import cards            # Import cards only
  """

  use Mix.Task

  import Pokevestment.Helpers, only: [format_duration: 1]

  @shortdoc "Import data from TCGdex and PokeAPI"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    start = System.monotonic_time(:millisecond)

    result =
      case args do
        [] ->
          Mix.shell().info("Starting full import...")
          Pokevestment.Ingestion.FullImport.run()

        ["series"] ->
          Pokevestment.Ingestion.FullImport.import_series()

        ["sets"] ->
          Pokevestment.Ingestion.FullImport.import_sets()

        ["species"] ->
          Pokevestment.Ingestion.FullImport.import_species()

        ["cards"] ->
          Pokevestment.Ingestion.FullImport.import_cards()

        [unknown] ->
          Mix.shell().error("Unknown entity: #{unknown}")
          Mix.shell().error("Usage: mix pokevestment.import [series|sets|species|cards]")
          {:error, :unknown_entity}

        _ ->
          Mix.shell().error("Usage: mix pokevestment.import [series|sets|species|cards]")
          {:error, :invalid_args}
      end

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, summary} ->
        Mix.shell().info("\nImport complete in #{format_duration(elapsed)}")
        print_summary(summary)

      {:error, reason} ->
        Mix.shell().error("\nImport failed: #{inspect(reason)}")
    end
  end

  defp print_summary(%{series: s, sets: st, species: sp, cards: cards}) do
    Mix.shell().info("  Series:  #{s}")
    Mix.shell().info("  Sets:    #{st}")
    Mix.shell().info("  Species: #{sp}")
    Mix.shell().info("  Cards:   #{cards.imported}/#{cards.total}")

    if cards.failed != [] do
      Mix.shell().info("  Failed:  #{length(cards.failed)} cards")
    end
  end

  defp print_summary(%{imported: imported, total: total, failed: failed}) do
    Mix.shell().info("  Cards: #{imported}/#{total}")
    if failed != [], do: Mix.shell().info("  Failed: #{length(failed)} cards")
  end

  defp print_summary(count) when is_integer(count) do
    Mix.shell().info("  Imported: #{count}")
  end

  defp print_summary(_), do: :ok
end
