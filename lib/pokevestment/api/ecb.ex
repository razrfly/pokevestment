defmodule Pokevestment.Api.ECB do
  @moduledoc """
  HTTP client for the European Central Bank Data API.

  Fetches the latest EUR/USD exchange rate from ECB's public CSV endpoint.
  No authentication required.
  """

  require Logger

  @base_url "https://data-api.ecb.europa.eu/service/data/EXR/D.USD.EUR.SP00.A"
  @req_opts [retry: :transient, max_retries: 3, receive_timeout: 15_000]

  @doc """
  Fetch the latest daily EUR/USD exchange rate.

  Returns `{:ok, %{rate: Decimal.t(), date: Date.t()}}` or `{:error, reason}`.
  """
  def fetch_eur_usd_rate do
    url = @base_url <> "?lastNObservations=1&format=csvdata"

    case Req.get(url, @req_opts) do
      {:ok, %{status: 200, body: body}} ->
        parse_csv_rate(body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_csv_rate(body) when is_binary(body) do
    lines = String.split(body, "\n", trim: true)

    case lines do
      [header | [data_line | _]] ->
        headers = String.split(header, ",")
        values = String.split(data_line, ",")

        header_value_map =
          Enum.zip(headers, values)
          |> Map.new()

        rate_str = Map.get(header_value_map, "OBS_VALUE")
        date_str = Map.get(header_value_map, "TIME_PERIOD")

        with rate_str when is_binary(rate_str) <- rate_str,
             date_str when is_binary(date_str) <- date_str,
             {rate_float, _} <- Float.parse(rate_str),
             {:ok, date} <- Date.from_iso8601(date_str) do
          {:ok, %{rate: Decimal.from_float(rate_float), date: date}}
        else
          _ ->
            Logger.warning("[ECB] Failed to parse rate from CSV: #{inspect({rate_str, date_str})}")
            {:error, :parse_error}
        end

      _ ->
        {:error, :unexpected_format}
    end
  end

  defp parse_csv_rate(_), do: {:error, :unexpected_format}
end
