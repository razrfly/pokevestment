# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pokevestment,
  ecto_repos: [Pokevestment.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :pokevestment, PokevestmentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PokevestmentWeb.ErrorHTML, json: PokevestmentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pokevestment.PubSub,
  live_view: [signing_salt: "C8/Xm3O7"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Oban for background job processing
config :pokevestment, Oban,
  repo: Pokevestment.Repo,
  queues: [default: 10, ingestion: 5],
  plugins: [
    # Prune completed jobs after 7 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Cron-based scheduled jobs (configured per environment)
    {Oban.Plugins.Cron,
     crontab: [
       # Daily price sync at 6 AM UTC
       {"0 6 * * *", Pokevestment.Workers.DailyPriceSync, queue: :ingestion},
       # Daily data quality check at 7 AM UTC (after prices, before tournaments)
       {"0 7 * * *", Pokevestment.Workers.DataQualityCheck},
       # Daily tournament sync at 8 AM UTC
       {"0 8 * * *", Pokevestment.Workers.TournamentSync, queue: :ingestion},
       # Daily ML prediction pipeline at 9 AM UTC (after prices + tournaments)
       {"0 9 * * *", Pokevestment.Workers.DailyPrediction},
       # Daily outcome evaluation at 10 AM UTC (after predictions)
       {"0 10 * * *", Pokevestment.Workers.OutcomeEvaluator}
     ]}
  ]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.0",
  pokevestment: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.0",
  pokevestment: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
