# Phase B: Schema Design — Final Table Definitions

> Definitive schema document for Phase C Ecto migrations.
> Based on Phase A API exploration (2026-03-28) with live TCGdex + PokeAPI data.
> Supersedes Issue #4's schema (which was designed around pokemontcg.io field names).

---

## Changes from Issue #4

Issue #4 was designed around pokemontcg.io. Now that TCGdex is our primary API, the following changes are required:

| Issue #4 | Phase B | Rationale |
|----------|---------|-----------|
| `supertype` column | `category` | TCGdex field name |
| `artist_id` FK → `artists` table | `illustrator` string column | 407 illustrators, no metadata beyond name — table adds complexity with no benefit |
| `subtypes[]` array | `stage` + `suffix` separate columns | TCGdex provides them separately; better for ML (independent features) |
| `number` column | `local_id` | TCGdex field name |
| `national_pokedex_numbers[]` on cards | `card_dex_ids` join table | Enables multi-Pokemon card queries, future pokemon_species join |
| `types[]` array on cards | `card_types` join table | 11 values, enables ML queries like "all Fire-type cards" |
| `series` string on sets | `series` table + `series_id` FK | TCGdex provides structured `{id, name}` — 21 rows |
| `printed_total` / `total` on sets | `card_count_official` / `card_count_total` | Clearer naming |
| `price_history` (mixed TCGPlayer/CardMarket columns) | `price_snapshots` (one row per source) | Different field structures per source; `source` column separates them |
| `pokemon` + `evolution_chains` (Phase 2) | `pokemon_species` (MVP) | User wants character profiles from day one |
| Drop `artists` table | — | String column sufficient |
| Drop `evolves_to[]` | — | Not in TCGdex; derivable from `evolves_from` relationships |
| Drop `rules[]` | — | Not in TCGdex; low ML value |
| Drop `flavor_text` | Moved to `metadata` JSONB | TCGdex `description` field; available on some modern cards only |

**New columns not in Issue #4:**

| Column | Table | Source |
|--------|-------|--------|
| `variants` (JSONB) | cards | TCGdex boolean flags for variant availability |
| `variants_detailed` (JSONB) | cards | TCGdex array of variant objects (shadowless, stamps, etc.) |
| `regulation_mark` | cards | TCGdex `regulationMark` — era/legality indicator |
| `suffix` | cards | TCGdex mechanic marker (EX, GX, V, TAG TEAM-GX, etc.) |
| `energy_type` | cards | TCGdex `energyType` — for Energy cards only |
| `trainer_type` | cards | Derived from TCGdex card data (Item, Supporter, Stadium, Tool) |
| `is_secret_rare` | cards | Derived: `local_id_numeric > set.card_count_official` |
| `generation` | cards | Derived from dex_id via lookup table |
| `series_id` FK | sets | TCGdex `serie.id` — references new `series` table |

---

## Table Definitions

### Migration Order

```
1. series           (no dependencies)
2. sets             (depends on: series)
3. pokemon_species  (no dependencies — self-referencing FK only)
4. cards            (depends on: sets)
5. card_types       (depends on: cards)
6. card_dex_ids     (depends on: cards, pokemon_species)
7. price_snapshots  (depends on: cards)
```

---

### 1. `series`

**Source**: TCGdex `/v2/en/series` — 21 rows
**Purpose**: Group sets into series (e.g., Base, Sun & Moon, Scarlet & Violet)

| Column | Type | Constraints | Description | TCGdex Field |
|--------|------|-------------|-------------|--------------|
| `id` | `VARCHAR(30)` | PRIMARY KEY | Series identifier | `id` (e.g., "base", "sv") |
| `name` | `VARCHAR(100)` | NOT NULL | Display name | `name` (e.g., "Base", "Scarlet & Violet") |
| `logo_url` | `TEXT` | | Series logo image URL | `logo` |
| `metadata` | `JSONB` | | Full API response | — |
| `inserted_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |
| `updated_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |

**Indexes**: None needed — 21 rows, always accessed via PK.

---

### 2. `sets`

**Source**: TCGdex `/v2/en/sets/{id}` — 200 rows
**Purpose**: Card set metadata (release date, card counts, legality)

| Column | Type | Constraints | Description | TCGdex Field |
|--------|------|-------------|-------------|--------------|
| `id` | `VARCHAR(30)` | PRIMARY KEY | Set identifier | `id` (e.g., "base1", "sv01") |
| `name` | `VARCHAR(100)` | NOT NULL | Display name | `name` |
| `series_id` | `VARCHAR(30)` | FK → series.id, NOT NULL | Parent series | `serie.id` |
| `release_date` | `DATE` | | ISO format | `releaseDate` |
| `card_count_official` | `INTEGER` | | Printed card count | `cardCount.official` |
| `card_count_total` | `INTEGER` | | Total including secrets | `cardCount.total` |
| `logo_url` | `TEXT` | | Set logo image | `logo` |
| `symbol_url` | `TEXT` | | Set symbol image | `symbol` |
| `ptcgo_code` | `VARCHAR(10)` | | PTCGO deck code | `tcgOnline` |
| `legal_standard` | `BOOLEAN` | DEFAULT false | Standard format legal | `legal.standard` |
| `legal_expanded` | `BOOLEAN` | DEFAULT false | Expanded format legal | `legal.expanded` |
| `card_count_breakdown` | `JSONB` | | Variant counts per set | `cardCount` (full object) |
| `metadata` | `JSONB` | | Full API response | — |
| `inserted_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |
| `updated_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |

**`card_count_breakdown` JSONB example:**
```json
{
  "firstEd": 102,
  "holo": 64,
  "normal": 344,
  "reverse": 0
}
```
Rationale for JSONB: These per-variant counts are informational, not queried or used as ML features.

**Indexes**:
- `idx_sets_series_id` on `series_id`
- `idx_sets_release_date` on `release_date`

**Foreign Keys**:
- `series_id` → `series(id)` ON DELETE RESTRICT

---

### 3. `pokemon_species`

**Source**: PokeAPI `/v2/pokemon-species/{id}` + `/v2/pokemon/{id}` — 1,025 rows
**Purpose**: Pokemon character profiles for display and future ML features
**Join key**: `pokemon_species.id` = `card_dex_ids.dex_id`

| Column | Type | Constraints | Description | PokeAPI Field |
|--------|------|-------------|-------------|---------------|
| `id` | `INTEGER` | PRIMARY KEY | National Pokedex number | `id` |
| `name` | `VARCHAR(50)` | NOT NULL, UNIQUE | Pokemon name | `name` |
| `generation` | `INTEGER` | NOT NULL | Generation number (1-9) | Derived from `generation.name` |
| `is_legendary` | `BOOLEAN` | NOT NULL, DEFAULT false | Legendary status | `is_legendary` |
| `is_mythical` | `BOOLEAN` | NOT NULL, DEFAULT false | Mythical status | `is_mythical` |
| `is_baby` | `BOOLEAN` | NOT NULL, DEFAULT false | Baby Pokemon | `is_baby` |
| `color` | `VARCHAR(20)` | | Primary color | `color.name` |
| `habitat` | `VARCHAR(30)` | | Natural habitat | `habitat.name` |
| `shape` | `VARCHAR(30)` | | Body shape | `shape.name` |
| `capture_rate` | `INTEGER` | | Base capture rate | `capture_rate` |
| `base_happiness` | `INTEGER` | | Base happiness | `base_happiness` |
| `growth_rate` | `VARCHAR(30)` | | Growth rate name | `growth_rate.name` |
| `flavor_text` | `TEXT` | | English flavor text (latest game) | `flavor_text_entries` (filtered) |
| `genus` | `VARCHAR(50)` | | Species category | `genera` (English, e.g., "Flame Pokémon") |
| `sprite_url` | `TEXT` | | Official artwork URL | `sprites.other.official-artwork.front_default` |
| `evolves_from_species_id` | `INTEGER` | FK → pokemon_species.id | Previous evolution | `evolves_from_species.url` → extract ID |
| `metadata` | `JSONB` | | Full API response | — |
| `inserted_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |
| `updated_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |

**Indexes**:
- `idx_pokemon_species_name` on `name`
- `idx_pokemon_species_generation` on `generation`
- `idx_pokemon_species_evolves_from` on `evolves_from_species_id`

**Foreign Keys**:
- `evolves_from_species_id` → `pokemon_species(id)` ON DELETE SET NULL

**Notes**:
- Fetched once and cached locally. PokeAPI data rarely changes.
- `flavor_text` is extracted by filtering `flavor_text_entries` for `language.name == "en"` and taking the most recent game version.
- `generation` stored as integer (1-9) not string ("generation-i"), for cleaner queries.
- Replaces Issue #4's `pokemon` + `evolution_chains` tables. Evolution chains are handled via `evolves_from_species_id` self-referencing FK — simpler than a separate chains table, and sufficient for "what does this Pokemon evolve from/to" queries.

---

### 4. `cards`

**Source**: TCGdex `/v2/en/cards/{id}` — 22,755 rows
**Purpose**: Core table — every Pokemon TCG card with ML-relevant features as columns

| Column | Type | Constraints | Description | TCGdex Field |
|--------|------|-------------|-------------|--------------|
| `id` | `VARCHAR(30)` | PRIMARY KEY | Card identifier | `id` (e.g., "base1-4") |
| `name` | `VARCHAR(150)` | NOT NULL | Card name | `name` |
| `local_id` | `VARCHAR(20)` | NOT NULL | Card number within set | `localId` |
| `category` | `VARCHAR(20)` | NOT NULL | Pokemon / Trainer / Energy | `category` |
| `set_id` | `VARCHAR(30)` | FK → sets.id, NOT NULL | Parent set | `set.id` |
| `rarity` | `VARCHAR(50)` | | Rarity classification (39 values) | `rarity` |
| `hp` | `INTEGER` | | Hit points (Pokemon only) | `hp` |
| `stage` | `VARCHAR(20)` | | Evolution stage | `stage` |
| `suffix` | `VARCHAR(30)` | | Mechanic marker | `suffix` |
| `illustrator` | `VARCHAR(100)` | | Artist name | `illustrator` |
| `evolves_from` | `VARCHAR(150)` | | Previous evolution name | `evolveFrom` |
| `retreat_cost` | `INTEGER` | | Retreat energy count | `retreat` |
| `regulation_mark` | `VARCHAR(5)` | | Regulation mark (D, E, F, G, H) | `regulationMark` |
| `energy_type` | `VARCHAR(20)` | | Energy subtype (Energy cards only) | `energyType` |
| `trainer_type` | `VARCHAR(20)` | | Trainer subtype (Trainer cards only) | See derivation below |
| `legal_standard` | `BOOLEAN` | DEFAULT false | Standard format legal | `legal.standard` |
| `legal_expanded` | `BOOLEAN` | DEFAULT false | Expanded format legal | `legal.expanded` |
| `is_secret_rare` | `BOOLEAN` | NOT NULL, DEFAULT false | Secret rare flag | Derived (see below) |
| `generation` | `INTEGER` | | Pokemon generation (1-9) | Derived from dex_id (see below) |
| `variants` | `JSONB` | | Variant availability flags | `variants` |
| `variants_detailed` | `JSONB` | | Detailed variant info | `variants_detailed` |
| `attacks` | `JSONB` | | Attack details array | `attacks` |
| `abilities` | `JSONB` | | Abilities/Powers array | `abilities` |
| `weaknesses` | `JSONB` | | Weakness array | `weaknesses` |
| `resistances` | `JSONB` | | Resistance array | `resistances` |
| `image_url` | `TEXT` | | Card image URL | `image` |
| `api_updated_at` | `TIMESTAMP` | | When TCGdex last updated this card | `updated` |
| `metadata` | `JSONB` | | Full API response | — |
| `inserted_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |
| `updated_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |

**Indexes**:
- `idx_cards_set_id` on `set_id`
- `idx_cards_name` on `name`
- `idx_cards_category` on `category`
- `idx_cards_rarity` on `rarity`
- `idx_cards_illustrator` on `illustrator`
- `idx_cards_regulation_mark` on `regulation_mark`
- `idx_cards_generation` on `generation`
- `idx_cards_is_secret_rare` on `is_secret_rare` (partial: WHERE `is_secret_rare` = true)
- `idx_cards_set_local` on `(set_id, local_id)` UNIQUE

**Foreign Keys**:
- `set_id` → `sets(id)` ON DELETE RESTRICT

---

### 5. `card_types`

**Source**: TCGdex `types[]` field on cards — ~25,000 rows
**Purpose**: Normalized card energy types for efficient ML queries

| Column | Type | Constraints | Description | TCGdex Field |
|--------|------|-------------|-------------|--------------|
| `card_id` | `VARCHAR(30)` | FK → cards.id, NOT NULL | Card reference | parent card `id` |
| `type_name` | `VARCHAR(20)` | NOT NULL | Energy type name | `types[]` element |

**Constraints**:
- `PRIMARY KEY (card_id, type_name)`

**11 possible `type_name` values**: Colorless, Darkness, Dragon, Fairy, Fighting, Fire, Grass, Lightning, Metal, Psychic, Water

**Indexes**:
- `idx_card_types_type_name` on `type_name` (for "all Fire-type cards" queries)

**Foreign Keys**:
- `card_id` → `cards(id)` ON DELETE CASCADE

**Notes**:
- Most cards have 1 type, some have 2 (e.g., dual-type Pokemon)
- Trainer cards have no entries in this table
- Energy cards DO have types (e.g., Basic Fighting Energy has `types: ["Fighting"]`) — expect entries for Energy cards
- Join table preferred over array: enables indexed queries like `WHERE type_name = 'Fire'` without GIN index overhead

---

### 6. `card_dex_ids`

**Source**: TCGdex `dexId[]` field on cards — ~20,000 rows
**Purpose**: Map cards to national Pokedex numbers for pokemon_species joins

| Column | Type | Constraints | Description | TCGdex Field |
|--------|------|-------------|-------------|--------------|
| `card_id` | `VARCHAR(30)` | FK → cards.id, NOT NULL | Card reference | parent card `id` |
| `dex_id` | `INTEGER` | NOT NULL | National Pokedex number | `dexId[]` element |

**Constraints**:
- `PRIMARY KEY (card_id, dex_id)`

**Indexes**:
- `idx_card_dex_ids_dex_id` on `dex_id` (for "all cards featuring Charizard" queries)

**Foreign Keys**:
- `card_id` → `cards(id)` ON DELETE CASCADE
- `dex_id` → `pokemon_species(id)` ON DELETE RESTRICT

**Notes**:
- Pokemon cards only — Trainer/Energy cards have no dex IDs
- ~1.05 rows per Pokemon card on average (most have 1 dex ID)
- Multi-Pokemon cards (Tag Teams, Fusion Strike) have 2+ entries
- Example: Eevee & Snorlax GX → two rows: `(card_id, 133)` and `(card_id, 143)`

---

### 7. `price_snapshots`

**Source**: TCGdex `pricing` field on cards — ~3.6M rows/year at weekly cadence
**Purpose**: Point-in-time price snapshots from TCGPlayer and CardMarket

| Column | Type | Constraints | Description | Source |
|--------|------|-------------|-------------|--------|
| `id` | `BIGSERIAL` | PRIMARY KEY | Auto-incrementing ID | — |
| `card_id` | `VARCHAR(30)` | FK → cards.id, NOT NULL | Card reference | parent card `id` |
| `source` | `VARCHAR(20)` | NOT NULL | Price source | `"tcgplayer"` or `"cardmarket"` |
| `variant` | `VARCHAR(30)` | NOT NULL | Variant type | See variant values below |
| `snapshot_date` | `DATE` | NOT NULL | Date of this snapshot | — |
| `currency` | `VARCHAR(3)` | NOT NULL | Currency code | `"USD"` (TCGPlayer) or `"EUR"` (CardMarket) |
| `price_low` | `DECIMAL(10,2)` | | Low/floor price | TCGPlayer: `lowPrice`, CardMarket: `low` |
| `price_mid` | `DECIMAL(10,2)` | | Mid price | TCGPlayer: `midPrice` |
| `price_high` | `DECIMAL(10,2)` | | High/ceiling price | TCGPlayer: `highPrice` |
| `price_market` | `DECIMAL(10,2)` | | Market price | TCGPlayer: `marketPrice` |
| `price_direct_low` | `DECIMAL(10,2)` | | Direct low price | TCGPlayer: `directLowPrice` |
| `price_avg` | `DECIMAL(10,2)` | | Average sell price | CardMarket: `avg` |
| `price_trend` | `DECIMAL(10,2)` | | Trend price | CardMarket: `trend` |
| `price_avg1` | `DECIMAL(10,2)` | | 1-day rolling average | CardMarket: `avg1` |
| `price_avg7` | `DECIMAL(10,2)` | | 7-day rolling average | CardMarket: `avg7` |
| `price_avg30` | `DECIMAL(10,2)` | | 30-day rolling average | CardMarket: `avg30` |
| `product_id` | `INTEGER` | | Source product identifier | TCGPlayer: `productId`, CardMarket: `idProduct` |
| `source_updated_at` | `TIMESTAMP` | | When source last updated | `updated` field from pricing |
| `metadata` | `JSONB` | | Raw pricing response | — |
| `inserted_at` | `TIMESTAMP` | NOT NULL | Ecto timestamp | — |

**Constraints**:
- `UNIQUE (card_id, source, variant, snapshot_date)`

**Variant values by source:**

| Source | Variant Values | Mapping |
|--------|---------------|---------|
| TCGPlayer | `normal` | `pricing.tcgplayer.normal` |
| TCGPlayer | `holofoil` | `pricing.tcgplayer.holofoil` |
| TCGPlayer | `reverse-holofoil` | `pricing.tcgplayer.reverse-holofoil` |
| TCGPlayer | `1stEditionHolofoil` | `pricing.tcgplayer.1stEditionHolofoil` |
| TCGPlayer | `1stEditionNormal` | `pricing.tcgplayer.1stEditionNormal` |
| CardMarket | `normal` | `pricing.cardmarket` base fields (avg, low, trend, avg1/7/30) |
| CardMarket | `holo` | `pricing.cardmarket` `-holo` suffixed fields |

**Indexes**:
- `idx_price_snapshots_card_source` on `(card_id, source)`
- `idx_price_snapshots_date` on `snapshot_date`
- `idx_price_snapshots_card_date` on `(card_id, snapshot_date)` — most common query pattern
- `idx_price_snapshots_card_variant_date` on `(card_id, variant, snapshot_date)` — variant-level trend queries

**Foreign Keys**:
- `card_id` → `cards(id)` ON DELETE CASCADE

**Column nullability pattern:**
- TCGPlayer rows: `price_low`, `price_mid`, `price_high`, `price_market`, `price_direct_low` populated; `price_avg`, `price_trend`, `price_avg1/7/30` NULL
- CardMarket rows: `price_avg`, `price_low`, `price_trend`, `price_avg1/7/30` populated; `price_mid`, `price_high`, `price_market`, `price_direct_low` NULL

This is intentional — the sources have fundamentally different pricing models. Using one table with `source` column is simpler than two tables, and queries always filter by source anyway.

**Growth projections:**
- Per snapshot: ~34,000 price rows (22,755 cards × ~1.5 variants × 2 sources)
- Weekly cadence: ~1.77M rows/year
- Daily cadence: ~12.4M rows/year
- **MVP recommendation**: Weekly snapshots = ~1.77M rows/year. Well within PostgreSQL comfort zone.

**Future partitioning**: When the table exceeds ~10M rows, partition by `snapshot_date` (yearly ranges). Ecto supports partitioned tables via custom migrations.

---

## Entity Relationship Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                            POKEVESTMENT SCHEMA (Phase B)                             │
│                                    7 Tables                                          │
└──────────────────────────────────────────────────────────────────────────────────────┘

  ┌────────────────┐
  │    series       │
  │────────────────│
  │ PK: id (varchar)│
  │    name         │
  │    logo_url     │
  └───────┬────────┘
          │ 1
          │
          │ N
  ┌───────▼────────┐         ┌──────────────────┐
  │     sets        │         │ pokemon_species   │
  │────────────────│         │──────────────────│
  │ PK: id (varchar)│         │ PK: id (integer)  │
  │ FK: series_id   │         │    name           │
  │    name         │         │    generation     │
  │    release_date │         │    is_legendary   │
  │    card_count_* │         │    flavor_text    │
  │    legal_*      │         │    genus          │
  │    ptcgo_code   │         │    sprite_url     │
  └───────┬────────┘         │ FK: evolves_from_ │◄──┐
          │ 1                 │     species_id    │   │ self-ref
          │                   └────────┬─────────┘───┘
          │ N                          │ 1
  ┌───────▼──────────────┐             │
  │       cards           │             │
  │──────────────────────│             │
  │ PK: id (varchar)      │             │
  │ FK: set_id            │             │
  │    name               │             │
  │    local_id           │             │
  │    category           │             │
  │    rarity             │             │
  │    hp                 │             │
  │    stage              │             │
  │    suffix             │             │
  │    illustrator        │             │
  │    evolves_from       │             │
  │    regulation_mark    │             │
  │    is_secret_rare     │             │
  │    generation         │             │
  │    variants (JSONB)   │             │
  │    attacks (JSONB)    │             │
  └──┬────────┬────────┬─┘             │
     │        │        │               │
     │ 1      │ 1      │ 1             │
     │        │        │               │
     │ N      │ N      │ N             │ N
  ┌──▼────┐ ┌─▼──────┐ ┌▼───────────┐ │
  │card_  │ │card_   │ │price_      │ │
  │types  │ │dex_ids │ │snapshots   │ │
  │───────│ │────────│ │────────────│ │
  │FK:    │ │FK:     │ │FK: card_id │ │
  │card_id│ │card_id │ │   source   │ │
  │type_  │ │dex_id──│─┘   variant  │
  │name   │ │  (FK)──│────►pokemon_ │
  │       │ │        │    species   │
  └───────┘ └────────┘ └────────────┘
```

**Relationship cardinality:**

| Relationship | Type | Description |
|-------------|------|-------------|
| series → sets | 1:N | One series has many sets |
| sets → cards | 1:N | One set has many cards |
| cards → card_types | 1:N | One card has 1-2 type entries |
| cards → card_dex_ids | 1:N | One card has 0-N dex ID entries |
| cards → price_snapshots | 1:N | One card has many price snapshots |
| pokemon_species → card_dex_ids | 1:N | One species appears on many cards |
| pokemon_species → pokemon_species | 1:1 | Self-referencing evolution (evolves_from) |

---

## Column vs JSONB Decisions

Every TCGdex field is either a dedicated column (queryable, filterable, ML feature) or stored in the `metadata` JSONB (preserved but not directly queried in MVP).

### Columns (queryable)

| TCGdex Field | Schema Column | Rationale |
|-------------|---------------|-----------|
| `id` | `cards.id` | Primary key, all lookups |
| `name` | `cards.name` | ML feature (#2 value driver), search, display |
| `localId` | `cards.local_id` | Secret rare derivation, set-level ordering |
| `category` | `cards.category` | Fundamental filter (Pokemon/Trainer/Energy) |
| `rarity` | `cards.rarity` | #1 value driver, ML feature |
| `hp` | `cards.hp` | ML feature, gameplay metric |
| `stage` | `cards.stage` | ML feature (#5 value driver), evolution stage |
| `suffix` | `cards.suffix` | ML feature (#5 value driver), mechanic marker |
| `illustrator` | `cards.illustrator` | #8 value driver, GROUP BY analytics |
| `retreat` | `cards.retreat_cost` | Minor ML feature |
| `evolveFrom` | `cards.evolves_from` | Evolution chain reference |
| `regulationMark` | `cards.regulation_mark` | #9 value driver, era indicator |
| `energyType` | `cards.energy_type` | Energy card classification |
| `legal.standard` | `cards.legal_standard` | Legality filter |
| `legal.expanded` | `cards.legal_expanded` | Legality filter |
| `types[]` | `card_types` join table | ML feature, type-based queries |
| `dexId[]` | `card_dex_ids` join table | Pokemon identity join, multi-Pokemon cards |
| `set.id` | `cards.set_id` | FK to sets table |
| `updated` | `cards.api_updated_at` | TCGdex data freshness, incremental sync |
| — (derived) | `cards.is_secret_rare` | #7 value driver |
| — (derived) | `cards.generation` | #10 value driver |

### JSONB (stored in `metadata` or dedicated JSONB column)

| TCGdex Field | Storage | Rationale |
|-------------|---------|-----------|
| `attacks` | `cards.attacks` JSONB | Complex nested structure (cost arrays, variable damage like "20+"), array of objects. Low ML priority for MVP — attack names/damage could become features later. Dedicated JSONB column (not in metadata) for easier access. |
| `abilities` | `cards.abilities` JSONB | Array of objects with name/type/effect. Rare (~15% of cards have abilities). Dedicated JSONB column for potential Phase 2 extraction. |
| `weaknesses` | `cards.weaknesses` JSONB | Array of `{type, value}`. Derivable from card type for ML. Dedicated JSONB column. |
| `resistances` | `cards.resistances` JSONB | Array of `{type, value}`. Same rationale as weaknesses. Dedicated JSONB column. |
| `variants` | `cards.variants` JSONB | Boolean flags `{firstEdition, holo, normal, reverse, wPromo}`. Dedicated JSONB column — could promote individual fields to columns if variant analysis becomes primary use case. |
| `variants_detailed` | `cards.variants_detailed` JSONB | Array of variant objects with type/subtype/size/stamp. Critical for variant-level analysis but too complex to normalize (variable structure). Dedicated JSONB column. |
| `description` | `cards.metadata` | Flavor text — available on some modern cards only. Low ML value. In metadata. |
| `image` | `cards.image_url` | Single URL string — dedicated column for display convenience. |
| `set.cardCount` (full) | `sets.card_count_breakdown` | Variant distribution per set (firstEd/holo/normal/reverse counts). Informational, not queried. |
| `set.abbreviation` | `sets.metadata` | Official abbreviation object. Low query value — ptcgo_code covers the common case. |

### Not Stored (available in raw metadata if needed)

| TCGdex Field | Reason |
|-------------|--------|
| `set.cards[]` (from set detail) | List of card IDs — reconstructable via query |

---

## Derived Field Logic

### `is_secret_rare` (on `cards`)

**Derivation**: A card is secret rare if its numeric position exceeds the set's official card count.

```elixir
# During data ingestion:
is_secret_rare = case Integer.parse(card.local_id) do
  {num, ""} -> num > set.card_count_official
  _ -> false  # Non-numeric local_ids (promos, etc.) default to false
end
```

**Example**: Set sv01 has `card_count_official: 198`, `card_count_total: 258`. Cards with `local_id` "199" through "258" get `is_secret_rare: true`.

**Edge case**: Some `local_id` values are non-numeric (e.g., promo cards with "SWSH001"). These default to `false`.

### `generation` (on `cards`)

**Derivation**: Derived from the card's first `dex_id` via static lookup table. Cards without a dex_id (Trainers, Energy) get `NULL`.

```elixir
# Static generation boundaries (verified against PokeAPI):
@generation_ranges [
  {1..151, 1},
  {152..251, 2},
  {252..386, 3},
  {387..493, 4},
  {494..649, 5},
  {650..721, 6},
  {722..809, 7},
  {810..905, 8},
  {906..1025, 9}
]

def generation_for_dex_id(nil), do: nil
def generation_for_dex_id(dex_id) do
  Enum.find_value(@generation_ranges, fn {range, gen} ->
    if dex_id in range, do: gen
  end)
end
```

**For multi-Pokemon cards**: Use the first (lowest) dex_id. Tag Team cards featuring Pokemon from different generations get the generation of the first listed Pokemon.

### `trainer_type` (on `cards`)

**Derivation**: TCGdex does not provide an explicit trainer subtype field. This will be populated via one of:

1. **TCGdex `effect` text parsing** — Many trainer cards contain "Supporter rule" or "Stadium rule" in their effect text
2. **Supplementary data from Pokemon TCG API** — The `subtypes` field explicitly contains "Supporter", "Item", "Stadium", "Tool"
3. **Manual classification** — For cards where neither source provides the data

**For MVP**: Set to `NULL` during initial ingestion. Populate in a follow-up data enrichment pass. This field is not a top-10 value driver and won't block ML model training.

**Possible values**: `"Item"`, `"Supporter"`, `"Stadium"`, `"Tool"`, `NULL`

### CardMarket variant splitting

**Derivation**: CardMarket provides flat pricing with base fields and `-holo` suffixed fields. During ingestion, split into two `price_snapshots` rows:

```elixir
# CardMarket base fields → variant "normal"
%{source: "cardmarket", variant: "normal",
  price_low: cardmarket["low"], price_avg: cardmarket["avg"],
  price_trend: cardmarket["trend"], price_avg1: cardmarket["avg1"],
  price_avg7: cardmarket["avg7"], price_avg30: cardmarket["avg30"]}

# CardMarket holo fields → variant "holo" (only if any holo field is non-null)
if cardmarket["avg-holo"] || cardmarket["low-holo"] || cardmarket["trend-holo"] do
  %{source: "cardmarket", variant: "holo",
    price_low: cardmarket["low-holo"], price_avg: cardmarket["avg-holo"],
    price_trend: cardmarket["trend-holo"], price_avg1: cardmarket["avg1-holo"],
    price_avg7: cardmarket["avg7-holo"], price_avg30: cardmarket["avg30-holo"]}
end
```

---

## Field Name Mapping: TCGdex → Schema

Complete mapping of every TCGdex API field to its schema location.

### Card Fields

| TCGdex Field | Schema Location | Notes |
|-------------|-----------------|-------|
| `id` | `cards.id` | PK |
| `name` | `cards.name` | |
| `localId` | `cards.local_id` | |
| `category` | `cards.category` | Was `supertype` in pokemontcg.io |
| `hp` | `cards.hp` | Integer (TCGdex), was string in pokemontcg.io |
| `stage` | `cards.stage` | Was part of `subtypes[]` in pokemontcg.io |
| `suffix` | `cards.suffix` | Was part of `subtypes[]` in pokemontcg.io |
| `illustrator` | `cards.illustrator` | Was `artist` in pokemontcg.io |
| `evolveFrom` | `cards.evolves_from` | |
| `retreat` | `cards.retreat_cost` | Integer (TCGdex), was array in pokemontcg.io |
| `regulationMark` | `cards.regulation_mark` | |
| `energyType` | `cards.energy_type` | Not in pokemontcg.io |
| `legal.standard` | `cards.legal_standard` | |
| `legal.expanded` | `cards.legal_expanded` | |
| `rarity` | `cards.rarity` | |
| `types[]` | `card_types` rows | |
| `dexId[]` | `card_dex_ids` rows | Was `nationalPokedexNumbers` |
| `attacks[]` | `cards.attacks` (JSONB) | |
| `abilities[]` | `cards.abilities` (JSONB) | |
| `weaknesses[]` | `cards.weaknesses` (JSONB) | |
| `resistances[]` | `cards.resistances` (JSONB) | |
| `variants` | `cards.variants` (JSONB) | Not in pokemontcg.io |
| `variants_detailed` | `cards.variants_detailed` (JSONB) | Not in pokemontcg.io |
| `description` | `cards.metadata` | Flavor text, modern cards only |
| `image` | `cards.image_url` | |
| `updated` | `cards.api_updated_at` | ISO timestamp of last TCGdex update |
| `set.id` | `cards.set_id` | FK |
| `pricing.*` | `price_snapshots` rows | See pricing mapping above |

### Set Fields

| TCGdex Field | Schema Location | Notes |
|-------------|-----------------|-------|
| `id` | `sets.id` | PK |
| `name` | `sets.name` | |
| `serie.id` | `sets.series_id` | FK to `series` table |
| `releaseDate` | `sets.release_date` | ISO format in TCGdex |
| `cardCount.official` | `sets.card_count_official` | Was `printedTotal` in pokemontcg.io |
| `cardCount.total` | `sets.card_count_total` | Was `total` in pokemontcg.io |
| `cardCount.*` (full) | `sets.card_count_breakdown` (JSONB) | firstEd/holo/normal/reverse counts |
| `logo` | `sets.logo_url` | |
| `symbol` | `sets.symbol_url` | |
| `tcgOnline` | `sets.ptcgo_code` | Was `ptcgoCode` in pokemontcg.io |
| `legal.standard` | `sets.legal_standard` | |
| `legal.expanded` | `sets.legal_expanded` | |
| `abbreviation` | `sets.metadata` | |

### Series Fields

| TCGdex Field | Schema Location |
|-------------|-----------------|
| `id` | `series.id` |
| `name` | `series.name` |
| `logo` | `series.logo_url` |

---

## Index Strategy

### Query Patterns and Supporting Indexes

| Query Pattern | Frequency | Index |
|--------------|-----------|-------|
| Card by ID | Very high | PK (`cards.id`) |
| Cards in a set | High | `idx_cards_set_id` |
| Cards by name (search) | High | `idx_cards_name` |
| Cards by rarity | High | `idx_cards_rarity` |
| Cards by category filter | Medium | `idx_cards_category` |
| Cards by type (e.g., "all Fire") | Medium | `idx_card_types_type_name` |
| Cards featuring a Pokemon | Medium | `idx_card_dex_ids_dex_id` |
| Cards by illustrator | Medium | `idx_cards_illustrator` |
| Price trend for a card | Very high | `idx_price_snapshots_card_date` |
| Price by card + variant | High | `idx_price_snapshots_card_variant_date` |
| All prices on a date | Low | `idx_price_snapshots_date` |
| Sets by release date | Medium | `idx_sets_release_date` |
| Sets in a series | Low | `idx_sets_series_id` |
| Secret rare cards | Low | `idx_cards_is_secret_rare` (partial) |
| Pokemon by generation | Low | `idx_pokemon_species_generation` |
| Pokemon evolution chain | Low | `idx_pokemon_species_evolves_from` |
| Card + set + local_id unique | Constraint | `idx_cards_set_local` (unique) |

### Index Sizing Estimates

| Index | Estimated Size | Notes |
|-------|---------------|-------|
| Cards indexes (all) | ~15 MB | 22,755 rows, small columns |
| card_types index | ~2 MB | ~25,000 rows |
| card_dex_ids index | ~1.5 MB | ~20,000 rows |
| price_snapshots indexes | ~50-100 MB/year | At weekly cadence |

Total index overhead is minimal. PostgreSQL handles this easily.

---

## Data Volume Summary

| Table | Initial Rows | Growth Rate | 1-Year Projection |
|-------|-------------|-------------|-------------------|
| `series` | 21 | ~1/year | 22 |
| `sets` | 200 | ~10/year | 210 |
| `pokemon_species` | 1,025 | ~100/generation (~3yr cycle) | 1,025 |
| `cards` | 22,755 | ~1,000/year (new sets) | ~24,000 |
| `card_types` | ~25,000 | ~1,100/year | ~26,000 |
| `card_dex_ids` | ~20,000 | ~800/year | ~21,000 |
| `price_snapshots` | 0 | ~1.77M/year (weekly) | ~1.77M |

**Total storage estimate**: ~500 MB in year 1 including indexes. PostgreSQL on modest hardware (2 CPU, 4GB RAM) handles this comfortably.

---

## Sample Queries

### Card with current prices (both sources)
```sql
SELECT c.name, c.rarity, s.name AS set_name, s.release_date,
       ps.source, ps.variant, ps.price_market, ps.price_avg,
       ps.currency
FROM cards c
JOIN sets s ON c.set_id = s.id
JOIN price_snapshots ps ON c.id = ps.card_id
WHERE c.id = 'base1-4'
  AND ps.snapshot_date = (SELECT MAX(snapshot_date) FROM price_snapshots);
```

### Price trend for a card (last 90 days)
```sql
SELECT snapshot_date, source, variant, price_market, price_avg
FROM price_snapshots
WHERE card_id = 'base1-4'
  AND snapshot_date >= CURRENT_DATE - INTERVAL '90 days'
ORDER BY snapshot_date, source;
```

### All Fire-type cards with market prices
```sql
SELECT c.name, c.rarity, c.set_id, ps.price_market
FROM cards c
JOIN card_types ct ON c.id = ct.card_id
LEFT JOIN price_snapshots ps ON c.id = ps.card_id
  AND ps.source = 'tcgplayer'
  AND ps.variant = 'normal'
  AND ps.snapshot_date = (SELECT MAX(snapshot_date) FROM price_snapshots)
WHERE ct.type_name = 'Fire'
ORDER BY ps.price_market DESC NULLS LAST;
```

### All cards featuring Charizard (dex #6)
```sql
SELECT c.id, c.name, c.set_id, c.rarity, c.stage, c.suffix
FROM cards c
JOIN card_dex_ids cd ON c.id = cd.card_id
WHERE cd.dex_id = 6
ORDER BY c.set_id;
```

### Cards by illustrator with average prices
```sql
SELECT c.illustrator, COUNT(c.id) AS card_count,
       AVG(ps.price_market) AS avg_market_price
FROM cards c
LEFT JOIN price_snapshots ps ON c.id = ps.card_id
  AND ps.source = 'tcgplayer'
  AND ps.variant = 'normal'
  AND ps.snapshot_date = (SELECT MAX(snapshot_date) FROM price_snapshots)
WHERE c.illustrator IS NOT NULL
GROUP BY c.illustrator
ORDER BY avg_market_price DESC NULLS LAST
LIMIT 20;
```

### Pokemon species with card count
```sql
SELECT ps.name, ps.genus, ps.generation, ps.is_legendary,
       COUNT(cd.card_id) AS card_count
FROM pokemon_species ps
JOIN card_dex_ids cd ON ps.id = cd.dex_id
GROUP BY ps.id
ORDER BY card_count DESC
LIMIT 20;
```

### Secret rare cards by set
```sql
SELECT s.name AS set_name, c.name, c.local_id, c.rarity,
       s.card_count_official, s.card_count_total
FROM cards c
JOIN sets s ON c.set_id = s.id
WHERE c.is_secret_rare = true
ORDER BY s.release_date DESC, c.local_id;
```

---

## Appendix A: Rarity Values (39)

From TCGdex `/v2/en/rarities`:

| Category | Values |
|----------|--------|
| Classic | Common, Uncommon, Rare |
| Holo | Rare Holo, Holo Rare V, Holo Rare VMAX, Holo Rare VSTAR |
| Ultra | Ultra Rare, Hyper rare, Secret Rare |
| Illustration (SV era) | Illustration rare, Special illustration rare |
| TCG Pocket | One Diamond, Two Diamond, Three Diamond, Four Diamond, One Star, Two Star, One Shiny, Two Shiny, Three Shiny |
| Special Mechanics | Amazing Rare, Radiant Rare, Crown |
| Niche | ACE SPEC Rare, LEGEND, Mega Hyper Rare |
| Promo/None | None |

## Appendix B: Stage Values (10)

From TCGdex `/v2/en/stages`: Basic, Stage1, Stage2, BREAK, LEVEL-UP, MEGA, RESTORED, V-UNION, VMAX, VSTAR

## Appendix C: Suffix Values (7)

From TCGdex `/v2/en/suffixes`: EX, GX, Legend, Prime, SP, TAG TEAM-GX, V

## Appendix D: Type Values (11)

From TCGdex `/v2/en/types`: Colorless, Darkness, Dragon, Fairy, Fighting, Fire, Grass, Lightning, Metal, Psychic, Water

## Appendix E: TCGdex API Endpoints Used

```
GET /v2/en/series              → series table (21 entries)
GET /v2/en/sets/{id}           → sets table (200 entries, detail endpoint)
GET /v2/en/cards/{id}          → cards + card_types + card_dex_ids + price_snapshots
GET /v2/en/rarities            → Reference data (39 values)
GET /v2/en/categories          → Reference data (3 values)
GET /v2/en/types               → Reference data (11 values)
GET /v2/en/stages              → Reference data (10 values)
GET /v2/en/suffixes            → Reference data (7 values)
GET /v2/en/illustrators        → Reference data (407 values)
```

PokeAPI endpoints:
```
GET /v2/pokemon-species/{id}   → pokemon_species table (1,025 entries)
GET /v2/pokemon/{id}           → sprite_url extraction
```
