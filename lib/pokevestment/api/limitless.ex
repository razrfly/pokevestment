defmodule Pokevestment.Api.Limitless do
  @moduledoc """
  HTTP client for the Limitless TCG API (https://play.limitlesstcg.com/api).

  No authentication required. Keep concurrency conservative (~5) for fair use.
  """

  @base_url "https://play.limitlesstcg.com/api"

  @doc "List tournaments for a game (default: PTCG). API caps at 500 results."
  def list_tournaments(game \\ "PTCG") do
    client()
    |> Req.get(url: "/tournaments", params: [game: game, limit: 500])
    |> handle_response()
  end

  @doc "Get standings for a tournament by its external ID."
  def get_standings(tournament_id) do
    client()
    |> Req.get(url: "/tournaments/#{tournament_id}/standings")
    |> handle_response()
  end

  defp client do
    Req.new(
      base_url: @base_url,
      retry: :transient,
      max_retries: 3,
      receive_timeout: 30_000
    )
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end
end
