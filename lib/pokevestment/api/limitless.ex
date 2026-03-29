defmodule Pokevestment.Api.Limitless do
  @moduledoc """
  Tesla HTTP client for the Limitless TCG API (https://play.limitlesstcg.com/api).

  No authentication required. Keep concurrency conservative (~5) for fair use.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://play.limitlesstcg.com/api"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger
  plug Tesla.Middleware.Retry, delay: 500, max_retries: 3, max_delay: 4_000
  plug Tesla.Middleware.Timeout, timeout: 30_000

  @doc "List tournaments for a game (default: PTCG). Returns list of tournament objects."
  def list_tournaments(game \\ "PTCG") do
    "/tournaments"
    |> get(query: [game: game])
    |> handle_response()
  end

  @doc "Get standings for a tournament by its external ID."
  def get_standings(tournament_id) do
    "/tournaments/#{tournament_id}/standings"
    |> get()
    |> handle_response()
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Tesla.Env{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end
end
