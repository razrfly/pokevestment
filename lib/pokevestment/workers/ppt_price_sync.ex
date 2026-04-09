defmodule Pokevestment.Workers.PptPriceSync do
  @moduledoc """
  Oban worker for daily PokemonPriceTracker price synchronization.

  Runs at 7:15 AM UTC — after DailyPriceSync (6 AM), CardDetailBackfill (6:30 AM),
  and DataQualityCheck (7 AM). Before TournamentSync (8 AM).

  Syncs the 10 priority sets (737 cards with zero TCGPlayer data from other sources)
  daily. Expand to full rotation via PptBackfill.run/1 after upgrading to paid plan.
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  require Logger

  alias Pokevestment.Ingestion.PptBackfill

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("[PptPriceSync] Starting daily PPT sync for priority sets...")

    {:ok, summary} = PptBackfill.run_priority_sets()

    Logger.info(
      "[PptPriceSync] Complete: #{summary.inserted} prices upserted, " <>
        "#{summary.sets_processed} sets, #{length(summary.errors)} errors"
    )

    cond do
      summary.sets_processed == 0 and length(summary.errors) > 0 ->
        # All sets failed — trigger Oban retry
        {:error, "All sets failed: #{inspect(Enum.take(summary.errors, 3))}"}

      summary.inserted == 0 and summary.sets_processed > 0 ->
        # Sets processed but zero prices inserted — likely auth or data issue
        Logger.warning("[PptPriceSync] Zero prices inserted despite processing #{summary.sets_processed} sets")
        :ok

      true ->
        :ok
    end
  end
end
