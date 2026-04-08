defmodule Pokevestment.Pricing.ExchangeRate do
  @moduledoc """
  Caches and provides EUR/USD exchange rate lookups via ETS.

  Call `fetch_and_cache/0` once at the start of each sync run.
  Use `convert_to_usd/2` to normalize prices to USD.
  """

  require Logger

  alias Pokevestment.Api.ECB

  @ets_table :exchange_rates

  @doc """
  Ensures the ETS table exists. Called from application startup.
  """
  def init do
    :ets.new(@ets_table, [:named_table, :set, :public, read_concurrency: true])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Fetches the latest EUR/USD rate from ECB and caches it in ETS.

  Returns `{:ok, %{rate: Decimal, date: Date}}` or `{:error, reason}`.
  """
  def fetch_and_cache do
    init()

    case ECB.fetch_eur_usd_rate() do
      {:ok, %{rate: rate, date: date} = result} ->
        :ets.insert(@ets_table, {:eur_usd, rate, date})
        Logger.info("[ExchangeRate] Cached EUR/USD rate: #{rate} (#{date})")
        {:ok, result}

      {:error, reason} = error ->
        Logger.warning("[ExchangeRate] Failed to fetch rate: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Returns the cached EUR/USD rate as `{rate, date}` or `{nil, nil}` if unavailable.
  """
  def get_eur_to_usd do
    init()

    case :ets.lookup(@ets_table, :eur_usd) do
      [{:eur_usd, rate, date}] -> {rate, date}
      [] -> {nil, nil}
    end
  end

  @doc """
  Converts a price to USD given its original currency.

  Returns `{price_usd, exchange_rate, exchange_rate_date}`.
  - USD input: passthrough with rate=1
  - EUR input: multiplied by cached rate
  - Unknown/nil rate: returns `{nil, nil, nil}` (doesn't block ingestion)
  """
  def convert_to_usd(nil, _currency), do: {nil, nil, nil}
  def convert_to_usd(_amount, nil), do: {nil, nil, nil}

  def convert_to_usd(amount, "USD") do
    {amount, Decimal.new(1), Date.utc_today()}
  end

  def convert_to_usd(amount, "EUR") do
    case get_eur_to_usd() do
      {nil, _} ->
        {nil, nil, nil}

      {rate, date} ->
        price_usd = Decimal.mult(amount, rate) |> Decimal.round(2)
        {price_usd, rate, date}
    end
  end

  def convert_to_usd(_amount, _other_currency), do: {nil, nil, nil}
end
