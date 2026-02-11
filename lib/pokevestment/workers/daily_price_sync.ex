defmodule Pokevestment.Workers.DailyPriceSync do
  @moduledoc """
  Oban worker for daily price synchronization from Pokemon TCG API.

  This worker runs daily at 2 AM UTC to:
  1. Fetch current prices for all cards
  2. Record price snapshots in the price_history table
  3. Handle variant-specific pricing (holofoil, reverse, normal)

  Actual implementation will be added in Phase 1.4.
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: _args}) do
    # TODO: Implement in Phase 1.4
    # 1. Fetch all cards with prices from Pokemon TCG API
    # 2. For each card, insert price_history record
    # 3. Handle rate limiting with exponential backoff

    :ok
  end
end
