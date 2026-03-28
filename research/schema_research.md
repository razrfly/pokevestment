# Schema Research: Relational Data & Metadata Pattern

**Research Date**: 2026-02-12
**Status**: Complete

---

## Key Principles

### 1. Metadata Column Pattern

Every table sourced from an API should include:

```sql
metadata JSONB  -- Raw API response for debugging/future extraction
```

**Rationale**:
- Enables debugging without re-fetching from API
- Future-proofs schema - can extract new columns from stored JSON
- Provides audit trail of source data
- Handles API response changes gracefully

---

## Data Sources

### Primary: Pokemon TCG API (pokemontcg.io)

All card, set, and pricing data.

### Secondary: PokeAPI (pokeapi.co)

Pokemon character data for cross-referencing:
- Evolution chains
- Pokemon types (can differ from card types)
- Generation info
- Physical stats (height, weight)
- ~1,350 Pokemon in database

---

## Available Fields from Pokemon TCG API

### Card Data (Full Response)

```json
{
  "id": "base1-4",
  "name": "Charizard",
  "supertype": "Pokémon",           // Pokemon, Trainer, Energy
  "subtypes": ["Stage 2"],          // Stage 1, Stage 2, Basic, V, VMAX, etc.
  "level": "76",                    // Older cards only
  "hp": "120",
  "types": ["Fire"],                // Card's energy types
  "evolvesFrom": "Charmeleon",      // Previous evolution
  "evolvesTo": ["..."],             // Next evolution(s) - sometimes present
  "abilities": [{                   // Pokemon Power, Ability
    "name": "Energy Burn",
    "text": "...",
    "type": "Pokémon Power"
  }],
  "attacks": [{
    "name": "Fire Spin",
    "cost": ["Fire", "Fire", "Fire", "Fire"],
    "convertedEnergyCost": 4,
    "damage": "100",
    "text": "..."
  }],
  "weaknesses": [{"type": "Water", "value": "×2"}],
  "resistances": [{"type": "Fighting", "value": "-30"}],
  "retreatCost": ["Colorless", "Colorless", "Colorless"],
  "convertedRetreatCost": 3,
  "set": {                          // Nested set object
    "id": "base1",
    "name": "Base",
    "series": "Base",
    "printedTotal": 102,
    "total": 102,
    "releaseDate": "1999/01/09",
    "ptcgoCode": "BS",
    "legalities": {...},
    "images": {...}
  },
  "number": "4",
  "artist": "Mitsuhiro Arita",
  "rarity": "Rare Holo",
  "flavorText": "Spits fire...",
  "nationalPokedexNumbers": [6],    // Links to PokeAPI!
  "legalities": {"unlimited": "Legal"},
  "images": {"small": "...", "large": "..."},
  "rules": ["..."],                 // For Trainer/Energy cards
  "tcgplayer": {...},               // Pricing
  "cardmarket": {...}               // Pricing
}
```

### Key Relational Fields

| Field | Links To | Notes |
|-------|----------|-------|
| `nationalPokedexNumbers` | Pokemon (PokeAPI) | Array - some cards have multiple Pokemon |
| `evolvesFrom` | Other cards | String - previous evolution name |
| `evolvesTo` | Other cards | Array - next evolution(s) |
| `set.id` | Sets table | Foreign key |
| `artist` | Artists table | String - normalize to table |
| `types` | Types lookup | Array - card energy types |
| `subtypes` | Subtypes lookup | Array - Stage 1, V, VMAX, etc. |
| `rarity` | Rarities lookup | String |

---

## PokeAPI Data (for Pokemon Reference)

### Pokemon Endpoint
```json
{
  "id": 6,                          // National Pokedex number
  "name": "charizard",
  "types": ["fire", "flying"],      // Game types (differ from card!)
  "height": 17,
  "weight": 905,
  "species": {"url": "..."}         // Links to species data
}
```

### Species Endpoint
```json
{
  "name": "charizard",
  "evolution_chain": {"url": "..."},
  "generation": "generation-i",
  "color": "red",
  "habitat": "mountain"
}
```

### Evolution Chain
```json
{
  "chain": {
    "species": "charmander",
    "evolves_to": [{
      "species": "charmeleon",
      "evolves_to": [{"species": "charizard"}]
    }]
  }
}
```

---

## Recommended Schema Design

### Core Tables (from Pokemon TCG API)

```
┌─────────────────────────────────────────────────────────────┐
│                         cards                                │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ "base1-4"                              │
│ name               │ "Charizard"                            │
│ supertype          │ "Pokémon"                              │
│ subtypes           │ ["Stage 2"]                            │
│ hp                 │ 120                                    │
│ types              │ ["Fire"]                               │
│ evolves_from       │ "Charmeleon"                           │
│ evolves_to         │ ["..."]                                │
│ set_id (FK)        │ "base1"                                │
│ number             │ "4"                                    │
│ artist_id (FK)     │ 1                                      │
│ rarity             │ "Rare Holo"                            │
│ flavor_text        │ "Spits fire..."                        │
│ images             │ JSONB                                  │
│ legalities         │ JSONB                                  │
│ attacks            │ JSONB (array of attack objects)        │
│ abilities          │ JSONB (array of ability objects)       │
│ weaknesses         │ JSONB                                  │
│ resistances        │ JSONB                                  │
│ retreat_cost       │ INTEGER                                │
│ metadata           │ JSONB (full API response)              │
│ inserted_at        │ timestamp                              │
│ updated_at         │ timestamp                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                         sets                                 │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ "base1"                                │
│ name               │ "Base"                                 │
│ series             │ "Base"                                 │
│ printed_total      │ 102                                    │
│ total              │ 102                                    │
│ release_date       │ 1999-01-09                             │
│ ptcgo_code         │ "BS"                                   │
│ images             │ JSONB                                  │
│ legalities         │ JSONB                                  │
│ metadata           │ JSONB (full API response)              │
│ inserted_at        │ timestamp                              │
│ updated_at         │ timestamp                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                       artists                                │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ serial                                 │
│ name (unique)      │ "Mitsuhiro Arita"                      │
│ card_count         │ calculated                             │
│ avg_price_premium  │ calculated                             │
│ inserted_at        │ timestamp                              │
│ updated_at         │ timestamp                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    price_history                             │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ bigserial                              │
│ card_id (FK)       │ "base1-4"                              │
│ recorded_at        │ date                                   │
│ variant            │ "holofoil" / "reverseHolofoil" / "normal"
│ tcg_low            │ decimal                                │
│ tcg_mid            │ decimal                                │
│ tcg_high           │ decimal                                │
│ tcg_market         │ decimal                                │
│ tcg_direct_low     │ decimal                                │
│ cm_avg_sell        │ decimal                                │
│ cm_low             │ decimal                                │
│ cm_trend           │ decimal                                │
│ cm_avg1            │ decimal                                │
│ cm_avg7            │ decimal                                │
│ cm_avg30           │ decimal                                │
│ metadata           │ JSONB (raw price response)             │
│ UNIQUE(card_id, recorded_at, variant)                       │
└─────────────────────────────────────────────────────────────┘
```

### Pokemon Reference Tables (from PokeAPI)

```
┌─────────────────────────────────────────────────────────────┐
│                       pokemon                                │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ 6 (National Pokedex number)            │
│ name               │ "charizard"                            │
│ types              │ ["fire", "flying"]                     │
│ generation         │ "generation-i"                         │
│ evolution_chain_id │ 2                                      │
│ color              │ "red"                                  │
│ habitat            │ "mountain"                             │
│ height             │ 17                                     │
│ weight             │ 905                                    │
│ metadata           │ JSONB (full API response)              │
│ inserted_at        │ timestamp                              │
│ updated_at         │ timestamp                              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                   evolution_chains                           │
├─────────────────────────────────────────────────────────────┤
│ id (PK)            │ 2                                      │
│ chain              │ JSONB (full evolution tree)            │
│ base_pokemon_id    │ 4 (Charmander)                         │
│ metadata           │ JSONB (full API response)              │
│ inserted_at        │ timestamp                              │
│ updated_at         │ timestamp                              │
└─────────────────────────────────────────────────────────────┘
```

### Join Tables

```
┌─────────────────────────────────────────────────────────────┐
│                   cards_pokemon                              │
├─────────────────────────────────────────────────────────────┤
│ card_id (FK)       │ "base1-4"                              │
│ pokemon_id (FK)    │ 6                                      │
│ PRIMARY KEY(card_id, pokemon_id)                            │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1.2 (Now)
- Create core tables: `cards`, `sets`, `artists`, `price_history`
- Include `metadata` JSONB on all tables
- Store `nationalPokedexNumbers` as array in cards table

### Phase 1.3+
- Add `pokemon` and `evolution_chains` tables
- Create `cards_pokemon` join table
- Backfill Pokemon data from PokeAPI

---

## Questions to Consider

1. **Do we need all PokeAPI data now?**
   - Recommendation: Store `nationalPokedexNumbers` in cards, add Pokemon tables later
   - Can always join/lookup later using the Pokedex numbers

2. **How to handle cards with multiple Pokemon?**
   - Some cards feature multiple Pokemon (e.g., Tag Team cards)
   - `nationalPokedexNumbers` is already an array
   - Use join table when Pokemon tables are added

3. **Card types vs Pokemon types?**
   - Card types (Fire) can differ from game types (Fire/Flying)
   - Keep both - card types for gameplay, Pokemon types for reference

4. **How much PokeAPI data to cache?**
   - ~1,350 Pokemon - small dataset
   - Can cache all or fetch on-demand
   - Recommendation: Cache all Pokemon data in Phase 2

---

## Summary

| Table | Source | Has Metadata | Notes |
|-------|--------|--------------|-------|
| `cards` | Pokemon TCG API | ✅ Yes | Core table |
| `sets` | Pokemon TCG API | ✅ Yes | |
| `artists` | Derived from cards | ❌ No | Normalized lookup |
| `price_history` | Pokemon TCG API | ✅ Yes | Daily snapshots |
| `pokemon` | PokeAPI | ✅ Yes | Phase 2 |
| `evolution_chains` | PokeAPI | ✅ Yes | Phase 2 |
| `cards_pokemon` | Join table | ❌ No | Phase 2 |
