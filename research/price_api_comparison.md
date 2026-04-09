# Price Data Sources Comparison

**Research Date**: 2026-02-11
**Status**: Complete

---

## Executive Summary

**Major Finding**: The Pokemon TCG API (pokemontcg.io) already includes integrated pricing from both TCGPlayer and CardMarket, eliminating the need for separate price API integrations. This significantly simplifies the architecture.

---

## Source Comparison Matrix

| Source | Has Public API | Price Data | Historical Depth | Graded Prices | Update Freq | Cost | Verdict |
|--------|---------------|------------|------------------|---------------|-------------|------|---------|
| **Pokemon TCG API** | ✅ Yes | ✅ TCGPlayer + CardMarket | 30 days (avg30) | ❌ Raw only | Daily | Free | **PRIMARY** |
| **TCGdex** | ✅ Yes | ✅ TCGPlayer + CardMarket | 30 days | ❌ Raw only | Daily | Free | **BACKUP** |
| **Pokemon Price Tracker** | ✅ Yes | ✅ TCGPlayer (condition-level) | 6 months (API plan) | ✅ eBay graded | Daily | $9.99/mo | **INTEGRATED (#101)** |
| PokeTrace | ⚠️ Unknown | Unknown | Unknown | Unknown | Unknown | Unknown | **SKIP** |
| TCGPlayer Direct | ❌ Affiliate only | N/A | N/A | N/A | N/A | Partner | **NOT AVAILABLE** |
| CardMarket Direct | ❌ Affiliate only | N/A | N/A | N/A | N/A | Partner | **NOT AVAILABLE** |
| PriceCharting | ❌ Requires key | N/A | N/A | N/A | N/A | Paid | **SKIP** |

---

## Detailed Analysis

### 1. Pokemon TCG API (pokemontcg.io) ✅ PRIMARY

**Status**: Fully functional, tested

**Pricing Data Available**:
```json
{
  "tcgplayer": {
    "prices": {
      "holofoil": {
        "low": 350.0,
        "mid": 659.99,
        "high": 1500.0,
        "market": 468.87,
        "directLow": 1299.98
      }
    }
  },
  "cardmarket": {
    "prices": {
      "averageSellPrice": 1321.25,
      "lowPrice": 475.0,
      "trendPrice": 876.51,
      "avg1": 880.0,
      "avg7": 1430.0,
      "avg30": 2427.43
    }
  }
}
```

**Pros**:
- Free to use
- Includes both TCGPlayer AND CardMarket prices
- Has 1-day, 7-day, and 30-day price averages
- Separate pricing for holofoil vs reverseHolofoil vs normal
- Artist field included for all cards
- Well-documented API
- 20,000+ cards with metadata

**Cons**:
- Rate limited without API key (504 errors on rapid requests)
- No PSA/graded card pricing
- Only 30 days of historical averages (no raw time series)
- Can't get older historical data for backtesting

**Rate Limits**:
- Without API key: ~1000 requests/day (anecdotal)
- With API key: Higher limits (registration required)

---

### 2. TCGdex API ✅ BACKUP

**Status**: Fully functional, tested

**URL**: https://api.tcgdex.net/v2/

**Pricing Data**:
```json
{
  "pricing": {
    "cardmarket": {
      "avg": 355.08,
      "low": 85,
      "trend": 322.92,
      "avg1": 271.23,
      "avg7": 334.09,
      "avg30": 340.06
    },
    "tcgplayer": {
      "holofoil": {
        "lowPrice": 350,
        "midPrice": 659.99,
        "highPrice": 1500,
        "marketPrice": 467.81
      }
    }
  }
}
```

**Pros**:
- Completely free, no rate limits observed
- Same pricing data as Pokemon TCG API
- Additional variant information (1st edition, shadowless, etc.)
- 22,755 cards in database
- Open source

**Cons**:
- Same limitations on historical data
- Slightly different response structure

**Use Case**: Fallback if Pokemon TCG API rate limited

---

### 3. Pokemon Price Tracker ✅ INTEGRATED (Issue #101)

**API**: https://www.pokemonpricetracker.com/api-docs
**Plan**: $9.99/mo (20,000 credits/day, 600,000/month)
**Coverage**: 215 sets, 50,000+ cards — all Pokemon TCG sets including ME sets

**Verified Features**:
- TCGPlayer pricing with condition-level granularity (Near Mint, Lightly Played)
- 6 months price history with daily volume counts (API plan)
- eBay graded sales (PSA, BGS, CGC, ACE, TAG) with smart market prices
- `externalCatalogId` matches our TCGdex card IDs exactly — zero mapping needed
- Bearer token auth, 60 req/min, credit-based billing

**Status**: Integrated as third price source. API client at `Pokevestment.Api.PokemonPriceTracker`.
Daily sync via `PptPriceSync` Oban worker at 7:15 AM UTC.

---

### 4. TCGPlayer Direct API ❌ NOT AVAILABLE

**Status**: Not publicly available

TCGPlayer requires affiliate/partner status for API access. Their pricing data is already available through the Pokemon TCG API integration.

---

### 5. CardMarket Direct API ❌ NOT AVAILABLE

**Status**: Requires seller/affiliate account

CardMarket API requires merchant account. Their pricing data is already available through the Pokemon TCG API integration.

---

### 6. PriceCharting ❌ REQUIRES PAID ACCESS

**Status**: Requires API key purchase

```json
{"error":"Unknown access token","status":"error"}
```

Not viable for MVP without budget allocation.

---

## Historical Data Gap Analysis

**Problem**: The blueprint assumes 90+ days of historical data for backtesting. Current findings:

| Source | Historical Depth | Format |
|--------|------------------|--------|
| Pokemon TCG API | 30 days | avg1, avg7, avg30 averages only |
| TCGdex | 30 days | Same averages |
| eBay Completed | 90 days | Individual sales (requires API) |

**Solutions**:
1. **Start collecting now**: Begin daily price snapshots to build our own historical database
2. **eBay API integration**: Get 90 days of completed sales as ground truth
3. **Third-party historical**: Investigate Pokemon Price Tracker or similar

---

## Recommendations

### For MVP (Phase 1)

1. **Primary Source**: Pokemon TCG API
   - Card metadata
   - Daily TCGPlayer/CardMarket prices
   - Artist information for premium analysis

2. **Data Collection Strategy**:
   - Daily cron job to snapshot all card prices
   - Store in TimescaleDB for time-series queries
   - Build historical dataset over time

3. **Skip for Now**:
   - Pokemon Price Tracker (unclear API access)
   - PokeTrace (no documentation found)
   - PriceCharting (paid)

### For Phase 2+

1. **eBay Completed Listings**: Ground truth validation
2. **Historical Data Service**: Evaluate paid options if needed
3. **Scraping**: Last resort for unavailable data

---

## Data Quality Notes

### Price Variance Observed

Base Set Charizard (base1-4):
- TCGPlayer market: $468.87
- CardMarket avg30: €2,427.43 (~$2,600 USD)

**Explanation**: CardMarket prices are in EUR and include different condition/grade mix. Will need normalization.

### Missing Price Data

Some cards have `null` for TCGPlayer prices but have CardMarket data (and vice versa). Need fallback logic.

---

## Next Steps

- [ ] Register for Pokemon TCG API key for higher rate limits
- [ ] Set up daily price collection job
- [ ] Design price normalization logic (USD/EUR, condition mapping)
- [ ] Evaluate eBay API for historical validation data
