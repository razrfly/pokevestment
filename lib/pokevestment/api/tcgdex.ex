defmodule Pokevestment.Api.Tcgdex do
  @moduledoc """
  HTTP client for the TCGdex API (https://api.tcgdex.net/v2/en).

  No authentication or rate limits required.
  """

  @base_url "https://api.tcgdex.net/v2/en"
  @req_opts [retry: :transient, max_retries: 3]

  @doc "List all series (~21 items)."
  def list_series, do: client() |> Req.get(url: "/series") |> handle_response()

  @doc "List all sets with basic info (~200 items)."
  def list_sets, do: client() |> Req.get(url: "/sets") |> handle_response()

  @doc "Get full detail for a single set."
  def get_set(id), do: client() |> Req.get(url: "/sets/#{id}") |> handle_response()

  @doc "List all cards with basic info (~22,755 items)."
  def list_cards, do: client() |> Req.get(url: "/cards") |> handle_response()

  @doc "Get full detail for a single card including pricing."
  def get_card(id), do: client() |> Req.get(url: "/cards/#{id}") |> handle_response()

  # 6 Western languages that share identical card IDs across TCGdex.
  # Japanese is excluded: TCGdex uses entirely different set codes and card IDs
  # for Japanese cards (e.g. SV1a-001 vs sv01-001), with no reliable mapping.
  @languages ~w(en fr de it es pt)

  @doc """
  List all card IDs for a given language endpoint.

  Supported languages: #{Enum.join(@languages, ", ")}
  """
  def list_cards_for_language(lang) when lang in @languages do
    Req.new(
      [base_url: "https://api.tcgdex.net/v2/#{lang}", receive_timeout: 60_000] ++ @req_opts
    )
    |> Req.get(url: "/cards")
    |> handle_response()
  end

  defp client do
    Req.new([base_url: @base_url, receive_timeout: 30_000] ++ @req_opts)
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
