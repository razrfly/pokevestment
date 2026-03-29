defmodule Pokevestment.Workers.DailyPriceSync do
  @moduledoc """
  Oban worker for daily price synchronization from TCGdex API.

  Runs daily at 2 AM UTC. Delegates to `PriceSync.run/0` for the actual work.

  - `list_cards/0` failure → returns error → Oban retries (up to 3 attempts)
  - Individual card failures within a run don't trigger retry — partial success is still `:ok`
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  alias Pokevestment.Ingestion.PriceSync

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case PriceSync.run() do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
