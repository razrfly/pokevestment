# Pokevestment

ML-powered Pokemon TCG price prediction platform. Ingests card data, pricing, tournament results, and Pokemon metadata to build features for price movement prediction.

## Getting Started

### Prerequisites

- **Elixir 1.15+** and **Erlang/OTP** — [asdf](https://asdf-vm.com/) or [mise](https://mise.jdx.dev/) recommended for version management
- **PostgreSQL** running locally with default `postgres/postgres` superuser
- **No API keys needed** — all three data sources (TCGdex, PokeAPI, Limitless TCG) are unauthenticated

### Clone & Initialize

```bash
git clone <repo-url> && cd pokevestment
mix setup
```

`mix setup` runs: `deps.get` → `ecto.create` → `ecto.migrate` → `seeds.exs`. This creates an empty database with schema only — no card, price, or tournament data yet.

### Load Data (first time)

Run these in order — each step depends on the previous:

```bash
# 1. Import all card data + initial prices
#    Hits TCGdex + PokeAPI live, ~23K HTTP calls, ~45 min, requires internet
#    Imports: series → sets → species → cards with day-0 price snapshots
mix pokevestment.import

# 2. Compute ML features from card JSONB data (~10 sec, no network)
mix pokevestment.backfill_features

# 3. Compute art type features from rarity (~10 sec, no network)
mix pokevestment.backfill_art_types

# 4. Import tournament data from Limitless TCG
#    Hits Limitless live, rate-limited (~7s/tournament), ~4 min for ~37 tournaments
#    Links deck cards to cards table via PTCGO code mapping
mix pokevestment.import_tournaments
```

All tasks are idempotent — safe to re-run if interrupted. Already-imported data is skipped via `on_conflict: :nothing`.

### Verify the Load

After all four steps complete, expected row counts:

| Table | Expected Rows |
|---|---|
| series | 21 |
| sets | 200 |
| cards | 22,754 |
| card_types | 19,435 |
| card_dex_ids | 16,953 |
| pokemon_species | 1,025 |
| price_snapshots | 62K+ |
| tournaments | 37+ |
| tournament_standings | 1,713+ |
| tournament_deck_cards | 32,560+ |

Quick verification:

```bash
# Start the app to confirm everything works
mix phx.server         # Phoenix at localhost:4006

# Or check row counts in iex
iex -S mix
iex> Pokevestment.Repo.aggregate(Pokevestment.Cards.Card, :count)
```

## Architecture

```
lib/pokevestment/
  api/                  # External API clients (Tesla/Req)
    tcgdex.ex           #   TCGdex — card data, sets, pricing
    poke_api.ex         #   PokeAPI — species, sprites, evolution chains
    limitless.ex        #   Limitless TCG — tournament standings, decklists
  cards/                # Card domain schemas
    series.ex           #   Series (21 rows, e.g. "Scarlet & Violet")
    set.ex              #   Sets (200 rows, e.g. "Twilight Masquerade")
    card.ex             #   Cards (22,754 rows) — includes ML feature columns
    card_type.ex        #   Card type associations (19,435 rows)
    card_dex_id.ex      #   Card-to-Pokedex mappings (16,953 rows)
  pokemon/
    species.ex          #   Pokemon species (1,025 rows)
  pricing/
    price_snapshot.ex   #   Daily price snapshots (62K+ rows, insert-only)
  tournaments/          # Tournament domain schemas
    tournament.ex       #   Tournaments (37+ rows)
    tournament_standing.ex  #   Player standings with deck archetypes (1,713+ rows)
    tournament_deck_card.ex #   Individual cards in decklists (32,560+ rows)
  ingestion/            # Data pipelines (no DB in transformers)
    transformer.ex      #   TCGdex/PokeAPI → Ecto attrs (pure functions)
    tournament_transformer.ex  # Limitless → Ecto attrs (pure functions)
    feature_extractor.ex #  ML feature computation (pure functions)
    full_import.ex      #   Full data import orchestrator
    price_sync.ex       #   Daily price sync orchestrator
    tournament_import.ex #  Tournament data import orchestrator
  workers/              # Oban background workers
    daily_price_sync.ex #   Cron: 6 AM UTC daily
    tournament_sync.ex  #   Cron: 8 AM UTC daily
```

## Data Sources

| Source | Auth | Data | Refresh |
|---|---|---|---|
| [TCGdex](https://api.tcgdex.net/v2/en) | None | Cards, sets, series, pricing | Initial import + daily price sync |
| [PokeAPI](https://pokeapi.co/api/v2) | None | Pokemon species, sprites, evolutions | Initial import only |
| [Limitless TCG](https://play.limitlesstcg.com/api) | None | Tournament results, standings, decklists | Daily sync |

## Database Schema

```
series (21)
  └── sets (200)
        └── cards (22,754)  ←── card_types, card_dex_ids
              └── price_snapshots (62K+)
              └── tournament_deck_cards.card_id (FK, nullable)

pokemon_species (1,025)

tournaments (37+)
  └── tournament_standings (1,713+)
        └── tournament_deck_cards (32,560+)
```

**Key design decisions**:
- Card IDs are strings from TCGdex (e.g. `sv06-040`), zero-padded 3-digit local IDs
- `sets.ptcgo_code` maps PTCGO codes (e.g. `TWM`) to set IDs (e.g. `sv06`) for tournament card resolution
- `price_snapshots` and `tournament_deck_cards` are insert-only (no `updated_at`)
- Tournament deck cards have a nullable FK to `cards` — ~89% resolve, remainder are basic energies (MEE) or unreleased sets (POR)

## Mix Tasks

All tasks are namespaced under `mix pokevestment.*` and follow consistent patterns:
- Start the app with `Mix.Task.run("app.start")`
- Print progress during long operations
- Return structured summaries on completion
- Idempotent — safe to re-run

### Task Reference

| Task | Purpose | Typical Runtime |
|---|---|---|
| `mix pokevestment.import` | Full data import from TCGdex + PokeAPI | ~45 min |
| `mix pokevestment.price_sync` | Sync current card prices from TCGdex | ~30 min |
| `mix pokevestment.import_tournaments` | Import tournament data from Limitless TCG | ~4 min |
| `mix pokevestment.backfill_features` | Compute ML feature columns on cards | ~10 sec |
| `mix pokevestment.backfill_art_types` | Compute art type features from rarity | ~10 sec |

### Detailed Usage

```bash
# Full import (series → sets → species → cards with pricing)
mix pokevestment.import
mix pokevestment.import series         # Just series
mix pokevestment.import sets           # Just sets
mix pokevestment.import species        # Just species
mix pokevestment.import cards          # Just cards

# Daily price sync (usually run by Oban cron, but can run manually)
mix pokevestment.price_sync

# Tournament data (usually run by Oban cron, but can run manually)
mix pokevestment.import_tournaments                    # STANDARD format (default)
mix pokevestment.import_tournaments --format EXPANDED  # Specific format
mix pokevestment.import_tournaments --all              # All formats

# ML feature backfill (run after initial card import)
mix pokevestment.backfill_features

# Art type feature backfill (run after initial card import)
mix pokevestment.backfill_art_types
```

## Mix Task Naming Conventions

When adding new mix tasks, follow these rules so they stay consistent and discoverable:

**Namespace**: Always `mix pokevestment.<task_name>`

**Naming pattern**: `<verb>_<noun>` using snake_case

- `import` — Bulk loading data from an external source for the first time
- `import_<entity>` — Bulk loading a specific entity type (e.g. `import_tournaments`)
- `<verb>_<noun>` — Action on a specific target (e.g. `backfill_features`, `price_sync`)

**File location**: `lib/mix/tasks/pokevestment.<task_name>.ex`

**Module name**: `Mix.Tasks.Pokevestment.<PascalCaseTaskName>` (e.g. `Mix.Tasks.Pokevestment.ImportTournaments`)

**Required elements**:
- `use Mix.Task`
- `@shortdoc` — One-line description (shown in `mix help`)
- `@moduledoc` — Full description with `## Usage` section showing all invocations
- `@impl Mix.Task` on `run/1`
- `Mix.Task.run("app.start")` as first line of `run/1`
- `format_duration/1` helper for elapsed time reporting

**Conventions**:
- Parse args in `run/1`, delegate to an orchestrator module in `lib/pokevestment/ingestion/`
- Don't put business logic in the mix task — it's a thin CLI wrapper
- Print summary on success with `Mix.shell().info/1`
- Raise on failure with `Mix.raise/1`
- Support `--flag value` style args for options

**Template**:
```elixir
defmodule Mix.Tasks.Pokevestment.DoThing do
  @moduledoc """
  Description of what this task does.

  ## Usage

      mix pokevestment.do_thing              # Default behavior
      mix pokevestment.do_thing --flag val   # With options
  """

  use Mix.Task

  @shortdoc "One-line description for mix help"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    # Parse args, call orchestrator, print summary
  end
end
```

## Oban Workers

| Worker | Queue | Schedule | Max Attempts |
|---|---|---|---|
| `DailyPriceSync` | `:ingestion` | `0 6 * * *` (6 AM UTC) | 3 |
| `TournamentSync` | `:ingestion` | `0 8 * * *` (8 AM UTC) | 3 |

Workers are thin wrappers that delegate to orchestrator modules in `lib/pokevestment/ingestion/`. Partial success (some cards/tournaments fail) returns `:ok` — only total API failure triggers Oban retry.

### Ongoing Operations

Once the Phoenix server is running, Oban handles daily syncs automatically — no external cron needed.

- **DailyPriceSync** (6 AM UTC): Fetches current prices for all ~22K cards from TCGdex, inserts new `price_snapshot` rows. ~30 min runtime.
- **TournamentSync** (8 AM UTC): Fetches new STANDARD-format tournaments from Limitless TCG, inserts tournaments + standings + deck cards. ~4 min runtime.
- Oban retries up to 3x on API failure. Individual card/tournament failures within a run don't trigger retry — partial success returns `:ok`.
- If the server is down at sync time, the job runs on next startup. Oban persists jobs in PostgreSQL so nothing is lost.
- Manual trigger anytime: `mix pokevestment.price_sync` or `mix pokevestment.import_tournaments`

### Re-running & Recovery

- All import tasks are idempotent via `on_conflict: :nothing` (immutable data) or `:replace_all_except` (updatable data)
- If `mix pokevestment.import` fails halfway through cards, re-run it — already-imported cards are skipped
- Each task prints progress during execution and a summary with failure counts on completion
- Tournament import defaults to STANDARD format; use `--format EXPANDED` or `--all` for other formats
- There is no DB dump/restore or seed file — all data comes from live API calls

## Ingestion Patterns

All import/sync orchestrators follow these patterns:

- **Preload lookups** — Load Maps/MapSets of existing IDs before processing to avoid N+1 queries
- **Concurrent processing** — `Task.async_stream` with conservative `max_concurrency` (3-10 depending on API)
- **Idempotent inserts** — `on_conflict: :nothing` for immutable data, `:replace_all_except` for updatable
- **Atomic progress tracking** — `:counters` module for thread-safe counting across concurrent tasks
- **Resilient error handling** — Individual failures don't abort the batch; tracked and returned in summary
- **Transaction wrapping** — Related inserts grouped in `Repo.transaction` (e.g. tournament + standings + deck cards)
- **Raw metadata preservation** — Every API-sourced table has a `metadata :map` (JSONB) column storing the unfiltered raw API response. This preserves data for debugging and future feature extraction without re-hitting external APIs

## Testing

```bash
mix test                   # Run all tests (76 tests)
mix precommit              # Full check: compile warnings, deps, format, test
```

Test infrastructure:
- `Pokevestment.DataCase` — DB tests with Ecto sandbox (automatic rollback)
- `ExUnit.Case` — Pure function tests (transformers, extractors)
- Mox available (`{:mox, "~> 1.1"}`) but not yet configured for API mocking
