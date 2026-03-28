# Collectr (getcollectr.com) Research

**Research Date**: 2026-03-28
**Status**: Complete

---

## Executive Summary

Collectr is a Toronto-based TCG portfolio management app with 4M+ users, bootstrapped by a 5-person team. It **does have an API** (`getcollectr.com/api`) but it is gated behind an application process with no publicly visible documentation, no published endpoints, and no pricing tiers. The API is focused on "retrieving product information on collectibles" and requires approval from Collectr to access. For the Pokevestment project, Collectr's API is **not a reliable or accessible data source** compared to the Pokemon TCG API and TCGdex, which are already identified as primary/backup sources.

---

## 1. What is Collectr?

Collectr is a mobile-first portfolio tracking application for collectible trading card games. It positions itself as "the most advanced portfolio tracking app for collectible TCGs."

**Company Details**:
- **Founded**: December 2021 by Adam Hijleh, Muhammad Rashid, Abbas Ali, and Mark Hopson (former Doorr co-founders)
- **Launched**: February 2022
- **Location**: Toronto, Canada
- **Team Size**: 5 people (3 engineers, 1 PM, 1 ops)
- **Funding**: $500K friends-and-family round only (still in bank); declined VC interest including a16z
- **Revenue**: Eight-figure ARR (scaled from five-figures in ~6 months)
- **Users**: 4M+ globally, 2M+ app opens/day
- **Products Tracked**: 600M+ items worth $1.5B collectively
- **Notable Advisor**: Steve Aoki (~25K cards logged on platform)

**Core Features**:
- AI-powered card scanning (camera identification of set, version, value)
- Real-time market valuations with auto-updated pricing
- Portfolio management for raw, graded, and sealed cards
- 25+ TCGs supported (Pokemon, MTG, Yu-Gi-Oh!, Lorcana, One Piece, Digimon, Dragon Ball Super, etc.)
- Social features (follow collectors, share collections, trending cards)
- Collection completeness tracking (shows missing cards per set)
- Multi-currency and crypto valuation support
- Showcase portfolios (public profiles with collection values)
- 1,000,000+ product database

**Pricing Data Sources** (per BetaKit reporting):
- Integrated affiliate listings from **eBay** and **TCGPlayer**
- Also runs the "largest ad network dedicated to collectibles" (550M+ impressions)

---

## 2. Does Collectr Have an API?

**Yes, but it is heavily gated.**

- **API Page**: `getcollectr.com/api` (returns 403 to web crawlers; requires browser/login)
- **API Terms**: `getcollectr.com/api-terms-and-conditions.html`
- **Contact**: `contact@getcollectr.com`

### What the API Terms Reveal

**Stated Purpose**: "Empowering the community of collectors by providing access to valuable data and resources."

**Access Model**:
- Must apply at `getcollectr.com/api`
- Collectr has "sole discretion to grant or deny any request"
- May request additional information before approving
- Grants a "non-exclusive, non-transferable, limited license"
- Uses "Application Keys" for authentication (cannot be shared)

**What is Allowed**:
- Retrieving product information on collectibles
- Integrating product information within your service or application
- Personal use
- Must display "Powered by Collectr" attribution

**What is NOT Allowed**:
- Collecting content/pricing via automated means (outside official API)
- Creating competing products or services
- Reselling or commercializing the data
- Reverse engineering or derivative works
- Performance comparisons with third-party services
- Exceeding "reasonable request volume"

**Rate Limits**: Referenced but no specific numbers published. "Limitations on access, calls, or use as determined by Collectr."

**Pricing**: Not disclosed in terms or on the website. The home page hints at tiers ("Best for personal and basic needs" and "Best for power user and team agencies") but no dollar amounts are visible for API plans.

### Key Takeaway

The API exists but is:
1. **Application-gated** (you cannot simply sign up and start using it)
2. **Undocumented publicly** (no visible endpoint docs, response schemas, or rate limits)
3. **Restrictive** (no competing products, no resale, mandatory attribution)
4. **Pricing unknown** (likely requires contacting sales)

---

## 3. What Data Does Collectr Provide?

Based on app features, reviews, and API terms:

### Card Metadata (via app/scanning)
- Card name
- Set identification
- Card version/variant
- Rarity level
- Condition status
- Artist information (inferred from card database)

### Pricing Data
- Real-time market valuations (auto-updated)
- Sources: eBay completed listings, TCGPlayer affiliate data
- 2+ years of detailed pricing history (PRO feature)
- Separate tracking for raw, graded, and sealed products
- Multi-currency support

### Collection Management
- Portfolio tracking with gain/loss analytics
- Collection completeness per set
- Filtering by set, rarity, condition
- Data export (PRO feature, CSV implied)
- Graded card "Slab View" visualization

### Data Accuracy Concerns (from reviews)
- **Modern cards**: Generally accurate pricing
- **Vintage cards**: Tends to overvalue; detects vintage as re-released versions
- **Overall rating**: 4/5 from PokecardGuy review; ranked behind PriceCharting and eBay for accuracy
- **Best for**: Modern sets and multi-TCG collectors; less ideal for vintage-focused collections

---

## 4. Pricing / Plans

### Consumer App
| Plan | Price | Key Features |
|------|-------|--------------|
| **Free** | $0 | 25+ TCGs, unlimited portfolios, marketplace, social, basic search |
| **PRO** | $4.99/mo (annual) or $7.99/mo (monthly) | Unlimited scanning, 2+ year pricing history, data export, advanced filters, priority support (coming soon) |

### API Access
- **No published pricing tiers** for API access
- Terms hint at multiple tiers but prices are not public
- Likely requires direct outreach to `contact@getcollectr.com`

---

## 5. Developer Documentation

**There is no publicly available developer documentation.**

- The API page (`getcollectr.com/api`) is gated and returned 403 when crawled
- No Swagger/OpenAPI docs found
- No Postman collections found
- No GitHub repos with Collectr API client libraries or wrappers
- No developer blog posts or technical documentation
- No community-built integrations found
- The Notion page (`getcollectr.notion.site/`) exists but was not accessible

**GitHub Search Results**: No repositories related to the Collectr (getcollectr) API were found. The only "collectr" repos are unrelated projects.

**Reddit/Forum Discussions**: No developer discussions about using the Collectr API were found. Community discussion is limited to app usage and collection management.

---

## 6. Assessment for Pokevestment Project

### Pros
- Has eBay + TCGPlayer pricing data in one place
- 2+ years of historical pricing (addresses our historical data gap)
- Graded card pricing support (PSA/BGS/CGC data we currently lack)
- 1M+ product database covering extensive Pokemon card catalog
- Sealed product pricing (booster boxes, ETBs, etc.)

### Cons
- **API access is not guaranteed** (application-based, discretionary approval)
- **No public documentation** (can't evaluate endpoints or data schemas before committing)
- **Restrictive terms** (no competing products clause could be problematic depending on interpretation)
- **"Powered by Collectr" attribution required** for any integration
- **Pricing unknown** (could be prohibitively expensive for a data analytics project)
- **Data accuracy concerns with vintage cards** (overvaluation reported)
- **Tiny team** (5 people) -- API may not be well-maintained or supported
- **No developer community** (no one discussing the API publicly = no support ecosystem)

### Recommendation

**Do NOT rely on Collectr as a primary data source for Pokevestment.**

The existing strategy (Pokemon TCG API as primary + TCGdex as backup + building our own historical price snapshots) remains the better approach because:

1. **Pokemon TCG API**: Free, documented, immediate access, same TCGPlayer/CardMarket data
2. **TCGdex**: Free, no rate limits, open source, same pricing data
3. **eBay API**: Better for historical completed sales data (90 days) with full documentation

**However**, it may be worth:
- Applying for API access to evaluate what Collectr offers (especially for graded card pricing and 2+ year historical data)
- Using the Collectr PRO app ($4.99/mo) to manually export collection data for validation/comparison
- Contacting `contact@getcollectr.com` to ask specifically about: endpoint documentation, rate limits, historical pricing depth, graded card data availability, and pricing

### If Collectr API Access is Granted

It could fill two specific gaps in our current data strategy:
1. **Graded card pricing** (PSA/BGS/CGC) -- currently unavailable from Pokemon TCG API
2. **2+ years of historical pricing** -- currently we only have 30-day averages

These are Phase 2+ needs, not MVP blockers.

---

## Sources

- [Collectr Homepage](https://getcollectr.com/)
- [Collectr PRO Membership](https://getcollectr.com/pro)
- [Collectr API Access Page](https://getcollectr.com/api)
- [Collectr API Terms](https://getcollectr.com/api-terms-and-conditions.html)
- [BetaKit: How Collectr bootstrapped a trading card hobby into an eight-figure business](https://betakit.com/how-collectr-bootstrapped-a-trading-card-hobby-into-an-eight-figure-business/)
- [Fintech.ca: Toronto's Collectr Is the World's Fastest Growing Collectibles App](https://www.fintech.ca/2025/05/22/collectr-worlds-fastest-growing-collectibles-app/)
- [Poke Card Guy: Pokemon Card Values and the Best Apps](https://www.pokecardguy.com/pokemon-card-values-and-the-best-apps-for-finding-it/)
- [iPhoneApplicationList: How Collectr Brings Pokemon Card Collecting to Your iPhone](https://iphoneapplicationlist.com/2025/05/20/gotta-track-em-all-how-collectr-brings-pokemon-card-collecting-to-your-iphone/)
- [App Store Listing](https://apps.apple.com/us/app/collectr-tcg-collector-app/id1603892248)
- [Google Play Listing](https://play.google.com/store/apps/details?id=com.collectrinc.collectr&hl=en_US)
