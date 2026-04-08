defmodule PokevestmentWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and deployment validation.
  """

  use PokevestmentWeb, :controller

  require Logger
  import Ecto.Query

  # 36 hours — missed a full day + 12h buffer
  @stale_threshold_hours 36

  def index(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban(),
      price_data: check_price_freshness(),
      predictions: check_prediction_freshness()
    }

    overall =
      if checks.database.status == "ok",
        do: :ok,
        else: :service_unavailable

    health_status = %{
      status: if(overall == :ok, do: "ok", else: "error"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:pokevestment, :vsn) |> to_string(),
      checks: checks
    }

    conn
    |> put_status(overall)
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
    e ->
      Logger.error("Health check oban failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      %{status: "not_running"}
  end

  defp check_price_freshness do
    sold_query = from(sp in "sold_prices", select: max(sp.snapshot_date))
    listing_query = from(lp in "listing_prices", select: max(lp.snapshot_date))

    sold_date = Pokevestment.Repo.one(sold_query)
    listing_date = Pokevestment.Repo.one(listing_query)

    latest_date =
      case {sold_date, listing_date} do
        {nil, nil} -> nil
        {nil, d} -> d
        {d, nil} -> d
        {s, l} -> if Date.compare(s, l) == :gt, do: s, else: l
      end

    case latest_date do
      nil ->
        %{status: "no_data", last_snapshot_date: nil, hours_since_last: nil}

      %Date{} = date ->
        hours_since = hours_since_date(date)
        status = if hours_since > @stale_threshold_hours, do: "stale", else: "ok"
        %{status: status, last_snapshot_date: Date.to_iso8601(date), hours_since_last: hours_since}
    end
  rescue
    e ->
      Logger.error("Health check price_data failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      %{status: "error"}
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
    e ->
      Logger.error("Health check predictions failed: #{Exception.format(:error, e, __STACKTRACE__)}")
      %{status: "error"}
  end

  defp hours_since_date(date) do
    now = DateTime.utc_now()
    midnight = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    DateTime.diff(now, midnight, :hour)
  end
end
