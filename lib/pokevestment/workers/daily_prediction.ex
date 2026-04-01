defmodule Pokevestment.Workers.DailyPrediction do
  @moduledoc """
  Oban worker for daily ML prediction pipeline.

  Runs after price sync (6 AM) and tournament sync (8 AM) to ensure
  fresh data. The pipeline is idempotent via upsert, so retries are safe.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

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
        if Regex.match?(@version_pattern, v), do: v, else: @default_version

      _ ->
        @default_version
    end
  end
end
