defmodule Mix.Tasks.Pokevestment.BackfillArtTypes do
  @moduledoc """
  Backfill art type feature columns for all existing cards from their rarity.

  Idempotent — safe to re-run (overwrites with same computed values).

  ## Usage

      mix pokevestment.backfill_art_types
  """

  use Mix.Task

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Card
  alias Pokevestment.Ingestion.FeatureExtractor

  import Pokevestment.Helpers, only: [format_duration: 1]

  @shortdoc "Backfill art type feature columns on cards"
  @batch_size 1000

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    total = Repo.aggregate(Card, :count)
    Mix.shell().info("Backfilling art type features for #{total} cards...")

    start = System.monotonic_time(:millisecond)

    updated = backfill_batches(total, nil, 0)

    elapsed = System.monotonic_time(:millisecond) - start
    Mix.shell().info("\nBackfill complete: #{updated} cards in #{format_duration(elapsed)}")
  end

  @art_keys [:art_type, :is_full_art, :is_alternate_art]

  defp backfill_batches(total, last_id, acc) do
    query =
      Card
      |> select([c], {c.id, c.rarity})
      |> order_by(:id)
      |> limit(@batch_size)

    query = if last_id, do: where(query, [c], c.id > ^last_id), else: query

    batch = Repo.all(query)

    if batch == [] do
      acc
    else
      case Repo.transaction(fn ->
             try do
               Enum.each(batch, fn {id, rarity} ->
                 features = FeatureExtractor.compute_art_features(%{rarity: rarity})

                 from(c in Card, where: c.id == ^id)
                 |> Repo.update_all(set: Map.to_list(Map.take(features, @art_keys)))
               end)
             rescue
               e -> Repo.rollback(Exception.message(e))
             end
           end) do
        {:ok, _} ->
          processed = acc + length(batch)
          {new_last_id, _} = List.last(batch)

          if rem(processed, 5_000) == 0 or processed == total do
            Mix.shell().info("  Backfilled #{processed}/#{total} cards")
          end

          backfill_batches(total, new_last_id, processed)

        {:error, reason} ->
          Mix.raise(
            "Batch transaction failed after #{acc} cards: #{reason}"
          )
      end
    end
  end

end
