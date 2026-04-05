defmodule Pokevestment.Workers.DailyPriceSync do
  @moduledoc """
  Oban worker for daily price synchronization via the Pokemon TCG API.

  Runs on a daily cron schedule. Delegates to `PriceSync.run/0` for the actual work.

  - SetMapping or API failure → returns error → Oban retries (up to 3 attempts)
  - Individual set failures within a run don't trigger retry — partial success is still `:ok`
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
