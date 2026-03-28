defmodule Mix.Tasks.Pokevestment.BackfillFeatures do
  @moduledoc """
  Backfill ML feature columns for all existing cards from their JSONB data.

  Idempotent — safe to re-run (overwrites with same computed values).

  ## Usage

      mix pokevestment.backfill_features
  """

  use Mix.Task

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Card
  alias Pokevestment.Ingestion.FeatureExtractor

  @shortdoc "Backfill ML feature columns on cards"
  @batch_size 1000

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    total = Repo.aggregate(Card, :count)
    Mix.shell().info("Backfilling ML features for #{total} cards...")

    start = System.monotonic_time(:millisecond)

    updated =
      Card
      |> select([c], {c.id, c.attacks, c.abilities, c.weaknesses, c.resistances, c.variants, c.variants_detailed})
      |> order_by(:id)
      |> Repo.all()
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(0, fn batch, acc ->
        Repo.transaction(fn ->
          Enum.each(batch, fn {id, attacks, abilities, weaknesses, resistances, variants, variants_detailed} ->
            features =
              FeatureExtractor.compute_features(%{
                attacks: attacks,
                abilities: abilities,
                weaknesses: weaknesses,
                resistances: resistances,
                variants: variants,
                variants_detailed: variants_detailed
              })

            from(c in Card, where: c.id == ^id)
            |> Repo.update_all(
              set: [
                attack_count: features.attack_count,
                total_attack_damage: features.total_attack_damage,
                max_attack_damage: features.max_attack_damage,
                has_ability: features.has_ability,
                ability_count: features.ability_count,
                weakness_count: features.weakness_count,
                resistance_count: features.resistance_count,
                first_edition: features.first_edition,
                is_shadowless: features.is_shadowless,
                has_first_edition_stamp: features.has_first_edition_stamp
              ]
            )
          end)
        end)

        processed = acc + length(batch)

        if rem(processed, 5_000) == 0 or processed == total do
          Mix.shell().info("  Backfilled #{processed}/#{total} cards")
        end

        processed
      end)

    elapsed = System.monotonic_time(:millisecond) - start
    Mix.shell().info("\nBackfill complete: #{updated} cards in #{format_duration(elapsed)}")
  end

  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
