defmodule Pokevestment.Ingestion.PriceSync do
  @moduledoc """
  Daily price sync orchestrator — fetches current prices for all cards and
  inserts new PriceSnapshot rows. Decoupled from Oban for testability and
  reuse from mix tasks.

  Idempotent: `on_conflict: :nothing` means re-running on the same day
  inserts 0 new rows.
  """

  require Logger

  alias Pokevestment.Repo
  alias Pokevestment.Api.Tcgdex
  alias Pokevestment.Ingestion.Transformer
  alias Pokevestment.Pricing.PriceSnapshot

  @doc """
  Run a full price sync for all cards.

  Returns `{:ok, summary}` or `{:error, reason}`.

  Summary keys: `:total`, `:processed`, `:snapshots_inserted`, `:failed`, `:elapsed_ms`.
  """
  def run do
    start = System.monotonic_time(:millisecond)
    Logger.info("PriceSync: starting daily price sync...")

    with {:ok, raw_cards} <- Tcgdex.list_cards() do
      card_ids = Enum.map(raw_cards, & &1["id"])
      total = length(card_ids)
      Logger.info("PriceSync: fetching prices for #{total} cards...")

      counter = :counters.new(1, [:atomics])

      {snapshots_inserted, failed} =
        card_ids
        |> Task.async_stream(
          fn card_id -> sync_card(card_id) end,
          max_concurrency: 10,
          timeout: 120_000,
          ordered: false
        )
        |> Enum.reduce({0, []}, fn result, {inserted, failed_ids} ->
          :counters.add(counter, 1, 1)
          processed = :counters.get(counter, 1)

          if rem(processed, 500) == 0 do
            elapsed = System.monotonic_time(:millisecond) - start
            rate = Float.round(processed / (elapsed / 1_000), 1)
            pct = Float.round(processed / total * 100, 1)
            Logger.info("PriceSync: #{processed}/#{total} (#{pct}%) — #{rate} cards/s")
          end

          case result do
            {:ok, {:ok, count}} ->
              {inserted + count, failed_ids}

            {:ok, {:error, card_id, _reason}} ->
              {inserted, [card_id | failed_ids]}

            {:exit, _reason} ->
              {inserted, failed_ids}
          end
        end)

      elapsed_ms = System.monotonic_time(:millisecond) - start
      processed = :counters.get(counter, 1)

      Logger.info(
        "PriceSync: complete in #{format_duration(elapsed_ms)} — " <>
          "#{processed}/#{total} processed, #{snapshots_inserted} snapshots inserted, " <>
          "#{length(failed)} failed"
      )

      if failed != [] do
        Logger.warning("PriceSync: failed card IDs: #{Enum.join(Enum.take(failed, 20), ", ")}")
      end

      {:ok,
       %{
         total: total,
         processed: processed,
         snapshots_inserted: snapshots_inserted,
         failed: failed,
         elapsed_ms: elapsed_ms
       }}
    end
  end

  defp sync_card(card_id) do
    case Tcgdex.get_card(card_id) do
      {:ok, raw} ->
        snapshots = Transformer.build_price_snapshots(card_id, raw["pricing"])
        inserted = insert_snapshots(snapshots)
        {:ok, inserted}

      {:error, reason} ->
        Logger.warning("PriceSync: failed to fetch card #{card_id}: #{inspect(reason)}")
        {:error, card_id, reason}
    end
  end

  defp insert_snapshots(snapshots) do
    Enum.reduce(snapshots, 0, fn attrs, acc ->
      case %PriceSnapshot{}
           |> PriceSnapshot.changeset(attrs)
           |> Repo.insert(
             on_conflict: :nothing,
             conflict_target: [:card_id, :source, :variant, :snapshot_date]
           ) do
        {:ok, %{id: id}} when not is_nil(id) -> acc + 1
        _ -> acc
      end
    end)
  end

  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
