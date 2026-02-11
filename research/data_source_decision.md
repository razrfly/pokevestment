# Data Source Decision Document

**Research Date**: 2026-02-11
**Decision Status**: ✅ Final
**Effective**: Phase 1 Implementation

---

## Final Recommendations

### Primary Card Metadata Source

**Decision**: `Pokemon TCG API (pokemontcg.io)`

**Rationale**:
- Comprehensive card database (20,113 cards)
- Well-documented, stable API
- Includes pricing data (no separate integration needed)
- Artist field supports premium analysis
- Free tier sufficient for MVP

---

### Primary Price Data Source

**Decision**: `Pokemon TCG API (integrated TCGPlayer + CardMarket)`

**Rationale**:
- Single API provides both major market prices
- Includes historical averages (avg1, avg7, avg30)
- Variant-specific pricing (holo, reverse, normal)
- Daily updates
- No additional API integration needed

---

### Grading Data Approach

**Decision**: `Deferred to Phase 2+`

**Rationale**:
- No public PSA API available
- Web scraping has legal/TOS risks
- Focus MVP on raw card prices
- Can add via Playwright automation later

**Phase 2 Plan**:
- Evaluate Playwright browser automation
- Consider manual curation of top 500 cards
- Explore PSA data partnership

---

### Ground-Truth Validation Source

**Decision**: `eBay API (Phase 2)`

**Rationale**:
- Actual sale prices vs. market estimates
- 90-day completed listing history
- Graded card prices available
- OAuth complexity deferred from MVP

**Phase 2 Plan**:
- Register eBay developer account
- Implement OAuth 2.0 client
- Use for model validation and arbitrage detection

---

## Architecture Summary

### MVP Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Pokemon TCG API                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │    Cards    │  │  TCGPlayer  │  │   CardMarket    │  │
│  │  Metadata   │  │   Prices    │  │    Prices       │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                   Elixir Ingestion                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Oban Job  │  │  Transform  │  │   Normalize     │  │
│  │   (Daily)   │  │    Data     │  │   USD/EUR       │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    PostgreSQL                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │    cards    │  │price_history│  │     sets        │  │
│  │    table    │  │   (daily)   │  │    table        │  │
│  └─────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Preliminary Schema Design

Based on actual API responses, here's the recommended schema:

### Cards Table

```sql
CREATE TABLE cards (
  id VARCHAR PRIMARY KEY,           -- "base1-4"
  name VARCHAR NOT NULL,            -- "Charizard"
  supertype VARCHAR,                -- "Pokémon"
  subtypes VARCHAR[],               -- ["Stage 2"]
  hp INTEGER,
  types VARCHAR[],                  -- ["Fire"]
  evolves_from VARCHAR,
  artist VARCHAR,                   -- "Mitsuhiro Arita"
  rarity VARCHAR,                   -- "Rare Holo"
  national_pokedex_numbers INTEGER[],
  set_id VARCHAR REFERENCES sets(id),
  number VARCHAR,                   -- "4"
  images JSONB,
  legalities JSONB,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Sets Table

```sql
CREATE TABLE sets (
  id VARCHAR PRIMARY KEY,           -- "base1"
  name VARCHAR NOT NULL,            -- "Base"
  series VARCHAR,                   -- "Base"
  printed_total INTEGER,
  total INTEGER,
  release_date DATE,
  images JSONB,
  legalities JSONB,
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Price History Table

```sql
CREATE TABLE price_history (
  id BIGSERIAL PRIMARY KEY,
  card_id VARCHAR REFERENCES cards(id),
  recorded_at DATE NOT NULL,

  -- TCGPlayer prices (USD)
  tcg_low DECIMAL(10,2),
  tcg_mid DECIMAL(10,2),
  tcg_high DECIMAL(10,2),
  tcg_market DECIMAL(10,2),
  tcg_direct_low DECIMAL(10,2),
  tcg_variant VARCHAR,              -- "holofoil", "reverseHolofoil", "normal"

  -- CardMarket prices (EUR)
  cm_avg_sell DECIMAL(10,2),
  cm_low DECIMAL(10,2),
  cm_trend DECIMAL(10,2),
  cm_avg1 DECIMAL(10,2),
  cm_avg7 DECIMAL(10,2),
  cm_avg30 DECIMAL(10,2),

  UNIQUE(card_id, recorded_at, tcg_variant)
);

-- Index for time-series queries
CREATE INDEX idx_price_history_card_date
ON price_history(card_id, recorded_at DESC);
```

### Artists Table (for premium analysis)

```sql
CREATE TABLE artists (
  id SERIAL PRIMARY KEY,
  name VARCHAR UNIQUE NOT NULL,     -- "Mitsuhiro Arita"
  card_count INTEGER DEFAULT 0,
  avg_price_premium DECIMAL(5,2),   -- calculated field
  notable_cards VARCHAR[],
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

---

## Data Collection Strategy

### Daily Job (Oban)

```elixir
# Runs daily at 2:00 AM UTC
def perform(_job) do
  # 1. Fetch all cards with prices
  cards = PokemonTCG.fetch_all_cards_with_prices()

  # 2. Upsert card metadata
  Enum.each(cards, &Cards.upsert/1)

  # 3. Insert price snapshots
  Enum.each(cards, &Prices.record_snapshot/1)

  # 4. Calculate derived metrics
  Metrics.calculate_daily_movements()
end
```

### Historical Data Timeline

| Week | Data Coverage | Capabilities |
|------|---------------|--------------|
| Week 1 | 7 days | Basic price display |
| Week 4 | 30 days | 30-day trends |
| Week 12 | 90 days | Full backtesting |

---

## Success Criteria Validation

From Phase 0 Issue:

- [x] ✅ Pokemon TCG API validated as card metadata source
- [x] ✅ At least ONE reliable price data source identified with 30+ days history
- [x] ✅ PSA/grading data approach determined (deferred)
- [x] ✅ eBay API access evaluated (available, deferred)
- [x] ✅ Card identifier correlation strategy documented (see below)
- [x] ✅ All research deliverables committed to `research/` directory
- [x] ✅ Go/No-Go decision documented: **GO**

---

## Card Identifier Correlation

### Pokemon TCG API ID Format

Pattern: `{set_id}-{card_number}`

Examples:
- `base1-4` (Base Set Charizard)
- `swsh2-5` (Rebel Clash Shuckle)
- `sm9-23` (Team Up Squirtle)

### TCGdex ID Format

Same pattern: `{set_id}-{card_number}`

**Correlation**: Direct 1:1 mapping between Pokemon TCG API and TCGdex IDs.

### Edge Cases

| Case | Example | Handling |
|------|---------|----------|
| Promo cards | `basep-1` | Set ID includes "p" suffix |
| Variants | Same ID, different prices | Use `tcg_variant` field |
| Regional | Japanese sets | Different set IDs |

---

## Approval

**Decision Made By**: Research Phase Analysis
**Date**: 2026-02-11
**Status**: Ready for Phase 1 Implementation
