defmodule Pokevestment.Workers.DailyPrediction do
  @moduledoc """
  Oban worker for daily ML prediction pipeline.

  Runs after price sync (6 AM) and tournament sync (8 AM) to ensure
  fresh data. The pipeline is idempotent via upsert, so retries are safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Pokevestment.ML.Pipeline

  @version_pattern ~r/^v\d+\.\d+\.\d+(-[\w.]+)?$/

  @default_version "v1.0.0"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, version} <- resolve_version(args) do
      case Pipeline.run(version: version) do
        {:ok, _summary} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} ->
        Logger.warning("DailyPrediction discarding job: #{reason}")
        {:discard, reason}
    end
  end

  defp resolve_version(args) do
    case Map.get(args, "version") do
      v when is_binary(v) and v != "" ->
        if Regex.match?(@version_pattern, v),
          do: {:ok, v},
          else: {:error, "invalid model version format: #{inspect(v)}"}

      _ ->
        {:ok, validated_default()}
    end
  end

  defp validated_default do
    case Application.get_env(:pokevestment, :model_version, @default_version) do
      v when is_binary(v) ->
        if Regex.match?(@version_pattern, v) do
          v
        else
          Logger.warning("Invalid :model_version config #{inspect(v)}, using #{@default_version}")
          @default_version
        end

      _ ->
        @default_version
    end
  end
end
