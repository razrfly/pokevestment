defmodule Pokevestment.Api.PokemonPriceTracker do
  @moduledoc """
  HTTP client for the PokemonPriceTracker API (https://www.pokemonpricetracker.com/api-docs).

  Provides TCGPlayer pricing with condition-level granularity, price history,
  and eBay graded sales data. Auth: Bearer token. Rate limit: 60 req/min.

  Credit costs:
  - Basic card data: 1 credit/card
  - Price history: +1 credit/card
  - eBay graded data: +1 credit/card

  Returns `{:ok, body, credits_meta}` on success to surface credit tracking.
  """

  @base_url "https://www.pokemonpricetracker.com/api/v2"
  @req_opts [retry: :transient, max_retries: 3]

  @doc """
  List all available sets.

  Returns `{:ok, [set], credits_meta}` or `{:error, reason}`.
  """
  def list_sets(opts \\ []) do
    params =
      [limit: Keyword.get(opts, :limit, 250)]
      |> maybe_add(:search, Keyword.get(opts, :search))
      |> maybe_add(:sortBy, Keyword.get(opts, :sort_by))
      |> maybe_add(:sortOrder, Keyword.get(opts, :sort_order))

    client()
    |> Req.get(url: "/sets", params: params)
    |> handle_response()
  end

  @doc """
  Fetch cards for a set by set name, with pagination.

  Options:
  - `:limit` — results per page (max 100, default 100)
  - `:offset` — pagination offset (default 0)
  - `:include_history` — add price history (+1 credit/card)
  - `:days` — history period (3-730, plan-dependent)
  - `:include_ebay` — add eBay graded data (+1 credit/card)

  Returns `{:ok, %{"data" => [cards], "metadata" => meta}, credits_meta}`.
  """
  def fetch_cards_for_set(set_name, opts \\ []) do
    params =
      [
        set: set_name,
        limit: Keyword.get(opts, :limit, 100),
        offset: Keyword.get(opts, :offset, 0)
      ]
      |> maybe_add(:includeHistory, Keyword.get(opts, :include_history))
      |> maybe_add(:days, Keyword.get(opts, :days))
      |> maybe_add(:includeEbay, Keyword.get(opts, :include_ebay))
      |> maybe_add(:fetchAllInSet, Keyword.get(opts, :fetch_all_in_set))

    client()
    |> Req.get(url: "/cards", params: params)
    |> handle_response()
  end

  @doc """
  Fetch a single card by TCGPlayer ID.

  Options: same as `fetch_cards_for_set/2`.

  Returns `{:ok, body, credits_meta}`.
  """
  def get_card(tcg_player_id, opts \\ []) do
    params =
      [tcgPlayerId: tcg_player_id]
      |> maybe_add(:includeHistory, Keyword.get(opts, :include_history))
      |> maybe_add(:days, Keyword.get(opts, :days))
      |> maybe_add(:includeEbay, Keyword.get(opts, :include_ebay))

    client()
    |> Req.get(url: "/cards", params: params)
    |> handle_response()
  end

  @doc """
  Search cards by query string.

  Returns `{:ok, body, credits_meta}`.
  """
  def search_cards(query, opts \\ []) do
    params =
      [
        search: query,
        limit: Keyword.get(opts, :limit, 100),
        offset: Keyword.get(opts, :offset, 0)
      ]
      |> maybe_add(:includeHistory, Keyword.get(opts, :include_history))
      |> maybe_add(:days, Keyword.get(opts, :days))

    client()
    |> Req.get(url: "/cards", params: params)
    |> handle_response()
  end

  # --- Private ---

  defp client do
    key = Application.get_env(:pokevestment, :pokemon_price_tracker_api_key)

    headers =
      case key do
        nil -> []
        "" -> []
        k -> [{"Authorization", "Bearer #{k}"}]
      end

    Req.new([base_url: @base_url, receive_timeout: 30_000, headers: headers] ++ @req_opts)
  end

  defp handle_response({:ok, %Req.Response{status: 429} = resp}) do
    retry_after =
      case Req.Response.get_header(resp, "retry-after") do
        [val | _] -> String.to_integer(val)
        _ -> 60
      end

    {:error, {:rate_limited, retry_after}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body} = resp})
       when status in 200..299 do
    credits = extract_credits_remaining(resp)
    {:ok, body, %{credits_remaining: credits}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, reason}) do
    {:error, reason}
  end

  defp extract_credits_remaining(resp) do
    case Req.Response.get_header(resp, "x-ratelimit-daily-remaining") do
      [val | _] ->
        case Integer.parse(val) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, _key, false), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)
end
