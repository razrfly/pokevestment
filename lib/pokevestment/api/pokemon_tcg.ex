defmodule Pokevestment.Api.PokemonTcg do
  @moduledoc """
  HTTP client for the Pokemon TCG API (https://api.pokemontcg.io/v2).

  Used for fetching TCGPlayer and CardMarket pricing data in bulk (per-set)
  instead of per-card requests. Auth key is optional but recommended for
  higher rate limits.
  """

  @base_url "https://api.pokemontcg.io/v2"
  @req_opts [retry: :transient, max_retries: 3]

  @doc "List all sets with id, name, and ptcgoCode."
  def list_sets do
    client()
    |> Req.get(url: "/sets", params: [select: "id,name,ptcgoCode", pageSize: 250])
    |> handle_response()
    |> case do
      {:ok, %{"data" => data}} -> {:ok, data}
      {:ok, other} -> {:ok, other}
      error -> error
    end
  end

  @doc """
  List all cards for a given set with pricing data.
  Handles pagination for large sets (>250 cards).
  """
  def list_cards_for_set(set_id) do
    fetch_all_pages(set_id, 1, [])
  end

  defp fetch_all_pages(set_id, page, acc) do
    params = [
      q: "set.id:#{set_id}",
      select: "id,number,tcgplayer,cardmarket",
      pageSize: 250,
      page: page
    ]

    case client() |> Req.get(url: "/cards", params: params) |> handle_response() do
      {:ok, %{"data" => data, "totalCount" => total}} ->
        all = acc ++ data
        fetched = page * 250

        if fetched < total do
          fetch_all_pages(set_id, page + 1, all)
        else
          {:ok, all}
        end

      {:ok, %{"data" => data}} ->
        {:ok, acc ++ data}

      error ->
        error
    end
  end

  defp client do
    headers =
      case Application.get_env(:pokevestment, :pokemon_tcg_api_key) do
        nil -> []
        "" -> []
        key -> [{"X-Api-Key", key}]
      end

    Req.new([base_url: @base_url, receive_timeout: 30_000, headers: headers] ++ @req_opts)
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
