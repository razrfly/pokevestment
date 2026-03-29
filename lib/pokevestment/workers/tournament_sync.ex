defmodule Pokevestment.Workers.TournamentSync do
  @moduledoc """
  Oban worker for daily tournament data synchronization from Limitless TCG API.

  Runs on a daily cron schedule. Delegates to `TournamentImport.run/1` for the actual work.

  - API failure → returns error → Oban retries (up to 3 attempts)
  - Individual tournament failures within a run don't trigger retry — partial success is still `:ok`
  """

  use Oban.Worker, queue: :ingestion, max_attempts: 3

  alias Pokevestment.Ingestion.TournamentImport

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case TournamentImport.run(format: "STANDARD") do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
