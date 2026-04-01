defmodule Pokevestment.Workers.DailyPrediction do
  @moduledoc """
  Oban worker for daily ML prediction pipeline.

  Runs after price sync (6 AM) and tournament sync (8 AM) to ensure
  fresh data. The pipeline is idempotent via upsert, so retries are safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias Pokevestment.ML.Pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    version =
      Map.get(args, "version") ||
        Application.get_env(:pokevestment, :model_version, "v1.0.0")

    case Pipeline.run(version: version) do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
