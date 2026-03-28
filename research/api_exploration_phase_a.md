# Phase A: API Exploration & Data Mapping

> Research conducted 2026-03-28 with live API calls. All data is real, not from documentation.

## 1. API Inventory

| API | Cards | Auth | Rate Limits | Pricing | Status |
|-----|-------|------|-------------|---------|--------|
| **TCGdex** (tcgdex.dev) | 22,755 | None | None | CardMarket + TCGPlayer | Active, open source |
| **Pokemon TCG API** (pokemontcg.io) | 20,237 | Optional API key | 1000/day free, more with key | CardMarket + TCGPlayer | Merging into paid Scrydex |
| **PokeAPI** (pokeapi.co) | 1,025 species | None | ~100/min | N/A | Active |
| **Collectr** (getcollectr.com) | 200K+ | Application-based | Unknown | TCGPlayer + eBay + CardMarket | API exists, gated access |

---

## 2. TCGdex Deep Dive

### 2.1 Sample Card Response (Base Set Charizard `base1-4`)

```json
{
  "category": "Pokemon",
  "id": "base1-4",
  "illustrator": "Mitsuhiro Arita",
  "localId": "4",
  "name": "Charizard",
  "rarity": "Rare",
  "set": {
    "cardCount": { "official": 102, "total": 102 },
    "id": "base1",
    "name": "Base Set"
  },
  "variants": {
    "firstEdition": true,
    "holo": true,
    "normal": false,
    "reverse": false,
    "wPromo": false
  },
  "variants_detailed": [
    { "type": "holo", "subtype": "unlimited", "size": "standard" },
    { "type": "holo", "subtype": "shadowless", "size": "standard", "stamp": ["1st-edition"] },
    { "type": "holo", "subtype": "shadowless", "size": "standard" },
    { "type": "holo", "subtype": "1999-2000-copyright", "size": "standard" }
  ],
  "dexId": [6],
  "hp": 120,
  "types": ["Fire"],
  "evolveFrom": "Charmeleon",
  "stage": "Stage2",
  "abilities": [{ "type": "Pokemon Power", "name": "Energy Burn", "effect": "..." }],
  "attacks": [{ "cost": ["Fire","Fire","Fire","Fire"], "name": "Fire Spin", "damage": 100, "effect": "..." }],
  "weaknesses": [{ "type": "Water", "value": "×2" }],
  "resistances": [{ "type": "Fighting", "value": "-30" }],
  "retreat": 3,
  "legal": { "standard": false, "expanded": false },
  "regulationMark": null,
  "pricing": {
    "cardmarket": {
      "updated": "2026-03-28T01:49:42.000Z",
      "unit": "EUR",
      "idProduct": 273699,
      "avg": 370.07, "low": 98, "trend": 382.89,
      "avg1": 975, "avg7": 236.41, "avg30": 339.4,
      "avg-holo": null, "low-holo": null, "trend-holo": 123.63,
      "avg1-holo": 207.4, "avg7-holo": 129.55, "avg30-holo": 202.71
    },
    "tcgplayer": {
      "updated": "2026-03-27T20:04:55.000Z",
      "unit": "USD",
      "holofoil": {
        "productId": 42382,
        "lowPrice": 630, "midPrice": 744.51, "highPrice": 2000,
        "marketPrice": 495.82, "directLowPrice": 1499.99
      }
    }
  }
}
```

### 2.2 Key Findings from TCGdex

**Pricing coverage**: 100% of sampled cards have pricing data. Tested across 3 eras (base1, sm9, sv01), all 3 categories (Pokemon, Trainer, Energy), including basic energy cards and cheap commons. Both CardMarket (EUR) and TCGPlayer (USD) present on every card.

**Pricing structure**:
- CardMarket: `avg`, `low`, `trend`, `avg1`/`avg7`/`avg30` (rolling averages), separate `-holo` variants for each metric
- TCGPlayer: Nested by variant type (`normal`, `holofoil`, `reverse-holofoil`), each with `lowPrice`, `midPrice`, `highPrice`, `marketPrice`, `directLowPrice`
- Updated daily (CardMarket: 2026-03-28, TCGPlayer: 2026-03-27)

**dexId field**: Array of national Pokedex numbers. Reliably present on Pokemon cards. Multi-Pokemon cards correctly return arrays (e.g., Eevee & Snorlax GX → `[133, 143]`). Not present on Trainer/Energy cards.

**Variant data**: Two structures available:
- `variants`: Boolean flags (`firstEdition`, `holo`, `normal`, `reverse`, `wPromo`)
- `variants_detailed`: Array of objects with `type`, `subtype`, `size`, optional `stamp` array
- Shadowless, 1st Edition, 1999-2000 copyright variants are properly distinguished

**Rarity values**: 39 distinct values from the API:

| Rarity | Example Era |
|--------|-------------|
| Common, Uncommon, Rare | Classic |
| Rare Holo, Holo Rare V/VMAX/VSTAR | Modern |
| Ultra Rare, Hyper rare, Secret Rare | Chase cards |
| Illustration rare, Special illustration rare | SV era |
| One/Two/Three/Four Diamond, One/Two Star, One/Two/Three Shiny | TCG Pocket |
| Amazing Rare, Radiant Rare, Crown | Special mechanics |
| ACE SPEC Rare, LEGEND, Mega Hyper Rare | Niche |
| None | Some promos |

**Stages**: `Basic`, `Stage1`, `Stage2`, `BREAK`, `LEVEL-UP`, `MEGA`, `RESTORED`, `V-UNION`, `VMAX`, `VSTAR`

**Suffixes** (mechanic markers): `EX`, `GX`, `Legend`, `Prime`, `SP`, `TAG TEAM-GX`, `V`

**Categories**: `Pokemon`, `Trainer`, `Energy`

**Energy cards**: Have `category: "Energy"`, `energyType` (e.g., "Normal"), `stage` ("Basic" for basic energy). No `dexId`, no attacks. DO have pricing data.

**Trainer cards**: Have `category: "Trainer"`, `illustrator`, `rarity`. No `dexId`, no `types`, no attacks. Some have `hp` (e.g., Clefairy Doll). DO have pricing data.

**Secret rares**: Derivable from `localId > set.cardCount.official`. Example: sv01 has `official: 198`, `total: 258`, so cards 199-258 are secret rares.

**Set metadata**: `releaseDate` (ISO format), `serie` (with id/name), `legal`, `tcgOnline` (PTCGO code), `abbreviation`, `cardCount` (with `firstEd`/`holo`/`normal`/`reverse`/`official`/`total` breakdowns).

**Modern card extras**: `regulationMark` (D, E, F, G, H), `description` (flavor text), `legal.standard`/`legal.expanded`.

**List vs detail**: List endpoint returns only `id`, `localId`, `name`, `image`. All other fields require per-card fetch.

### 2.3 Data Counts

| Dimension | Count |
|-----------|-------|
| Total cards | 22,755 |
| Sets | 200 |
| Series | 21 |
| Illustrators | 407 |
| Rarities | 39 |
| Types | 11 (Colorless, Darkness, Dragon, Fairy, Fighting, Fire, Grass, Lightning, Metal, Psychic, Water) |
| Categories | 3 (Pokemon, Trainer, Energy) |
| Stages | 10 |
| Suffixes | 7 |

---

## 3. TCGdex vs Pokemon TCG API Comparison

### 3.1 Field-by-Field Comparison (4 cards tested: base1-4, base1-70, sm9-120, swsh1-136)

| Field | TCGdex | Pokemon TCG API | Winner |
|-------|--------|-----------------|--------|
| ID format | `base1-4` | `base1-4` | Tie (identical) |
| Name | `Charizard` | `Charizard` | Tie |
| Category/Supertype | `category: "Pokemon"` | `supertype: "Pokémon"` | Tie |
| Subtypes | `stage` + `suffix` (separate) | `subtypes: ["Stage 2"]` or `["Basic","TAG TEAM","GX"]` | **TCG API** (richer for multi-type) |
| HP | `120` (integer) | `"120"` (string) | **TCGdex** (proper type) |
| Types | `["Fire"]` | `["Fire"]` | Tie |
| Evolves from | `evolveFrom: "Charmeleon"` | `evolvesFrom: "Charmeleon"` | Tie |
| Evolves to | Not present | `evolvesTo: ["Vaporeon",...]` | **TCG API** |
| Attacks | `cost`, `name`, `effect`, `damage` | Same + `convertedEnergyCost` | **TCG API** (converted cost) |
| Abilities | Same | Same | Tie |
| Weaknesses | Same | Same | Tie |
| Resistances | Same | Same | Tie |
| Retreat cost | `retreat: 3` (integer) | `retreatCost: ["Colorless"x3]` + `convertedRetreatCost: 3` | **TCG API** (both formats) |
| Rarity | `"Rare"` | `"Rare Holo"` | **TCG API** (more specific for base1-4) |
| Illustrator/Artist | `illustrator` | `artist` | Tie |
| Flavor text | `description` (modern only) | `flavorText` | **TCG API** (more cards have it) |
| Pokedex numbers | `dexId: [6]` | `nationalPokedexNumbers: [6]` | Tie |
| Level | Not present | `level: "76"` (old cards) | **TCG API** |
| Rules | Not present | `rules: [...]` (TAG TEAM, GX rules) | **TCG API** |
| Regulation mark | `regulationMark: "D"` | `regulationMark: "D"` | Tie |
| **Variants** | `variants` + `variants_detailed` | Not present | **TCGdex** (critical advantage) |
| **1st Edition** | `variants.firstEdition`, `variants_detailed[].stamp` | Not present | **TCGdex** (critical advantage) |
| Set release date | `"1999-01-09"` (ISO) | `"1999/01/09"` (slash format) | **TCGdex** (standard format) |
| Set series | `serie: {id, name}` | `series: "Base"` (string only) | **TCGdex** (structured) |
| Set legality | `legal: {standard, expanded}` | `legalities: {unlimited, expanded, standard}` | **TCG API** (includes unlimited) |
| Card legality | `legal: {standard, expanded}` | `legalities: {unlimited, expanded}` | **TCG API** |
| Image URLs | Card image URL | Small + large URLs | **TCG API** (hi-res option) |
| PTCGO code | `tcgOnline` | `ptcgoCode` | Tie |

### 3.2 Pricing Comparison

| Aspect | TCGdex | Pokemon TCG API |
|--------|--------|-----------------|
| **Sources** | CardMarket + TCGPlayer | CardMarket + TCGPlayer |
| **TCGPlayer structure** | Nested by variant (normal/holofoil/reverse-holofoil), 5-6 price points each | Same structure, same data |
| **CardMarket structure** | Rolling averages (avg1/7/30) + holo variants, 12+ metrics | Flat structure (averageSellPrice, trendPrice, etc.), 13 metrics |
| **Freshness** | CardMarket: 2026-03-28, TCGPlayer: 2026-03-27 | CardMarket: varies (some 2025-11-25), TCGPlayer: 2026-03-28 |
| **CardMarket base1-4 avg** | 370.07 EUR | 1496.67 EUR |
| **TCGPlayer base1-4 market** | $495.82 | $495.82 |
| **Product IDs** | `idProduct` (CardMarket), `productId` (TCGPlayer) | Not exposed |

**Key pricing differences**: TCGPlayer data is identical between APIs (same source). CardMarket data differs significantly - TCGdex shows 370.07 EUR avg vs Pokemon TCG API shows 1496.67 EUR. This suggests they may be pulling different product variants or using different aggregation. TCGdex CardMarket data is more granular (separate holo metrics) and more frequently updated.

### 3.3 Primary API Decision: **TCGdex**

**Rationale**:

1. **Variant data is critical for ML and missing from Pokemon TCG API**. The `variants` and `variants_detailed` fields distinguish 1st Edition, Shadowless, Unlimited, holo vs non-holo - these are primary value drivers. Pokemon TCG API has no equivalent.

2. **More cards** (22,755 vs 20,237 = 2,518 more cards, 12.4% more coverage).

3. **No auth, no rate limits**. Pokemon TCG API limits to 1,000 requests/day without an API key.

4. **Not being deprecated**. Pokemon TCG API is merging into paid Scrydex.

5. **Fresher CardMarket data** (updated same day vs months stale on some Pokemon TCG API cards).

6. **Open source** - can inspect data pipeline, contribute fixes.

7. **Better typed data** - HP as integer, retreat as integer, ISO date format.

**What we lose**:
- `flavorText` on older cards (low ML value)
- `evolvesTo` (derivable from `evolveFrom` relationships)
- `convertedEnergyCost` on attacks (derivable from cost array length)
- `rules` text (TAG TEAM/GX rules - low ML value)
- `level` on old cards (low ML value)
- `subtypes` as array (we get `stage` + `suffix` separately, which is actually better for ML features)
- `Rare Holo` distinction (TCGdex says "Rare" for base1-4 while Pokemon TCG API says "Rare Holo" - but TCGdex has `variants.holo` to compensate)

**None of these losses impact our value prediction model.**

---

## 4. PokeAPI Evaluation

### 4.1 What PokeAPI Adds

| Field | PokeAPI Source | Example (Charizard) | ML Value |
|-------|---------------|---------------------|----------|
| `generation` | `generation.name` | `generation-i` | **Derivable** from dexId range |
| `is_legendary` | `is_legendary` | `false` | Medium - only 71 Pokemon |
| `is_mythical` | `is_mythical` | `false` | Medium - only 23 Pokemon |
| `color` | `color.name` | `red` | Low |
| `habitat` | `habitat.name` | `mountain` | Low |
| `shape` | `shape.name` | `upright` | Low |
| `base_happiness` | `base_happiness` | `70` | Low |
| `capture_rate` | `capture_rate` | `45` | Low-Medium (correlates with rarity in games) |
| `growth_rate` | `growth_rate.name` | `medium-slow` | Low |
| `egg_groups` | `egg_groups[].name` | `["monster","dragon"]` | Low |
| `evolves_from` | `evolves_from_species.name` | `charmeleon` | Already in TCGdex |

### 4.2 Generation Derivation

Generation is **perfectly derivable** from national Pokedex number. Verified against live PokeAPI data:

```
Gen 1: 1-151    (151 species)    Gen 6: 650-721   (72 species)
Gen 2: 152-251  (100 species)    Gen 7: 722-809   (88 species)
Gen 3: 252-386  (135 species)    Gen 8: 810-905   (96 species)
Gen 4: 387-493  (107 species)    Gen 9: 906-1025  (120 species)
Gen 5: 494-649  (156 species)
```

Boundary checks confirmed: Mew (#151) = Gen 1, Chikorita (#152) = Gen 2, Celebi (#251) = Gen 2, Treecko (#252) = Gen 3.

### 4.3 Legendary/Mythical Stats

- **71 legendary** Pokemon (6.9% of 1,025 species)
- **23 mythical** Pokemon (2.2% of 1,025 species)
- **94 total special** Pokemon (9.2%)
- Flags are **mutually exclusive** in PokeAPI (a Pokemon is never both)

### 4.4 Decision: **Defer PokeAPI to Phase 2**

**Rationale**:
1. **Generation**: Derivable from dexId with a simple lookup table. No API needed.
2. **Legendary/Mythical**: Only 94 Pokemon total. Can be a static lookup table of ~94 entries rather than an API dependency. Not worth adding API complexity for MVP.
3. **Other fields** (color, habitat, shape, capture_rate): Low ML value for price prediction. Capture rate has some correlation with in-game rarity but doesn't directly drive card market value.
4. **MVP Focus**: TCGdex gives us everything needed for the top 10 value drivers. PokeAPI adds marginal features.

**Phase 2 plan**: If ML models show Pokemon identity as high-importance, add a `pokemon_species` table with PokeAPI data. The 94 legendary/mythical entries can be seeded as a static migration.

---

## 4b. Collectr API Evaluation

### What Collectr Is

Collectr (getcollectr.com) is a portfolio tracking app for collectible TCGs. Not Pokemon-specific — covers 25+ TCGs. 200K+ products including **graded cards (PSA)** and **sealed products**. Claims 4M+ users.

### API Status

Collectr **does have an API** — registration at `getcollectr.com/api`, approval-based access at Collectr's sole discretion. No public documentation of endpoints, response formats, or rate limits. We have a Pro account ($4.99/month).

### What Collectr Uniquely Offers

| Data | Available Elsewhere? | Notes |
|------|---------------------|-------|
| **2+ years price history** | Not from free APIs (TCGdex/pokemontcg.io only have 30-day rolling) | Major gap-filler |
| **PSA graded card pricing** | PokeTrace ($20/mo), PokemonPriceTracker ($99/mo) | Key Phase 2 data |
| **eBay completed sales** | PokeTrace ($20/mo) | eBay Finding API deprecated Feb 2025 |
| **Sealed product pricing** | Not from card APIs | Booster boxes, ETBs, etc. |
| **Multi-TCG coverage** | Not relevant to MVP | 25+ TCGs |

### API Terms of Service (getcollectr.com/api-terms-and-conditions.html)

Reviewed 2026-03-28. Key provisions:

1. **Non-compete clause**: Cannot "develop, promote, or enable any product, application, or service similar to or that competes with Collectr's current or planned offerings"
2. **Personal use allowed**: Approved uses include "personal use or promoting access to Collectr's platform"
3. **No data resale/redistribution**: Cannot commercialize retrieved data
4. **No caching explicitly permitted**: Terms grant "temporary access" only
5. **Attribution required**: "Powered by Collectr" must be displayed prominently
6. **No public endpoint docs**: Black box until access is granted

### Assessment for Pokevestment

**For personal use**: The terms allow personal use, so as a personal portfolio/analysis tool, Collectr API access is viable. The non-compete clause targets commercial products, not personal tools.

**Unique value**: The 2+ year price history is the single most valuable data Collectr offers that free APIs don't have. This is critical for ML models that need to identify price trends over time (not just current snapshots).

**Risk**: API is a black box — no public docs means we can't evaluate data quality or coverage until access is granted. Approval is at Collectr's discretion.

### Action Item

Apply for API access. When evaluating:
- What endpoints exist?
- What's the response format?
- Rate limits?
- Does historical pricing cover variant-level data (1st Edition vs Unlimited)?
- Is graded data broken out by grade (PSA 10 vs PSA 9)?

### Decision: **Not MVP, but apply now for Phase 2**

Collectr can't be a dependency for MVP because:
1. Access isn't guaranteed (approval-based)
2. No public docs to design against
3. Free APIs (TCGdex) cover all MVP needs

But the 2+ year price history and graded pricing make it the top Phase 2 data source to pursue. Apply immediately so access is ready when we need it.

---

## 5. Field-to-Schema Mapping

### 5.1 Columns (queryable, filterable, ML features)

| API Field | Schema Column | Type | Rationale |
|-----------|--------------|------|-----------|
| `id` | `tcgdex_id` | `string` PK | Primary identifier, same format as Pokemon TCG API |
| `name` | `name` | `string` | Query, display, ML feature (character identity) |
| `localId` | `local_id` | `string` | Card number within set |
| `category` | `category` | `string` | Pokemon/Trainer/Energy - fundamental filter |
| `rarity` | `rarity` | `string` | #1 value driver |
| `hp` | `hp` | `integer` | ML feature |
| `stage` | `stage` | `string` | ML feature (Basic/Stage1/Stage2/VMAX/etc.) |
| `suffix` | `suffix` | `string` | ML feature (EX/GX/V/TAG TEAM-GX/etc.) |
| `illustrator` | `illustrator` | `string` | #8 value driver |
| `retreat` | `retreat_cost` | `integer` | Minor ML feature |
| `regulationMark` | `regulation_mark` | `string` | Legality/era indicator |
| `dexId` | — | — | See pokemon_card_dex_ids join table |
| `set.id` | `set_id` | `string` FK | Join to sets table |
| `types` | — | — | See card_types join or array |
| `evolveFrom` | `evolves_from` | `string` | Evolution chain reference |
| `legal.standard` | `legal_standard` | `boolean` | Legality filter |
| `legal.expanded` | `legal_expanded` | `boolean` | Legality filter |
| `energyType` | `energy_type` | `string` | For Energy cards only |
| `updated` | `api_updated_at` | `utc_datetime` | Data freshness tracking |
| — | `is_secret_rare` | `boolean` | Derived: `localId > set.cardCount.official` |
| — | `generation` | `integer` | Derived from dexId via lookup table |

### 5.2 JSONB Metadata (stored, not queried in MVP)

| API Field | Rationale for JSONB |
|-----------|-------------------|
| `abilities` | Array of objects, complex structure, low ML priority |
| `attacks` | Array of objects with nested cost arrays, damage can be string ("20+") |
| `weaknesses` | Array, derivable from type for ML |
| `resistances` | Array, derivable from type for ML |
| `description` / flavor text | Text blob, not ML feature |
| `image` | URL string, display only |
| `variants` | Boolean flags - could promote to columns if variant pricing becomes primary use case |
| `variants_detailed` | Complex array of objects - critical for variant-level pricing but complex to normalize |

### 5.3 Separate Tables

**`sets` table** (200 rows):

| Column | Source | Type |
|--------|--------|------|
| `id` | `set.id` | `string` PK |
| `name` | `set.name` | `string` |
| `series_id` | `set.serie.id` | `string` FK |
| `release_date` | from set detail | `date` |
| `card_count_official` | `set.cardCount.official` | `integer` |
| `card_count_total` | `set.cardCount.total` | `integer` |
| `logo_url` | `set.logo` | `string` |
| `symbol_url` | `set.symbol` | `string` |
| `legal_standard` | `set.legal.standard` | `boolean` |
| `legal_expanded` | `set.legal.expanded` | `boolean` |
| `ptcgo_code` | `set.tcgOnline` | `string` |

**`series` table** (21 rows):

| Column | Source | Type |
|--------|--------|------|
| `id` | `serie.id` | `string` PK |
| `name` | `serie.name` | `string` |
| `logo_url` | `serie.logo` | `string` |

**`card_prices` table** (price snapshots):

| Column | Type | Notes |
|--------|------|-------|
| `id` | `bigint` PK | Auto-increment |
| `card_id` | `string` FK | References cards |
| `source` | `string` | `"cardmarket"` or `"tcgplayer"` |
| `variant_type` | `string` | `"normal"`, `"holofoil"`, `"reverse-holofoil"` |
| `price_low` | `decimal` | |
| `price_mid` | `decimal` | |
| `price_high` | `decimal` | |
| `price_market` | `decimal` | |
| `price_direct_low` | `decimal` | TCGPlayer only |
| `currency` | `string` | `"USD"` or `"EUR"` |
| `fetched_at` | `utc_datetime` | When we pulled the data |
| `source_updated_at` | `utc_datetime` | When source last updated |

### 5.4 Join Tables vs Arrays

**`card_types`** - Join table recommended:
- 11 possible types
- Cards can have 1-2 types
- ML models need to query "all Fire-type cards" efficiently
- Only ~2 rows per card, so join overhead is minimal

**`card_dex_ids`** - Join table recommended:
- Multi-Pokemon cards have 2+ dex IDs (e.g., Tag Team)
- Need to query "all cards featuring Charizard (dex #6)"
- Enables easy join to future pokemon_species table

---

## 6. Answers to 12 Questions

### Q1: What percentage of cards have pricing data?

**100%** of sampled cards across all 3 eras and all 3 categories. Tested 19 cards spanning Base Set (1999), Team Up (2019), and Scarlet & Violet (2023). Every card has both CardMarket (EUR) and TCGPlayer (USD) pricing. Even basic Energy cards (Fire Energy: $0.37 market) have full pricing. Data is updated daily.

### Q2: How do multi-Pokemon cards work?

`dexId` is an **array**. Tag Team cards like Eevee & Snorlax GX return `dexId: [133, 143]`. This is why a `card_dex_ids` join table is needed instead of a single `dex_id` column. Estimated ~200-300 multi-Pokemon cards across all sets (Tag Teams, Fusion Strike, etc.).

### Q3: What data do Trainer/Energy cards have?

**Trainer cards**: `category`, `name`, `illustrator`, `rarity`, `set`, `variants`, `variants_detailed`, `legal`, `pricing`. Some have `hp` (Clefairy Doll). No `dexId`, `types`, `attacks`, `stage`, `suffix`.

**Energy cards**: Same as Trainers plus `energyType` ("Normal"), `stage` ("Basic"). No `dexId`, `types` (in card sense).

**Both have full pricing data.** A 1st Edition Base Set Trainer like Clefairy Doll has $6.77 market value. Some Energy cards from vintage sets have notable value too.

### Q4: Do we need PokeAPI for MVP?

**No.** Deferred to Phase 2.
- **Generation**: Derivable from dexId with static lookup table (verified exact boundaries)
- **Legendary/Mythical**: 94 total Pokemon - can be static table/enum, not worth API complexity
- **Other fields** (color, habitat, capture_rate): Low ML value for price prediction
- If ML models show Pokemon identity importance, add in Phase 2

### Q5: Are there fields missing from our planned schema?

**Fields in API not originally planned**:
- `variants_detailed` - Rich variant data (shadowless, subtypes, stamps) - store in JSONB for now
- `energyType` - For Energy cards specifically
- `regulationMark` - Era/legality indicator on modern cards
- `legal.standard` / `legal.expanded` - At both card and set level
- Set `cardCount.firstEd` / `cardCount.holo` / `cardCount.reverse` - Variant distribution per set
- Set `abbreviation` and `tcgOnline` (PTCGO codes)
- CardMarket `idProduct` and TCGPlayer `productId` - Useful for deep linking

**No critical gaps.** All value-driving fields are covered.

### Q6: What are the actual rate limits?

| API | Rate Limit | Measured Response Time |
|-----|-----------|----------------------|
| TCGdex | **None** | ~100-300ms per card detail |
| Pokemon TCG API | 1,000/day (free), higher with API key | ~100-200ms |
| PokeAPI | ~100 requests/minute | ~50-100ms |

TCGdex has no rate limits at all. For initial data load of 22,755 cards at ~200ms each, sequential fetching would take ~76 minutes. With parallel requests (10 concurrent), ~8 minutes.

### Q7: What are the value drivers mapped to API fields?

| Rank | Value Driver | API Field(s) | ML Feature Type |
|------|-------------|-------------|-----------------|
| 1 | **Rarity** | `rarity` (39 values) | Categorical |
| 2 | **Character identity** | `name`, `dexId` | Categorical + popularity proxy |
| 3 | **Set/era** | `set.id`, `set.releaseDate`, `set.serie` | Categorical + temporal |
| 4 | **Variant type** | `variants`, `variants_detailed`, pricing keys | Categorical |
| 5 | **Card mechanic** | `stage`, `suffix` | Categorical |
| 6 | **1st Edition** | `variants.firstEdition`, `variants_detailed[].stamp` | Binary |
| 7 | **Secret rare** | Derived: `localId > set.cardCount.official` | Binary |
| 8 | **Artist** | `illustrator` | Categorical (407 values) |
| 9 | **Legality** | `legal.standard`, `legal.expanded`, `regulationMark` | Binary + categorical |
| 10 | **Generation** | Derived from `dexId` | Ordinal (1-9) |
| 11 | **Evolution stage** | `stage` | Ordinal |
| 12 | **HP** | `hp` | Numeric |

### Q8: What value drivers are missing from API data?

| Missing Driver | Why It Matters | Availability | Phase |
|---------------|---------------|--------------|-------|
| **Card condition/grading** | PSA 10 vs raw = 10-100x price difference | No API - manual data or scraping | Phase 2+ |
| **Print run/supply** | Scarcity drives value | Not publicly available | Phase 2+ |
| **Social sentiment** | Hype cycles (YouTube, TikTok) | Social APIs or scraping | Phase 3+ |
| **Tournament results** | Competitive demand | Not in card APIs | Phase 3+ |
| **Population reports** | PSA/BGS graded counts | PSA API (limited) | Phase 2+ |
| **Legendary/Mythical** | Pokemon lore status | PokeAPI or static table | Phase 2 |

The biggest gap is **grading data** - it's the single largest price multiplier and has no API source. For MVP, we predict **raw card value** only.

### Q9: Should we track Trainer and Energy card pricing?

**Yes.** Evidence:
- Base Set Clefairy Doll (Trainer): $6.77 market
- 1st Edition Base Set Trainers can reach $50-200+
- Base Set Fighting Energy: $0.37 market (but 1st Edition versions much higher)
- Some Special Energy cards and Trainer staples have significant value
- Excluding them would miss ~30-40% of all cards

Recommendation: Track all cards in one `cards` table with `category` column as filter. ML models can include/exclude categories as features.

### Q10: Should artists be a separate table or stored as string?

**String column** recommended.

- 407 unique illustrators - manageable but not tiny
- No additional metadata per artist in the API (no bio, no country, etc.)
- Artist lookup queries work fine with indexed string column
- A separate table adds complexity with no data to put in it beyond the name
- If we later want artist-level analytics (avg card value by artist), a string column with GROUP BY works identically to a join
- Can always promote to a table later if we get artist metadata

### Q11: Should types and dex IDs use join tables or arrays?

**Join tables** recommended for both.

**card_types**:
- Only 11 possible values, cards have 1-2 types
- ML queries need "all Fire-type cards with prices" - join is natural
- PostgreSQL array would work but join is more conventional for Ecto

**card_dex_ids**:
- Multi-Pokemon cards have 2+ dex IDs
- Need "all cards featuring Charizard" queries for portfolio features
- Future join to `pokemon_species` table requires normalized IDs
- ~1.1 rows per card on average (most have 1, some have 2-3)

### Q12: How large will the price history table get?

**Calculation**:

```
Cards: 22,755
Avg variants per card with pricing: ~1.5 (some have normal+reverse+holo)
= ~34,133 price rows per snapshot

Daily snapshots for 1 year: 34,133 × 365 = ~12.5M rows/year
Daily snapshots for 5 years: ~62.5M rows

With both CardMarket + TCGPlayer: double it
= ~25M rows/year, ~125M rows over 5 years
```

**Mitigation strategies**:
1. **Weekly snapshots** instead of daily: ~3.6M rows/year (recommended for MVP)
2. **Only snapshot cards with price changes** > threshold: further reduction
3. **Partition by year**: PostgreSQL table partitioning
4. **Aggregate old data**: Keep daily for 90 days, weekly for 1 year, monthly beyond

**Recommendation for MVP**: Weekly snapshots, all cards, both sources = ~3.6M rows/year. This is well within PostgreSQL comfort zone on modest hardware.

---

## 7. Value Drivers Mapped to Schema

| Rank | Factor | Source | Schema Location | ML Feature Type | MVP |
|------|--------|--------|----------------|-----------------|-----|
| 1 | Rarity | `rarity` | `cards.rarity` | Categorical (39 vals) | Yes |
| 2 | Character identity | `name`, `dexId` | `cards.name`, `card_dex_ids` | Categorical | Yes |
| 3 | Set/era | `set.*` | `cards.set_id` → `sets.release_date`, `sets.series_id` | Temporal + categorical | Yes |
| 4 | Variant type | Pricing keys | `card_prices.variant_type` | Categorical | Yes |
| 5 | Card mechanic | `stage`, `suffix` | `cards.stage`, `cards.suffix` | Categorical | Yes |
| 6 | 1st Edition | `variants.firstEdition` | `cards.metadata` (JSONB) or derived | Binary | Yes |
| 7 | Secret rare | Derived | `cards.is_secret_rare` | Binary | Yes |
| 8 | Artist | `illustrator` | `cards.illustrator` | Categorical (407 vals) | Yes |
| 9 | Legality | `legal.*`, `regulationMark` | `cards.legal_standard`, `cards.regulation_mark` | Binary + categorical | Yes |
| 10 | Generation | Derived from dexId | `cards.generation` | Ordinal (1-9) | Yes |
| 11 | Evolution stage | `stage` | `cards.stage` | Ordinal | Yes |
| 12 | HP | `hp` | `cards.hp` | Numeric | Yes |
| — | Legendary/Mythical | PokeAPI | Static lookup or Phase 2 table | Binary | Phase 2 |
| — | Grading | None | Manual data entry | Categorical | Phase 2+ |
| — | Print run | None | Not available | Numeric | Phase 2+ |
| — | Social sentiment | Social APIs | Not available | Numeric | Phase 3+ |

---

## 8. Appendix: Raw API Response Samples

### A. TCGdex Endpoints Used

```
GET /v2/en/cards/{id}          - Card detail (all fields + pricing)
GET /v2/en/cards               - Card list (id, localId, name, image only)
GET /v2/en/sets/{id}           - Set detail with card list
GET /v2/en/sets                - All sets (id, name, cardCount)
GET /v2/en/series              - All series (21 entries)
GET /v2/en/rarities            - All rarity values (39)
GET /v2/en/categories          - All categories (3)
GET /v2/en/illustrators        - All illustrators (407)
GET /v2/en/types               - All types (11)
GET /v2/en/stages              - All stages (10)
GET /v2/en/suffixes            - All suffixes (7)
```

### B. TCGdex Pricing Structure

**CardMarket** (EUR):
```json
{
  "updated": "2026-03-28T01:49:42.000Z",
  "unit": "EUR",
  "idProduct": 273699,
  "avg": 370.07, "low": 98, "trend": 382.89,
  "avg1": 975, "avg7": 236.41, "avg30": 339.4,
  "avg-holo": null, "low-holo": null, "trend-holo": 123.63,
  "avg1-holo": 207.4, "avg7-holo": 129.55, "avg30-holo": 202.71
}
```

**TCGPlayer** (USD, nested by variant):
```json
{
  "updated": "2026-03-27T20:04:55.000Z",
  "unit": "USD",
  "holofoil": {
    "productId": 42382,
    "lowPrice": 630, "midPrice": 744.51, "highPrice": 2000,
    "marketPrice": 495.82, "directLowPrice": 1499.99
  }
}
```

Possible TCGPlayer variant keys: `normal`, `holofoil`, `reverse-holofoil`, `1stEditionHolofoil`, `1stEditionNormal`

### C. Set Detail Structure

```json
{
  "cardCount": {
    "firstEd": 102, "holo": 64, "normal": 344,
    "official": 102, "reverse": 0, "total": 102
  },
  "id": "base1",
  "legal": { "expanded": false, "standard": false },
  "name": "Base Set",
  "releaseDate": "1999-01-09",
  "serie": { "id": "base", "name": "Base" },
  "tcgOnline": "BS",
  "abbreviation": { "official": "BS" }
}
```

### D. Variant Detailed Structure

```json
[
  { "type": "holo", "subtype": "unlimited", "size": "standard" },
  { "type": "holo", "subtype": "shadowless", "size": "standard", "stamp": ["1st-edition"] },
  { "type": "holo", "subtype": "shadowless", "size": "standard" },
  { "type": "holo", "subtype": "1999-2000-copyright", "size": "standard" }
]
```

Variant `type` values: `normal`, `holo`, `reverse`
Variant `subtype` values: `unlimited`, `shadowless`, `1999-2000-copyright`
Variant `size` values: `standard`
Variant `stamp` values: `["1st-edition"]`
