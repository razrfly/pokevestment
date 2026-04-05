defmodule Pokevestment.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :pokevestment

  def migrate do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
        {:ok, _, _} ->
          IO.puts("Migrations successful for #{inspect(repo)}")

        {:error, reason} ->
          IO.warn("Migration failed for #{inspect(repo)}: #{inspect(reason)}")
          raise "Migration failed for #{inspect(repo)}"
      end
    end

    :ok
  end

  def rollback(repo, version) do
    load_app()

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, _, _} ->
        IO.puts("Rollback to version #{version} successful for #{inspect(repo)}")
        :ok

      {:error, reason} ->
        IO.warn("Rollback failed for #{inspect(repo)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    case Application.load(@app) do
      :ok ->
        :ok

      {:error, {:already_loaded, @app}} ->
        :ok

      {:error, reason} ->
        raise "Failed to load application: #{inspect(reason)}"
    end
  end
end
