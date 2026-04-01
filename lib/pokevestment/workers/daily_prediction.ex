defmodule Pokevestment.Workers.DailyPrediction do
  @moduledoc """
  Oban worker for daily ML prediction pipeline.

  Runs after price sync (6 AM) and tournament sync (8 AM) to ensure
  fresh data. The pipeline is idempotent via upsert, so retries are safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias Pokevestment.ML.Pipeline

  @version_pattern ~r/^v\d+\.\d+\.\d+(-[\w.]+)?$/

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    version =
      case Map.get(args, "version") do
        v when is_binary(v) and v != "" ->
          if Regex.match?(@version_pattern, v),
            do: v,
            else: default_version()

        _ ->
          default_version()
      end

    case Pipeline.run(version: version) do
      {:ok, _summary} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_version do
    Application.get_env(:pokevestment, :model_version, "v1.0.0")
  end
end
