# Grading Data Sources Investigation

**Research Date**: 2026-02-11
**Status**: Complete

---

## Executive Summary

**Finding**: PSA does not offer a public API. Their website is protected by Cloudflare and requires JavaScript execution. Programmatic access to PSA population reports will require either:
1. Browser automation (Playwright)
2. Third-party aggregators
3. Manual data collection

---

## PSA (Professional Sports Authenticator)

### API Investigation

**Tested Endpoint**: `https://www.psacard.com/api/cert/{cert_number}`

**Result**: 302 redirect to `/errors/notfound`

```
HTTP/2 302
location: /errors/notfound?aspxerrorpath=/api/cert/12345678
```

**Conclusion**: No public API exists.

### Website Access

**URL**: https://www.psacard.com/cert/{cert_number}

**Result**: Cloudflare protection active
```html
<title>Just a moment...</title>
<noscript>Enable JavaScript and cookies to continue</noscript>
```

**Conclusion**: Website requires JavaScript execution. Standard HTTP requests are blocked.

### Available Data (via website)

Per certificate lookup:
- Grade (1-10, plus qualifiers like OC, MC, etc.)
- Card description
- Year
- Brand/Set
- Certification date
- Population at time of grading (sometimes)

### Population Reports

**URL**: https://www.psacard.com/pop

Population reports are available by:
- Set
- Year
- Category

Contains:
- Total graded per grade level (1-10)
- Breakdown by variant (1st edition, etc.)

---

## Alternative Grading Data Sources

### 1. PokéMetrics

**Status**: Fan-maintained PSA population tracker

**Pros**:
- Free access
- Corrections for PSA data errors
- Trend analysis

**Cons**:
- Not official
- May lag behind PSA updates
- No API (web scraping required)

### 2. CGC (Certified Guaranty Company)

**Website**: https://www.cgccards.com/

**API Status**: Unknown - needs investigation

**Notes**: Growing competitor to PSA, may have better API access

### 3. BGS (Beckett Grading Services)

**Website**: https://www.beckett.com/grading

**API Status**: Unknown - needs investigation

**Notes**: Less common for Pokemon cards

### 4. CardGrader.AI

**Description**: AI-powered card condition grading from photos

**Use Case**: Estimate pre-grading values without actual submission

**Status**: Needs investigation for API access

---

## Grading ROI Analysis Feasibility

### Required Data Points

To calculate grading ROI (key blueprint feature):
1. Raw card market price
2. PSA 10 population
3. PSA 10 market price
4. Grading cost (~$20-150 per card)
5. Expected grade distribution

### Current Data Availability

| Data Point | Source | Available |
|------------|--------|-----------|
| Raw card price | Pokemon TCG API | ✅ Yes |
| PSA 10 price | ❌ Not in API | ❌ No |
| PSA population | PSA website | ⚠️ Scraping required |
| Grading cost | PSA website | ✅ Static/known |
| Grade distribution | Historical/statistical | ⚠️ Needs research |

---

## Recommended Approach

### Phase 1 (MVP)

**Skip grading data integration**. Focus on raw card prices.

Rationale:
- No easy API access
- Scraping is complex and potentially TOS-violating
- Can add later without architectural changes

### Phase 2+

**Option A: Browser Automation**
```
Playwright → PSA cert lookup → Parse HTML → Store data
```

Pros: Gets real data
Cons: Fragile, slow, may violate TOS

**Option B: Manual Curation**
- Focus on top 100-500 high-value cards
- Manually collect PSA data periodically
- Store in database

Pros: Accurate, legal
Cons: Not scalable, labor intensive

**Option C: Third-Party Service**
- Evaluate paid services that aggregate grading data
- May exist for sports cards, check Pokemon coverage

---

## Legal/TOS Considerations

### PSA Terms of Service

Key concerns:
- Automated access likely prohibited
- Rate limiting and blocking if detected
- Potential legal action for scraping

### Recommendations

1. **Do not scrape** PSA in production without legal review
2. **Consider partnership**: Contact PSA about data licensing
3. **User-provided data**: Let users input their own cert numbers
4. **Public data only**: Use only publicly displayed, non-protected data

---

## Conclusion

Grading data integration is **not feasible for MVP** without:
- Significant scraping infrastructure
- Legal risk assessment
- Or paid third-party service

**Recommendation**: Defer to Phase 2+. Focus MVP on raw card prices which are readily available via Pokemon TCG API.
