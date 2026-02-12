defmodule PokevestmentWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and deployment validation.
  """

  use PokevestmentWeb, :controller

  def index(conn, _params) do
    health_status = %{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:pokevestment, :vsn) |> to_string(),
      checks: %{
        database: check_database(),
        oban: check_oban()
      }
    }

    conn
    |> put_status(:ok)
    |> json(health_status)
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Pokevestment.Repo, "SELECT 1", []) do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  end

  defp check_oban do
    # Check if Oban is running by checking its config
    case Oban.config() do
      %Oban.Config{} -> "ok"
      _ -> "not_configured"
    end
  rescue
    _ -> "not_running"
  end
end
