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

# 4. Backfill set-level supply proxy features (~1 sec, no network)
#    Populates: secret_rare_count, secret_rare_ratio, era on sets
mix pokevestment.backfill_set_features

# 5. Backfill language availability counts (~2 min, hits TCGdex for 6 languages)
#    Populates: language_count on cards (range 1–6)
mix pokevestment.backfill_language_counts

# 6. Import tournament data from Limitless TCG
#    Hits Limitless live, rate-limited (~7s/tournament), ~4 min for ~37 tournaments
#    Links deck cards to cards table via PTCGO code mapping
mix pokevestment.import_tournaments
```

All tasks are idempotent — safe to re-run if interrupted. Already-imported data is skipped via `on_conflict: :nothing`. Skipping backfill steps 2–5 will leave ML features, art types, set supply proxies (`secret_rare_count`, `secret_rare_ratio`, `era`), and `language_count` at their defaults.

### Verify the Load

After all steps complete, expected row counts:

| Table | Expected Rows |
|---|---|
| series | 21 |
| sets | 200 |
| cards | 22,754 |
| card_types | 19,435 |
| card_dex_ids | 16,953 |
| pokemon_species | 1,025 |
| price_snapshots | 62K+ |
| tournaments | 130+ |
| tournament_standings | 6,581+ |
| tournament_deck_cards | 161,449+ |

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
  api/                  # External API clients (Req)
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
    tournament.ex       #   Tournaments (130+ rows)
    tournament_standing.ex  #   Player standings with deck archetypes (6,581+ rows)
    tournament_deck_card.ex #   Individual cards in decklists (161,449+ rows)
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

tournaments (130+)
  └── tournament_standings (6,581+)
        └── tournament_deck_cards (161,449+)
```

**Key design decisions**:
- Card IDs are strings from TCGdex (e.g. `sv06-040`), zero-padded 3-digit local IDs
- `sets.ptcgo_code` maps PTCGO codes (e.g. `TWM`) to set IDs (e.g. `sv06`) for tournament card resolution
- `price_snapshots` and `tournament_deck_cards` are insert-only (no `updated_at`)
- Tournament deck cards have a nullable FK to `cards` — ~89% resolve, remainder are basic energies (MEE) or unreleased sets (POR)

## ML Feature Inventory

70 base features (~85-90 when tournament time windows are expanded) across 7 umbrellas. Every feature below is either a direct database column or derivable from existing columns at feature matrix assembly time.

### Legend

- **Source**: Where the data lives in our DB
- **Type**: How ML should treat it (numeric, categorical, boolean, derived)
- **Coverage**: % of 22,754 cards that have this field populated
- **Signal**: Estimated predictive importance for card price prediction

### Umbrella 1: Card Identity & Classification

*What the card IS — its fundamental properties.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 1 | `category` | cards.category | Categorical (3) | 100% | High | Pokemon / Trainer / Energy |
| 2 | `rarity` | cards.rarity | Categorical (65+) | 100% | Very High | Mega Hyper Rare avg $304 vs Common $4.67 (65x) |
| 3 | `art_type` | cards.art_type | Categorical (14) | 100% | Very High | Normalized rarity → art classification |
| 4 | `is_full_art` | cards.is_full_art | Boolean | 100% | High | Binary flag for any full/alt art |
| 5 | `is_alternate_art` | cards.is_alternate_art | Boolean | 100% | High | Covers illustration, special illustration, rainbow |
| 6 | `is_secret_rare` | cards.is_secret_rare | Boolean | 100% | High | $77 avg vs $12.48 non-secret (6.2x) |
| 7 | `suffix` | cards.suffix | Categorical (7) | 10% | High | ex, GX, V, VMAX, VSTAR, TAG TEAM-GX, etc. |
| 8 | `stage` | cards.stage | Categorical | 82% | Medium | Basic, Stage 1, Stage 2, MEGA, etc. |
| 9 | `hp` | cards.hp | Numeric | 85% | Low-Medium | Hit points (null for Trainers/Energy) |
| 10 | `trainer_type` | cards.trainer_type | Categorical | 12% | Low | Supporter, Item, Stadium, Tool (Trainers only) |
| 11 | `energy_type` | cards.energy_type | Categorical | 2% | Low | Basic energy type (Energy cards only) |
| 12 | `regulation_mark` | cards.regulation_mark | Categorical (A-H) | 34% | Medium | Modern cards only — era indicator |
| 13 | `first_edition` | cards.first_edition | Boolean | 100% | High | ~940 cards are 1st edition |
| 14 | `is_shadowless` | cards.is_shadowless | Boolean | 100% | High | Shadowless Base Set cards worth significantly more |
| 15 | `has_first_edition_stamp` | cards.has_first_edition_stamp | Boolean | 100% | Medium | Has 1st-edition in stamps |

### Umbrella 2: Combat & Gameplay Power

*How strong the card is in actual gameplay.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 16 | `attack_count` | cards.attack_count | Numeric (0-4) | 100% | Low-Medium | Number of attacks |
| 17 | `total_attack_damage` | cards.total_attack_damage | Numeric | 100% | Low | Sum of all attack damage |
| 18 | `max_attack_damage` | cards.max_attack_damage | Numeric | 100% | Low-Medium | Highest single attack |
| 19 | `has_ability` | cards.has_ability | Boolean | 100% | Low-Medium | Cards with abilities are often more playable |
| 20 | `ability_count` | cards.ability_count | Numeric | 100% | Low | Number of abilities |
| 21 | `weakness_count` | cards.weakness_count | Numeric | 100% | Low | Number of type weaknesses |
| 22 | `resistance_count` | cards.resistance_count | Numeric | 100% | Low | Number of type resistances |
| 23 | `retreat_cost` | cards.retreat_cost | Numeric | 70% | Low | Energy to retreat |
| 24 | `type_count` | card_types (count) | Numeric | 85% | Low | Number of energy types on card |
| 25 | `primary_type` | card_types (first) | Categorical | 85% | Medium | Fire, Water, Psychic, etc. |
| 26 | `energy_cost_total` | cards.energy_cost_total | Numeric | 84% | Low | Sum of all attack energy costs |

### Umbrella 3: Pokemon Identity & Lore

*Which Pokemon is on the card and its in-game significance.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 27 | `generation` | cards.generation | Numeric (1-9) | 74% | Very High | Gen 1 avg $28.21 vs Gen 9 $1.14 (25x) |
| 28 | `is_legendary` | pokemon_species.is_legendary | Boolean | 74%\* | High | $52.12 avg vs $14.09 (3.7x) |
| 29 | `is_mythical` | pokemon_species.is_mythical | Boolean | 74%\* | Medium | $27.06 avg vs $14.09 (1.9x) |
| 30 | `is_baby` | pokemon_species.is_baby | Boolean | 74%\* | Low | Baby Pokemon flag |
| 31 | `capture_rate` | pokemon_species.capture_rate | Numeric (3-255) | 74%\* | Medium | Lower = rarer in games = potentially higher card value |
| 32 | `species_color` | pokemon_species.color | Categorical | 74%\* | Low | Body color classification |
| 33 | `species_habitat` | pokemon_species.habitat | Categorical | 26%\*\* | Low | Only Gen 1-3 have habitats |
| 34 | `species_shape` | pokemon_species.shape | Categorical | 74%\* | Low | Body shape |
| 35 | `growth_rate` | pokemon_species.growth_rate | Categorical | 74%\* | Low | Experience growth rate |
| 36 | `evolution_stage_in_chain` | Derived from evolves_from_id chains | Categorical (base/mid/final) | 74%\* | Medium | Final evolutions more popular |
| 37 | `evolves_from` | cards.evolves_from | String/Boolean | 35% | Low | Has evolution predecessor |

\* Coverage is 74% because only Pokemon cards have dex_ids; Trainers/Energy are null — correct behavior.
\*\* PokeAPI only has habitat for Gen 1-3.

### Umbrella 4: Artist & Visual Appeal

*Who made the art and what kind of art treatment it received.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 38 | `illustrator` | cards.illustrator | Categorical (407) | 91% | Very High | Top artist avg $209 vs bottom <$1 (200x+) |
| 39 | `illustrator_frequency` | Derived (count per illustrator) | Numeric | 91% | Medium | Prolific vs rare illustrators |
| 40 | `has_image` | cards.image_url IS NOT NULL | Boolean | 96% | Low | Proxy for card data completeness |

Note: `art_type`, `is_full_art`, `is_alternate_art` from Umbrella 1 are also visual but derive from rarity, so they're classified under Identity.

### Umbrella 5: Set & Series Context

*Where and when the card was released — supply-side signals.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 41 | `set_id` | cards.set_id | Categorical (200) | 100% | Medium | Which set the card belongs to |
| 42 | `series_id` | sets.series_id | Categorical (21) | 100% | Medium | Which series the set belongs to |
| 43 | `era` | sets.era | Categorical (12) | 100% | High | wotc/ex/dp/bw/xy/sm/swsh/sv/mega/etc. |
| 44 | `days_since_release` | Derived: Date.diff(today, sets.release_date) | Numeric | 99% | Very High | Likely top-3 predictor. Older = more valuable. |
| 45 | `set_card_count_official` | sets.card_count_official | Numeric | 100% | Medium | Smaller sets = rarer pulls |
| 46 | `set_card_count_total` | sets.card_count_total | Numeric | 100% | Low | Total including secrets |
| 47 | `secret_rare_count` | sets.secret_rare_count | Numeric | 100% | Medium | Number of bonus/secret cards |
| 48 | `secret_rare_ratio` | sets.secret_rare_ratio | Numeric | 100% | Medium | Proportion of chase cards |
| 49 | `set_legal_standard` | sets.legal_standard | Boolean | 100% | Medium | Tournament legality affects demand |
| 50 | `set_legal_expanded` | sets.legal_expanded | Boolean | 100% | Low | Expanded format legality |
| 51 | `language_count` | cards.language_count | Numeric (1-6) | 100% | Medium | More languages = larger print run = more supply |

### Umbrella 6: Competitive / Tournament Demand

*How the card performs in competitive play — strongest short-term predictor.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 52 | `meta_share` | Derived: decks with card / total decks in period | Numeric (0-1) | Varies\* | Very High | Primary demand pressure signal |
| 53 | `tournament_appearances` | Derived: count distinct tournaments | Numeric | Varies | High | Breadth of competitive demand |
| 54 | `avg_copies_per_deck` | Derived: avg count when included | Numeric (1-4) | Varies | High | 4-of staple vs 1-of tech |
| 55 | `archetype_count` | Derived: distinct deck_archetype_ids | Numeric | Varies | High | Versatility across deck types |
| 56 | `avg_win_rate` | Derived: weighted avg wins/(wins+losses+ties) | Numeric (0-1) | Varies | Medium-High | Competitive strength signal |
| 57 | `meta_trend` | Derived: meta_share(7d) - meta_share(30d) | Numeric | Varies | Very High | Rising/falling demand momentum |
| 58 | `top_8_appearances` | Derived: count of standings where placing <= 8 | Numeric | Varies | High | Elite competitive performance |

\* Tournament features are computed over time windows (7d, 30d, 90d). Each window is effectively a separate feature, so features 52-58 multiply by 2-3 windows = ~15-20 actual features. Coverage varies because many cards (especially older/non-competitive) have zero tournament data.

Raw data: 130 tournaments, 6,581 standings, 161,449 deck card rows.

### Umbrella 7: Price & Market Signals

*Current and historical pricing data — both target variables and features.*

| # | Feature | Source | Type | Coverage | Signal | Notes |
|---|---------|--------|------|----------|--------|-------|
| 59 | `price_market` (TCGPlayer) | price_snapshots | Numeric | 42% | Target | TCGPlayer market price (USD) |
| 60 | `price_avg` (CardMarket) | price_snapshots | Numeric | 81% | Target | CardMarket average price (EUR) |
| 61 | `price_trend` (CardMarket) | price_snapshots | Numeric | 81% | Feature | CardMarket trend indicator |
| 62 | `price_avg1` | price_snapshots | Numeric | 81% | Feature | 1-day moving average |
| 63 | `price_avg7` | price_snapshots | Numeric | 81% | Feature | 7-day moving average |
| 64 | `price_avg30` | price_snapshots | Numeric | 81% | Feature | 30-day moving average |
| 65 | `price_momentum_7d` | Derived: price_avg1 / price_avg7 | Numeric | 81% | High | Short-term momentum |
| 66 | `price_momentum_30d` | Derived: price_avg1 / price_avg30 | Numeric | 81% | High | Medium-term momentum |
| 67 | `tcg_cm_spread` | Derived: price_market / price_avg | Numeric | 42% | Medium | Cross-market price divergence |
| 68 | `price_low` | price_snapshots | Numeric | 84% | Low | Floor price |
| 69 | `price_high` | price_snapshots | Numeric | 84% | Low | Ceiling price |
| 70 | `price_spread` | Derived: (high - low) / mid | Numeric | 84% | Medium | Market uncertainty/volatility |

Features 62-66 are available today from CardMarket's rolling averages — no need to wait for our own time-series to accumulate for basic momentum signals.

### Signal Strength Summary

| Tier | Features | Notes |
|------|----------|-------|
| **Very High** | rarity/art_type, generation, days_since_release, illustrator, meta_share, meta_trend, price_momentum | These 7 likely explain 80%+ of variance |
| **High** | is_legendary, is_secret_rare, suffix, era, first_edition, is_shadowless, tournament_appearances, avg_copies_per_deck, archetype_count | Strong secondary signals |
| **Medium** | secret_rare_ratio, capture_rate, language_count, regulation_mark, set_card_count, hp, stage, primary_type, price_spread, evolution_stage | Moderate predictive power |
| **Low** | Most combat stats, species_color/shape/habitat, energy_type, trainer_type, growth_rate | Individually weak but may contribute in ensemble |

### Coverage Summary

- **42 features** available at 100% coverage (no nulls)
- **19 features** require species join (null for non-Pokemon cards — correct behavior)
- **7 tournament features** are derived at query time from tournament tables (x2-3 time windows each)
- **12 price features** from price_snapshots (coverage depends on source: CardMarket 81%, TCGPlayer 42%)

### How ML Should Use These Umbrellas

**For the ML pipeline**: The model should weight features individually (not by umbrella). XGBoost/LightGBM does this automatically via feature importance. The umbrellas are for human interpretation only.

**For the UI/UX**: When explaining "why is this card undervalued?", group the top contributing features under their umbrella:

```text
STRONG BUY — Pikachu VMAX (Secret)

Value Drivers:
  Card Identity: Secret rare (6.2x premium), VMAX suffix (3.4x)
  Pokemon Lore: Generation 1 (25x vs Gen 9), iconic species
  Artist: HYOGONOSUKE (top-tier illustrator, 2.1x premium)
  Set Context: 1,800 days old (vintage premium building)
  Tournament: 12% meta share, appearing in 4 archetypes
```

The umbrellas give users a mental model: "this card is valuable because of WHAT it is + WHO made it + WHEN it came from + HOW it's used in competition."

### Future Feature Sources

| Future Feature | Umbrella | Source |
|---------------|----------|--------|
| Graded population (PSA census) | New: **Scarcity & Grading** | PSA API / scraping |
| Historical price backfill | Price & Market Signals | PokemonPriceTracker |
| Japanese market pricing | Price & Market Signals | PokemonPriceTracker |
| Social media mentions | New: **Hype & Sentiment** | Reddit/YouTube APIs |
| Sealed product prices | New: **Sealed Market** | Various |
| Sales volume | Price & Market Signals | TCGPlayer affiliate |

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
| `mix pokevestment.backfill_set_features` | Compute set-level supply proxy features | ~1 sec |
| `mix pokevestment.backfill_language_counts` | Backfill language availability counts | ~2 min |

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

# Set-level supply proxy features (run after initial set import)
mix pokevestment.backfill_set_features

# Language availability counts (run after initial card import, hits TCGdex)
mix pokevestment.backfill_language_counts
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
mix test                   # Run all tests (92 tests)
mix precommit              # Full check: compile warnings, deps, format, test
```

Test infrastructure:
- `Pokevestment.DataCase` — DB tests with Ecto sandbox (automatic rollback)
- `ExUnit.Case` — Pure function tests (transformers, extractors)
- Mox available (`{:mox, "~> 1.1"}`) but not yet configured for API mocking
