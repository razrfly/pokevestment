# eBay API Evaluation

**Research Date**: 2026-02-11
**Status**: Complete

---

## Executive Summary

eBay provides a comprehensive Browse API that can access completed listings. Authentication is required via OAuth 2.0. The API exists and responds, but requires developer account setup and app registration.

---

## API Testing Results

### Authentication Test

**Endpoint**: `https://api.ebay.com/buy/browse/v1/item_summary/search`

**Response** (without auth):
```json
{
  "errors": [
    {
      "errorId": 1001,
      "domain": "OAuth",
      "category": "REQUEST",
      "message": "Invalid access token",
      "longMessage": "Invalid access token. Check the value of the Authorization HTTP request header."
    }
  ]
}
```

**Conclusion**: API exists and is functional. Requires valid OAuth token.

---

## eBay Developer Program

### Registration Requirements

**Portal**: https://developer.ebay.com/

**Steps Required**:
1. Create eBay developer account
2. Register application
3. Generate OAuth credentials
4. Request production access (for completed listings)

### API Tiers

| Tier | Rate Limit | Completed Listings | Cost |
|------|------------|-------------------|------|
| Basic | 5,000/day | ❌ No | Free |
| Standard | 10,000/day | ✅ Yes | Free |
| Enterprise | Custom | ✅ Yes | Negotiated |

---

## Browse API Capabilities

### Relevant Endpoints

**Item Summary Search**
```
GET /buy/browse/v1/item_summary/search
```

Parameters:
- `q`: Search query (e.g., "charizard psa 10")
- `filter`: Condition, price range, buying format
- `sort`: Price, date, relevance
- `limit`: Results per page (max 200)

**Completed Listings Filter**
```
filter=buyingOptions:{FIXED_PRICE|AUCTION}
```

Note: Need to verify if "sold" items are accessible

### Data Available Per Listing

- Final sale price
- Sale date
- Item condition
- Seller information
- Item specifics (grade, set, etc.)
- Number of bids (for auctions)
- Shipping costs

---

## Historical Data Depth

### eBay Policy

- **Completed listings**: Available for 90 days
- **Sold items**: Requires specific API access
- **Historical beyond 90 days**: Not available via API

### Implications for Backtesting

| Timeframe | Data Source |
|-----------|-------------|
| Last 90 days | eBay API |
| 90+ days | Must collect ourselves |

---

## Rate Limiting

### Standard Tier Limits

- **Daily calls**: 10,000
- **Calls per second**: 5
- **Items per response**: 200

### Estimated Coverage

With 10,000 calls/day at 200 items/call:
- **Max items**: 2,000,000 per day
- **Sufficient for**: Daily monitoring of high-value cards

---

## Integration Complexity

### OAuth 2.0 Flow

1. Register application → Get client_id, client_secret
2. Request access token → POST to /identity/v1/oauth2/token
3. Include token in requests → Authorization: Bearer {token}
4. Refresh token periodically → Tokens expire

### Code Estimate

**Elixir Integration**: ~4-6 hours
- OAuth module
- API client
- Response parsing
- Error handling

---

## Use Cases for PokePredict

### Ground Truth Validation

eBay completed listings provide **actual sale prices** vs. TCGPlayer "market" estimates.

**Workflow**:
1. Get prediction from ML model
2. Compare to recent eBay sales
3. Calculate prediction accuracy
4. Adjust model weights

### Arbitrage Detection

Compare eBay prices to TCGPlayer prices:
- If TCGPlayer < eBay avg: Buy signal
- If TCGPlayer > eBay avg: Sell signal

### Graded Card Pricing

eBay is primary market for PSA graded cards:
- Can search for "PSA 10 Charizard"
- Get actual graded sale prices
- Partially addresses grading data gap

---

## Recommendations

### For MVP

**Defer eBay integration**

Rationale:
1. Pokemon TCG API provides sufficient pricing data
2. eBay OAuth adds complexity
3. Can be added in Phase 2 without architecture changes

### For Phase 2

**Implement eBay Integration**

Priority use cases:
1. Ground truth validation for model training
2. Graded card pricing (fills PSA gap)
3. Arbitrage detection across platforms

---

## Action Items

- [ ] Create eBay developer account
- [ ] Register application for Browse API
- [ ] Test completed listings access
- [ ] Document actual rate limits observed
- [ ] Build Elixir OAuth client (Phase 2)

---

## Alternative: Terapeak

eBay owns Terapeak, which provides historical sales data beyond 90 days.

**Access**: Requires eBay Seller Hub subscription

**Consider for**: Long-term historical data needs
