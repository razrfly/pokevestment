# PokePredict API Evaluation Report

**Research Date**: 2026-02-11
**Phase**: 0 - API Research & Data Source Validation
**Status**: ✅ Complete

---

## Executive Summary

Phase 0 research has validated the core data infrastructure requirements for PokePredict. The most significant finding is that the **Pokemon TCG API already includes integrated pricing** from both TCGPlayer and CardMarket, dramatically simplifying the originally proposed architecture.

### Key Findings

| Category | Finding | Impact |
|----------|---------|--------|
| **Pricing** | Pokemon TCG API includes TCGPlayer + CardMarket prices | ✅ No separate price API needed |
| **Historical Data** | Only 30-day averages available | ⚠️ Must build our own historical DB |
| **Card Metadata** | 20,113 cards, 171 sets, 38 rarities | ✅ Comprehensive coverage |
| **Artist Data** | Artist field available, searchable | ✅ Artist premium strategy viable |
| **Grading Data** | No PSA API, Cloudflare protected | ❌ Defer to Phase 2+ |
| **eBay API** | Available but requires OAuth setup | ⚠️ Defer to Phase 2 |

---

## Blueprint Assumption Validation

### Validated ✅

| Assumption | Status | Notes |
|------------|--------|-------|
| Pokemon TCG API free access | ✅ Confirmed | Rate limited without API key |
| Artist field available | ✅ Confirmed | Searchable via `q=artist:NAME` |
| TCGPlayer pricing | ✅ Confirmed | Included in Pokemon TCG API |
| CardMarket pricing | ✅ Confirmed | Included with avg1/avg7/avg30 |
| Multiple rarities | ✅ Confirmed | 38 distinct rarity types |

### Invalidated ❌

| Assumption | Status | Reality |
|------------|--------|---------|
| 130,000+ cards | ❌ Wrong | Actually 20,113 cards |
| 90+ days historical | ❌ Wrong | Only 30-day averages |
| PSA API available | ❌ Wrong | No public API, Cloudflare protected |
| TCGPlayer direct API | ❌ Wrong | Affiliate-only, but data via Pokemon TCG API |

### Needs More Research ⚠️

| Assumption | Status | Action |
|------------|--------|--------|
| Pokemon Price Tracker API | ⚠️ Unknown | No public documentation found |
| PokeTrace API | ⚠️ Unknown | No documentation found |
| Tournament data API | ⚠️ Unknown | Not investigated |

---

## Recommended Architecture Changes

### Original Blueprint Architecture
```
Data Sources:
├── Pokemon TCG API → Card metadata
├── Pokemon Price Tracker → Historical prices
├── TCGPlayer API → Real-time prices
├── CardMarket API → EU prices
├── PokeTrace API → Multi-market
├── PSA API → Grading data
└── eBay API → Ground truth
```

### Revised Architecture (Based on Research)
```
Data Sources:
├── Pokemon TCG API → Card metadata + TCGPlayer + CardMarket prices
├── Daily price snapshots → Build historical database ourselves
└── [Phase 2] eBay API → Ground truth validation
```

**Simplification**: 7 data sources → 2 data sources (for MVP)

---

## API-Specific Findings

### Pokemon TCG API (pokemontcg.io)

**Status**: ✅ Primary data source

**Capabilities Confirmed**:
- Card metadata (name, type, rarity, HP, attacks, etc.)
- Artist information (searchable)
- Set information (release dates, legalities)
- TCGPlayer prices (low, mid, high, market)
- CardMarket prices (avg1, avg7, avg30, trend)
- Variant pricing (holofoil, reverse, normal)

**Limitations**:
- Rate limiting without API key
- No PSA/graded prices
- Only 30-day historical averages
- ~20K cards (not 130K as blueprint stated)

**Sample Response**: See `pokemon_tcg_api_samples.json`

### TCGdex API

**Status**: ✅ Backup/alternative source

**Advantages over Pokemon TCG API**:
- Variant details (1st edition, shadowless)
- No observed rate limiting
- Open source

**Use Case**: Fallback if Pokemon TCG API rate limited

### PSA/Grading Data

**Status**: ❌ Not viable for MVP

**Blockers**:
- No public API
- Cloudflare protection requires browser automation
- Potential TOS violations for scraping

**Recommendation**: Defer to Phase 2+

### eBay API

**Status**: ⚠️ Available but deferred

**Requirements**:
- Developer account registration
- OAuth 2.0 implementation
- Application approval

**Value**: Ground truth sales data, graded card prices

**Recommendation**: Phase 2 integration

---

## Cost Analysis

### MVP (Phase 1)

| Service | Cost | Notes |
|---------|------|-------|
| Pokemon TCG API | Free | May need API key for production |
| PostgreSQL | Free | Local dev, ~$15/mo Fly.io |
| TCGdex | Free | Open source |
| **Total** | **$0-15/mo** | |

### Production (Phase 2+)

| Service | Cost | Notes |
|---------|------|-------|
| Pokemon TCG API | Free-$? | API key may have costs |
| eBay API | Free | Standard tier sufficient |
| Server hosting | ~$50/mo | Fly.io or similar |
| **Total** | **~$50/mo** | |

---

## Risk Assessment

### Low Risk ✅

- **API Availability**: Pokemon TCG API is stable, well-maintained
- **Data Quality**: Price data matches expectations
- **Cost**: Free tier sufficient for MVP

### Medium Risk ⚠️

- **Rate Limiting**: May hit limits during bulk operations
- **Historical Data**: Must build our own database over time
- **Price Accuracy**: TCGPlayer vs CardMarket discrepancies

### High Risk ❌

- **Grading Data**: No viable path without legal risk
- **Backtesting**: Cannot validate against historical data initially

---

## Mitigation Strategies

### Rate Limiting
1. Register for Pokemon TCG API key
2. Implement request throttling
3. Cache aggressively
4. Use TCGdex as fallback

### Historical Data Gap
1. Start daily price collection immediately
2. Build 90+ days of history before ML training
3. Use eBay completed listings for initial validation

### Grading Data
1. Skip for MVP
2. Evaluate Playwright automation in Phase 2
3. Consider manual curation for top 500 cards
4. Explore partnership with PSA

---

## Go/No-Go Decision

### ✅ GO for Phase 1

**Rationale**:
1. Primary data source (Pokemon TCG API) is validated and functional
2. Pricing data is more comprehensive than expected (includes both markets)
3. Artist data enables premium analysis strategy
4. Architecture is simpler than blueprint proposed
5. Costs are minimal for MVP

**Caveats**:
- Must accept 30-day historical limitation initially
- Grading features deferred
- eBay integration deferred

---

## Recommended Phase 1 Scope

### Include
- [ ] Pokemon TCG API integration (cards, sets, prices)
- [ ] Daily price snapshot collection
- [ ] PostgreSQL schema for cards and price history
- [ ] Basic artist premium analysis
- [ ] Price movement calculations (7d, 30d)

### Exclude (Defer to Phase 2+)
- [ ] PSA/grading data
- [ ] eBay integration
- [ ] Cross-platform arbitrage
- [ ] Tournament data
- [ ] Social sentiment

---

## Next Steps

1. **Register** for Pokemon TCG API key
2. **Initialize** Elixir/Phoenix project
3. **Design** database schema based on API responses
4. **Implement** data ingestion pipeline
5. **Start** daily price collection

---

## Appendix: File References

- `pokemon_tcg_api_samples.json` - API response samples
- `price_api_comparison.md` - Detailed price source analysis
- `grading_data_sources.md` - PSA/grading investigation
- `ebay_api_evaluation.md` - eBay API analysis
- `data_source_decision.md` - Final recommendations
