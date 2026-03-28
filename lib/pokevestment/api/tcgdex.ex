defmodule Pokevestment.Api.Tcgdex do
  @moduledoc """
  Tesla HTTP client for the TCGdex API (https://api.tcgdex.net/v2/en).

  No authentication or rate limits required.
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.tcgdex.net/v2/en"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger
  plug Tesla.Middleware.Retry, delay: 500, max_retries: 3, max_delay: 4_000
  plug Tesla.Middleware.Timeout, timeout: 30_000

  @doc "List all series (~21 items)."
  def list_series, do: "/series" |> get() |> handle_response()

  @doc "List all sets with basic info (~200 items)."
  def list_sets, do: "/sets" |> get() |> handle_response()

  @doc "Get full detail for a single set."
  def get_set(id), do: "/sets/#{id}" |> get() |> handle_response()

  @doc "List all cards with basic info (~22,755 items)."
  def list_cards, do: "/cards" |> get() |> handle_response()

  @doc "Get full detail for a single card including pricing."
  def get_card(id), do: "/cards/#{id}" |> get() |> handle_response()

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
