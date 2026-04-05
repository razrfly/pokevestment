defmodule PokevestmentWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and deployment validation.
  """

  use PokevestmentWeb, :controller

  import Ecto.Query

  # 36 hours — missed a full day + 12h buffer
  @stale_threshold_hours 36

  def index(conn, _params) do
    health_status = %{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:pokevestment, :vsn) |> to_string(),
      checks: %{
        database: check_database(),
        oban: check_oban(),
        price_data: check_price_freshness(),
        predictions: check_prediction_freshness()
      }
    }

    conn
    |> put_status(:ok)
    |> json(health_status)
  end

  defp check_database do
    case Ecto.Adapters.SQL.query(Pokevestment.Repo, "SELECT 1", []) do
      {:ok, _} -> %{status: "ok"}
      {:error, _} -> %{status: "error"}
    end
  end

  defp check_oban do
    case Oban.config() do
      %Oban.Config{} -> %{status: "ok"}
      _ -> %{status: "not_configured"}
    end
  rescue
    _ -> %{status: "not_running"}
  end

  defp check_price_freshness do
    query = from(ps in "price_snapshots", select: max(ps.snapshot_date))

    case Pokevestment.Repo.one(query) do
      nil ->
        %{status: "no_data", last_snapshot_date: nil, hours_since_last: nil}

      %Date{} = date ->
        hours_since = hours_since_date(date)
        status = if hours_since > @stale_threshold_hours, do: "stale", else: "ok"
        %{status: status, last_snapshot_date: Date.to_iso8601(date), hours_since_last: hours_since}
    end
  rescue
    _ -> %{status: "error"}
  end

  defp check_prediction_freshness do
    query =
      from(cp in "card_predictions",
        select: %{latest_date: max(cp.prediction_date), count: count(cp.card_id)}
      )

    case Pokevestment.Repo.one(query) do
      %{latest_date: nil} ->
        %{status: "no_data", last_prediction_date: nil, prediction_count: 0, hours_since_last: nil}

      %{latest_date: %Date{} = date, count: count} ->
        hours_since = hours_since_date(date)
        status = if hours_since > @stale_threshold_hours, do: "stale", else: "ok"

        %{
          status: status,
          last_prediction_date: Date.to_iso8601(date),
          prediction_count: count,
          hours_since_last: hours_since
        }
    end
  rescue
    _ -> %{status: "error"}
  end

  defp hours_since_date(date) do
    now = DateTime.utc_now()
    midnight = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    DateTime.diff(now, midnight, :hour)
  end
end
