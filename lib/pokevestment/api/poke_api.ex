defmodule Pokevestment.Api.PokeApi do
  @moduledoc """
  Tesla HTTP client for PokeAPI (https://pokeapi.co/api/v2).

  No authentication required. Fair use: keep concurrency low (~3).
  """

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://pokeapi.co/api/v2"
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Logger
  plug Tesla.Middleware.Retry, delay: 1_000, max_retries: 3, max_delay: 8_000
  plug Tesla.Middleware.Timeout, timeout: 15_000

  @doc "Get a Pokemon species by ID or name."
  def get_species(id_or_name), do: "/pokemon-species/#{id_or_name}" |> get() |> handle_response()

  @doc "Get a Pokemon by ID or name (for sprites)."
  def get_pokemon(id_or_name), do: "/pokemon/#{id_or_name}" |> get() |> handle_response()

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
