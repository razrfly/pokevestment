defmodule Mix.Tasks.Pokevestment.BackfillSetFeatures do
  @moduledoc """
  Backfill set-level supply proxy features (secret_rare_count, secret_rare_ratio, era).

  Idempotent — safe to re-run (overwrites with same computed values).

  ## Usage

      mix pokevestment.backfill_set_features
  """

  use Mix.Task

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Ingestion.FeatureExtractor

  @shortdoc "Backfill set-level supply proxy features"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    sets =
      from(s in Set,
        select: %{
          id: s.id,
          series_id: s.series_id,
          card_count_official: s.card_count_official,
          card_count_total: s.card_count_total
        }
      )
      |> Repo.all()

    total = length(sets)
    Mix.shell().info("Backfilling set features for #{total} sets...")

    start = System.monotonic_time(:millisecond)

    updated =
      Enum.reduce(sets, 0, fn set, acc ->
        features = FeatureExtractor.compute_set_features(set)

        from(s in Set, where: s.id == ^set.id)
        |> Repo.update_all(
          set: [
            secret_rare_count: features.secret_rare_count,
            secret_rare_ratio: features.secret_rare_ratio,
            era: features.era
          ]
        )

        acc + 1
      end)

    elapsed = System.monotonic_time(:millisecond) - start
    Mix.shell().info("Backfill complete: #{updated} sets in #{format_duration(elapsed)}")
  end

  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
