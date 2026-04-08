defmodule Pokevestment.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS table for exchange rate caching
    Pokevestment.Pricing.ExchangeRate.init()

    children = [
      PokevestmentWeb.Telemetry,
      Pokevestment.Repo,
      {DNSCluster, query: Application.get_env(:pokevestment, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pokevestment.PubSub},
      # Oban for background job processing
      {Oban, Application.fetch_env!(:pokevestment, Oban)},
      # Start to serve requests, typically the last entry
      PokevestmentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pokevestment.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PokevestmentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
