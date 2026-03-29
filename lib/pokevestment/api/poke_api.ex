defmodule Pokevestment.Api.PokeApi do
  @moduledoc """
  HTTP client for PokeAPI (https://pokeapi.co/api/v2).

  No authentication required. Fair use: keep concurrency low (~3).
  """

  @base_url "https://pokeapi.co/api/v2"

  @doc "Get a Pokemon species by ID or name."
  def get_species(id_or_name) do
    client() |> Req.get(url: "/pokemon-species/#{id_or_name}") |> handle_response()
  end

  @doc "Get a Pokemon by ID or name (for sprites)."
  def get_pokemon(id_or_name) do
    client() |> Req.get(url: "/pokemon/#{id_or_name}") |> handle_response()
  end

  defp client do
    Req.new(
      base_url: @base_url,
      retry: :transient,
      max_retries: 3,
      receive_timeout: 15_000
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
