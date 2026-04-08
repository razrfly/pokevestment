defmodule Pokevestment.Pricing.ExchangeRateTest do
  use ExUnit.Case, async: false

  alias Pokevestment.Pricing.ExchangeRate

  setup do
    # Ensure ETS table exists and clear any cached rate
    ExchangeRate.init()

    if :ets.whereis(:exchange_rates) != :undefined do
      :ets.delete_all_objects(:exchange_rates)
    end

    :ok
  end

  describe "convert_to_usd/2" do
    test "USD passthrough returns amount unchanged with rate 1" do
      amount = Decimal.new("90.00")
      {price_usd, rate, date} = ExchangeRate.convert_to_usd(amount, "USD")

      assert price_usd == amount
      assert rate == Decimal.new(1)
      assert date == Date.utc_today()
    end

    test "EUR conversion uses cached rate" do
      rate = Decimal.from_float(1.08)
      date = ~D[2026-04-07]
      :ets.insert(:exchange_rates, {:eur_usd, rate, date})

      amount = Decimal.new("45.00")
      {price_usd, returned_rate, returned_date} = ExchangeRate.convert_to_usd(amount, "EUR")

      expected = Decimal.new("48.60")
      assert Decimal.eq?(price_usd, expected)
      assert returned_rate == rate
      assert returned_date == date
    end

    test "EUR conversion returns nil tuple when no rate cached" do
      amount = Decimal.new("45.00")
      assert {nil, nil, nil} = ExchangeRate.convert_to_usd(amount, "EUR")
    end

    test "nil amount returns nil tuple" do
      assert {nil, nil, nil} = ExchangeRate.convert_to_usd(nil, "USD")
      assert {nil, nil, nil} = ExchangeRate.convert_to_usd(nil, "EUR")
    end

    test "nil currency returns nil tuple" do
      assert {nil, nil, nil} = ExchangeRate.convert_to_usd(Decimal.new("10.00"), nil)
    end

    test "unknown currency returns nil tuple" do
      assert {nil, nil, nil} = ExchangeRate.convert_to_usd(Decimal.new("10.00"), "GBP")
    end
  end

  describe "get_eur_to_usd/0" do
    test "returns {nil, nil} when no rate cached" do
      assert {nil, nil} = ExchangeRate.get_eur_to_usd()
    end

    test "returns cached rate and date" do
      rate = Decimal.from_float(1.08)
      date = ~D[2026-04-07]
      :ets.insert(:exchange_rates, {:eur_usd, rate, date})

      assert {^rate, ^date} = ExchangeRate.get_eur_to_usd()
    end
  end

  describe "init/0" do
    test "is idempotent" do
      assert :ok = ExchangeRate.init()
      assert :ok = ExchangeRate.init()
    end
  end
end
