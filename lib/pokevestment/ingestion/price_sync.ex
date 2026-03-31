defmodule Pokevestment.Ingestion.PriceSync do
  @moduledoc """
  Daily price sync orchestrator — fetches current prices for all cards and
  inserts new PriceSnapshot rows. Decoupled from Oban for testability and
  reuse from mix tasks.

  Idempotent: `on_conflict: :nothing` means re-running on the same day
  inserts 0 new rows.
  """

  require Logger

  import Pokevestment.Helpers, only: [format_duration: 1]

  alias Pokevestment.Repo
  alias Pokevestment.Api.Tcgdex
  alias Pokevestment.Ingestion.Transformer
  alias Pokevestment.Pricing.PriceSnapshot

  @doc """
  Run a full price sync for all cards.

  Returns `{:ok, summary}` or `{:error, reason}`.

  Summary keys: `:total`, `:processed`, `:snapshots_inserted`, `:failed`, `:exit_count`, `:elapsed_ms`.
  """
  def run do
    start = System.monotonic_time(:millisecond)
    Logger.info("PriceSync: starting daily price sync...")

    with {:ok, raw_cards} <- Tcgdex.list_cards() do
      card_ids = Enum.map(raw_cards, & &1["id"])
      total = length(card_ids)
      Logger.info("PriceSync: fetching prices for #{total} cards...")

      counter = :counters.new(1, [:atomics])

      {snapshots_inserted, failed, exit_count} =
        card_ids
        |> Task.async_stream(
          fn card_id -> {card_id, sync_card(card_id)} end,
          max_concurrency: 10,
          timeout: 120_000,
          on_timeout: :kill_task,
          ordered: false
        )
        |> Enum.reduce({0, [], 0}, fn result, {inserted, failed_ids, exits} ->
          :counters.add(counter, 1, 1)
          processed = :counters.get(counter, 1)

          if rem(processed, 500) == 0 do
            elapsed = System.monotonic_time(:millisecond) - start
            rate = Float.round(processed / (elapsed / 1_000), 1)
            pct = Float.round(processed / total * 100, 1)
            Logger.info("PriceSync: #{processed}/#{total} (#{pct}%) — #{rate} cards/s")
          end

          case result do
            {:ok, {_card_id, {:ok, count}}} ->
              {inserted + count, failed_ids, exits}

            {:ok, {card_id, {:error, _card_id, _reason}}} ->
              {inserted, [card_id | failed_ids], exits}

            {:exit, reason} ->
              Logger.warning("PriceSync: task exited: #{inspect(reason)}")
              {inserted, failed_ids, exits + 1}
          end
        end)

      elapsed_ms = System.monotonic_time(:millisecond) - start
      processed = :counters.get(counter, 1)

      failure_total = length(failed) + exit_count

      Logger.info(
        "PriceSync: complete in #{format_duration(elapsed_ms)} — " <>
          "#{processed}/#{total} processed, #{snapshots_inserted} snapshots inserted, " <>
          "#{failure_total} failed" <>
          if(exit_count > 0, do: " (#{exit_count} timed out)", else: "")
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
         exit_count: exit_count,
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

  defp insert_snapshots([]), do: 0

  defp insert_snapshots(snapshots) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {valid_rows, invalid_count} =
      Enum.reduce(snapshots, {[], 0}, fn attrs, {rows, bad} ->
        changeset = PriceSnapshot.changeset(%PriceSnapshot{}, attrs)

        if changeset.valid? do
          row = Map.merge(attrs, %{inserted_at: now})
          {[row | rows], bad}
        else
          Logger.warning(
            "PriceSync: dropping invalid snapshot for card #{attrs[:card_id]}: " <>
              "#{inspect(changeset.errors)}"
          )

          {rows, bad + 1}
        end
      end)

    if invalid_count > 0 do
      Logger.warning("PriceSync: skipped #{invalid_count} invalid snapshots in batch")
    end

    case valid_rows do
      [] ->
        0

      rows ->
        {count, _} =
          Repo.insert_all(PriceSnapshot, Enum.reverse(rows),
            on_conflict: :nothing,
            conflict_target: [:card_id, :source, :variant, :snapshot_date]
          )

        count
    end
  end
end
