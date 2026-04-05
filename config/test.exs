import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pokevestment, Pokevestment.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pokevestment_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pokevestment, PokevestmentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "i52ddSSAUMEIb4kVrsZygrfw9TPDp69Ybt7ditwNW5bSNhCcF1Q1UvdVN/d60NhJ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable Oban during tests - use manual testing mode
config :pokevestment, Oban,
  testing: :manual,
  queues: false,
  plugins: false

# Disable basic auth on admin routes so tests can hit them directly
config :pokevestment, admin_auth_disabled: true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
