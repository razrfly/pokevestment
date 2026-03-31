defmodule Mix.Tasks.Pokevestment.ImportTournaments do
  @moduledoc """
  Import tournament data from Limitless TCG API.

  ## Usage

      mix pokevestment.import_tournaments                    # Import STANDARD format
      mix pokevestment.import_tournaments --format EXPANDED  # Specific format
      mix pokevestment.import_tournaments --all              # All formats
  """

  use Mix.Task

  import Pokevestment.Helpers, only: [format_duration: 1]

  @shortdoc "Import tournament data from Limitless TCG"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)

    format = Keyword.get(opts, :format)
    Mix.shell().info("Starting tournament import (format=#{format || "ALL"})...")

    case Pokevestment.Ingestion.TournamentImport.run(opts) do
      {:ok, summary} ->
        Mix.shell().info("\nTournament import complete in #{format_duration(summary.elapsed_ms)}")
        Mix.shell().info("  Tournaments:  #{summary.tournaments}")
        Mix.shell().info("  Standings:    #{summary.standings}")
        Mix.shell().info("  Deck cards:   #{summary.deck_cards}")
        Mix.shell().info("  Skipped:      #{summary.skipped}")

        if summary.failed != [] do
          Mix.shell().info("  Failed:       #{length(summary.failed)}")
        end

        if summary.unresolved_codes != [] do
          Mix.shell().info(
            "  Unresolved PTCGO codes: #{Enum.join(summary.unresolved_codes, ", ")}"
          )
        end

      {:error, reason} ->
        Mix.raise("Tournament import failed: #{inspect(reason)}")
    end
  end

  defp parse_args(args) do
    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [format: :string, all: :boolean],
        aliases: []
      )

    cond do
      parsed[:all] -> [format: nil]
      parsed[:format] -> [format: parsed[:format]]
      true -> [format: "STANDARD"]
    end
  end
end
