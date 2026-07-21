# Pre-Stream Dashboard Aggregate Tables — Usage Guide

**Owner:** eBay Live Analytics team  
**Data scope:** `2026-07-17` onward (eBay Live launch date)  
**Refresh cadence:** Daily (scheduled after metric store refresh completes)

---

## Tables

| Table | Grain date | Dashboard sections |
|---|---|---|
| `P_LIVE_ANALYTICS_T.PRE_STREAM_EVENT_METRICS_AGG` | Event publication / CTA click dt | Seller Setup, Event Completion Rate, Express Listing Rate, Event Completion Time |
| `P_LIVE_ANALYTICS_T.PRE_STREAM_LISTING_METRICS_AGG` | Listing creation dt (`SLNG_LSTG_SUPER_FACT.SITE_CREATE_DATE`) | Express Listing Adoption, Avg Listings per Event, Listing Completion Time |
| `P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG` | Studio activation dt (cohort) | P0 Full Funnel |

---

## Shared columns (all tables)

| Column | Type | Description |
|---|---|---|
| `label` | STRING | Time period identifier. See format below. |
| `timeframe` | STRING | `'Daily'` / `'Weekly'` / `'Monthly'` / `'Overall'` |
| `geography` | STRING | Filter dimension. `'Unknown'` = no filter applied. |
| `launch_phase` | STRING | Filter dimension. |
| `category` | STRING | Filter dimension. |
| `gmv_tier` | STRING | Filter dimension. |
| `onboarding_method` | STRING | Filter dimension. |
| `seller_background` | STRING | Filter dimension. |

### Label formats by timeframe

| timeframe | label format | Example |
|---|---|---|
| `Daily` | `yyyy-MM-dd` | `'2026-07-22'` |
| `Weekly` | `{RETAIL_YEAR}RW{NN}` | `'2026RW29'` |
| `Monthly` | `YYYYMM` (integer as string) | `'202607'` |
| `Overall` | `'Overall'` | `'Overall'` |

---

## `PRE_STREAM_EVENT_METRICS_AGG` — Column reference

| Column | Available at | Description |
|---|---|---|
| `published_events` | D / W / M / Overall | Count of published live events (numerator from Event Completion Rate) |
| `cta_clicks` | D / W / M / Overall | Count of Create Event CTA clicks (denominator) |
| `seller_setup_started` | D / W / M / Overall | Distinct sellers who clicked CTA (denominator > 0) |
| `seller_setup_success` | D / W / M / Overall | Distinct sellers who published an event (numerator > 0) |
| `listings_completed` | D / W / M / Overall | Express listings completed (numerator from Express Listing Rate) |
| `listings_started` | D / W / M / Overall | Express listings started (denominator) |
| `event_time_total_rows` | D / W / M / Overall | Row count of events with time data |
| `event_time_matched_rows` | D / W / M / Overall | Row count with non-null diff_in_minutes |
| `event_completion_avg` | D / W / M / Overall | Average event completion time (minutes) |
| `event_completion_p50` | **Overall only** | Median completion time (NULL at D/W/M) |
| `event_completion_p75` | **Overall only** | 75th percentile (NULL at D/W/M) |
| `event_completion_p90` | **Overall only** | 90th percentile (NULL at D/W/M) |

**Compute rate in Tableau:**
```
SUM(published_events) / NULLIF(SUM(cta_clicks), 0)
```

---

## `PRE_STREAM_LISTING_METRICS_AGG` — Column reference

| Column | Available at | Description |
|---|---|---|
| `total_listings` | D / W / M / Overall | Total listings created across all live events |
| `express_listings` | D / W / M / Overall | Express (template-based) listings |
| `case_break_listings` | D / W / M / Overall | Case-break listings |
| `event_count` | D / W / M / Overall | Distinct live events with listings |
| `listing_time_total_rows` | D / W / M / Overall | Row count of listings with time data |
| `listing_time_matched_rows` | D / W / M / Overall | Row count with non-null diff_in_minutes |
| `express_listing_avg` | D / W / M / Overall | Avg completion time — express listings (minutes) |
| `express_listing_p50` | **Overall only** | Median for express listings (NULL at D/W/M) |
| `express_listing_p75` | **Overall only** | 75th pct for express listings |
| `express_listing_p90` | **Overall only** | 90th pct for express listings |
| `standard_listing_avg` | D / W / M / Overall | Avg completion time — standard listings |
| `standard_listing_p50` | **Overall only** | Median for standard listings (NULL at D/W/M) |
| `standard_listing_p75` | **Overall only** | 75th pct for standard listings |
| `standard_listing_p90` | **Overall only** | 90th pct for standard listings |

**Avg listings per event in Tableau:**
```
SUM(total_listings) / NULLIF(SUM(event_count), 0)
```

---

## `PRE_STREAM_FUNNEL_AGG` — Column reference

| Column | Available at | Description |
|---|---|---|
| `step0_setup_started` | D / W / M / Overall | Distinct sellers who activated Live Studio (cohort baseline) |
| `step1_event_created` | D / W / M / Overall | Sellers who subsequently published a live event |
| `step2_listing_ready` | D / W / M / Overall | Sellers whose event has at least one listing created |
| `step3_first_show_ready` | D / W / M / Overall | Same as step2 (first show ready = event with listing) |
| `step4_14d_first_show` | D / W / M / Overall | Sellers who streamed within 14 days of studio activation |

**Important:** The funnel uses the **activation date** as the cohort grain, not the event/stream date. A seller who activated on `2026-07-18` and streamed on `2026-07-25` appears in the `2026-07-18` daily row. This means early dates will have lower funnel completion rates until sellers have had time to progress.

**Conversion rate in Tableau:**
```
SUM(step1_event_created) / NULLIF(SUM(step0_setup_started), 0)
```

---

## Standard Tableau filter pattern

All three tables support the same filter dimensions. Apply as a single WHERE clause or as Tableau filters:

```sql
WHERE timeframe     = 'Weekly'       -- or Daily / Monthly / Overall
  AND label         = '2026RW29'     -- specific week
  AND geography     = 'US'           -- or 'Unknown' to include all
  AND launch_phase  = 'Unknown'      -- 'Unknown' = no sub-filter
  AND category      = 'Unknown'
  AND gmv_tier      = 'Unknown'
  AND onboarding_method = 'Unknown'
  AND seller_background = 'Unknown'
```

To show **all geographies combined**, filter `geography = 'Unknown'`.  
To show **a specific geography**, filter `geography = 'US'` (or whichever value).

---

## Cross-table note

`PRE_STREAM_EVENT_METRICS_AGG` and `PRE_STREAM_LISTING_METRICS_AGG` use different grain dates (event publication vs. listing creation). Do not JOIN them directly on `label` — the same `label = '2026-07-22'` means different calendar days in each table.

`PRE_STREAM_FUNNEL_AGG` is a cohort table — its Daily rows represent activation cohorts, not activity on that date.
