defmodule Mix.Tasks.Pokevestment.BackfillLanguageCounts do
  @moduledoc """
  Backfill language_count for all cards by querying TCGdex multi-language endpoints.

  Fetches card ID lists for 6 Western languages (en, fr, de, it, es, pt),
  builds a frequency map, and batch-updates cards. Practical range: 1–6.

  Japanese is excluded because TCGdex uses entirely different set codes and card
  IDs for Japanese cards (e.g. `SV1a-001` vs `sv01-001`). No reliable automated
  mapping exists between Japanese and Western card IDs. The 6 Western languages
  share identical card IDs, making frequency counting accurate.

  Idempotent — safe to re-run.

  ## Usage

      mix pokevestment.backfill_language_counts
  """

  use Mix.Task

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Card
  alias Pokevestment.Api.Tcgdex

  import Pokevestment.Helpers, only: [format_duration: 1]

  @shortdoc "Backfill language_count on cards from TCGdex multi-language data"
  @languages ~w(en fr de it es pt)
  @batch_size 1000

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    Mix.shell().info("Fetching card lists for #{length(@languages)} languages...")
    start = System.monotonic_time(:millisecond)

    # Fetch card ID sets for each language concurrently
    lang_results =
      @languages
      |> Task.async_stream(
        fn lang ->
          case Tcgdex.list_cards_for_language(lang) do
            {:ok, cards} ->
              ids = MapSet.new(cards, fn c -> c["id"] end)
              Mix.shell().info("  #{lang}: #{MapSet.size(ids)} cards")
              {:ok, lang, ids}

            {:error, reason} ->
              Mix.shell().error("  #{lang}: failed — #{inspect(reason)}")
              {:error, lang, reason}
          end
        end,
        max_concurrency: 3,
        timeout: 120_000
      )
      |> Enum.reduce({[], []}, fn
        {:ok, {:ok, lang, ids}}, {successes, failures} ->
          {[{lang, ids} | successes], failures}

        {:ok, {:error, lang, reason}}, {successes, failures} ->
          {successes, [{lang, reason} | failures]}

        {:exit, reason}, {successes, failures} ->
          {successes, [{:unknown, reason} | failures]}
      end)

    {successes, failures} = lang_results

    if failures != [] do
      Mix.shell().error("Failed languages: #{inspect(Enum.map(failures, &elem(&1, 0)))}")
    end

    if successes == [] do
      Mix.shell().error("No language data fetched. Aborting.")
    else
      # Build frequency map: card_id → count of languages
      Mix.shell().info("Building language frequency map...")

      freq_map =
        Enum.reduce(successes, %{}, fn {_lang, ids}, acc ->
          Enum.reduce(ids, acc, fn id, inner_acc ->
            Map.update(inner_acc, id, 1, &(&1 + 1))
          end)
        end)

      Mix.shell().info("Unique cards across languages: #{map_size(freq_map)}")

      # Update all cards that exist in our DB (including count == 1 for idempotency)
      db_card_ids =
        from(c in Card, select: c.id)
        |> Repo.all()
        |> MapSet.new()

      updates =
        freq_map
        |> Enum.filter(fn {id, _count} -> MapSet.member?(db_card_ids, id) end)
        |> Enum.sort_by(&elem(&1, 0))

      Mix.shell().info("Cards to update: #{length(updates)}")

      # Group by count value and batch update — one query per (count, batch) instead of per card
      updates_by_count =
        Enum.group_by(updates, fn {_id, count} -> count end, fn {id, _count} -> id end)

      total_updates = length(updates)

      updated =
        updates_by_count
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.reduce(0, fn {count, ids}, acc ->
          ids
          |> Enum.chunk_every(@batch_size)
          |> Enum.reduce(acc, fn batch_ids, inner_acc ->
            from(c in Card, where: c.id in ^batch_ids)
            |> Repo.update_all(set: [language_count: count])

            processed = inner_acc + length(batch_ids)

            if rem(processed, 5_000) == 0 or processed == total_updates do
              Mix.shell().info("  Updated #{processed}/#{total_updates} cards")
            end

            processed
          end)
        end)

      elapsed = System.monotonic_time(:millisecond) - start

      Mix.shell().info(
        "Backfill complete: #{updated} cards updated in #{format_duration(elapsed)}"
      )

      # Summary
      dist =
        freq_map
        |> Map.values()
        |> Enum.frequencies()
        |> Enum.sort_by(&elem(&1, 0))

      Mix.shell().info("Language distribution: #{inspect(dist)}")
    end
  end
end
