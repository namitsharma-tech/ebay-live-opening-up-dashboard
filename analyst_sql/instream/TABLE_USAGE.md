# HC_STREAM_METRICS_AGG — Table Usage Guide

**Table:** `P_LIVE_ANALYTICS_T.HC_STREAM_METRICS_AGG`
**SQL:** `hc_stream_metrics_agg.sql` (same folder)
**Source:** `P_LIVE_ANALYTICS_T.HC_STREAM_METRICS` (one row per `live_event_id` per `event_dt`), enriched with `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` by `seller_id`
**Scope:** `event_dt >= '2026-07-17'` (eBay Live launch date)
**Data lag:** Inherits the 2-day lag from `HC_STREAM_METRICS`

This table backs the **Instream** tab of the eBay Live Opening Up dashboard (North Star, Inventory, Auction/Bid, Viewer Engagement, Chat/Engagement Tools Adoption, Guardrails).

---

## Grain & Label Format

| Timeframe | Label format | Example | Notes |
|---|---|---|---|
| `Daily` | `yyyy-MM-dd` | `2026-07-22` | One row per calendar day |
| `Weekly` | `YYYYRWnn` | `2026RW30` | Retail week; **complete weeks only** (`AGE_FOR_RTL_WEEK_ID <= -1`) — current/partial week excluded |
| `Monthly` | `YYYYMM` | `202607` | Retail month |
| `Overall` | `'Overall'` | `Overall` | All data to date |

In Tableau, filter on `timeframe` as a parameter to switch grains, and use `label` as the x-axis / sort field.

---

## Dimension Columns (filters)

| Column | Source | Notes |
|---|---|---|
| `geography` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | `'Unknown'` if seller has no dim row |
| `launch_phase` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | |
| `category` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | |
| `gmv_tier` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | |
| `onboarding_method` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | |
| `seller_background` | `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` | |

> Note: This replaces the raw `HC_STREAM_METRICS` dims (`BSNS_VRTCL_NAME`, `FCSD_VRTCL_GRP`, `SELLER_COUNTRY`) with the standard onboarding-dim set used across all three dashboard tabs (pre_stream, instream, registration), for consistent cross-tab filtering in Tableau.

To get an "All categories" / "All geographies" total row, filter Tableau to `geography = 'Unknown' AND launch_phase = 'Unknown' AND category = 'Unknown' AND gmv_tier = 'Unknown' AND onboarding_method = 'Unknown' AND seller_background = 'Unknown'` **only if** every stream's seller is missing a dim row — otherwise, sum across all dim values in Tableau (SUM aggregation over the filtered dim set), since these are additive counts.

---

## Column Reference

### Volume
| Column | Formula | Grain availability |
|---|---|---|
| `n_streams` | `COUNT(DISTINCT live_event_id)` | All |
| `n_streaming_sellers` | `COUNT(DISTINCT seller_id)` | All |

### GMV / Duration (build derived metrics in Tableau — see below)
| Column | Meaning |
|---|---|
| `total_gmv_during` | `SUM(gmv_during)` |
| `total_items_sold_during` | `SUM(items_sold_during)` |
| `total_streaming_mins` | `SUM(event_duration_mins)` |

### Inventory
| Column | Meaning |
|---|---|
| `total_items_listed`, `total_items_pinned`, `total_items_not_pinned` | Listing counts |
| `total_bin_items`, `total_auction_items` | Format breakdown |
| `bin_items_pinned`, `auction_items_pinned` | Pinned by format |
| `auction_items_sold` | Auction items sold |
| `pinned_items_sold_during` | Sold + pinned (featured STR numerator) |
| `featured_auction_items_sold`, `featured_bin_items_sold` | Featured STR by format |

### Auction & Bid
| Column | Meaning |
|---|---|
| `n_streams_with_auctions`, `n_streams_with_bids` | Distinct stream counts |
| `auction_items_with_bids`, `total_bids`, `total_unique_bidders` | Bid volume |
| `avg_starting_bid_amt`, `avg_final_bid_amt`, `avg_bid_price_realization_pct` | `AVG()` across streams (matches source V2 SQL semantics) |
| `avg_pin_duration_proxy_mins` | `AVG()` across streams |
| `avg_pct_items_purchasable`, `avg_pct_items_visible` | `AVG()` across streams |

### Viewer Engagement
| Column | Meaning |
|---|---|
| `total_unique_viewers`, `total_quality_viewers`, `total_bounced_viewers`, `total_engaged_viewers` | `SUM()` — additive |
| `avg_watch_duration_secs`, `avg_time_in_stream_mins` | `AVG()` across streams |
| `p50_viewers_per_stream`, `p90_viewers_per_stream`, `p50_duration_mins`, `p90_duration_mins` | **`PERCENTILE_APPROX` — Overall grain only.** NULL at Daily/Weekly/Monthly (non-re-aggregatable) |

### Chat & Engagement Tools Adoption
| Column | Meaning |
|---|---|
| `n_sellers_sent_chats`, `n_sellers_pinned_chats`, `n_sellers_bookmarked_chats`, `n_sellers_saved_presets` | `COUNT(DISTINCT seller_id WHERE ... > 0)` — safe against seller-day duplication since distinctness dedupes |
| `n_sellers_quiz`, `n_sellers_poll`, `n_sellers_notice`, `n_sellers_any_tool` | Same pattern |
| `total_quiz_starts`, `total_poll_starts`, `total_notice_toggles` | `SUM()` — additive |

### Guardrails
| Column | Meaning |
|---|---|
| `n_streams_proxy_fired` | `SUM(stream_proxy_fired)` |
| `n_streams_zero_pins`, `n_streams_zero_sales` | Distinct stream counts |
| `total_listings_added_in_stream`, `total_auction_resets`, `total_users_muted` | `SUM()` — additive |

---

## Derived Metrics — Compute in Tableau, NOT Pre-Stored

Rates and ratios are **never** pre-aggregated as AVG-of-rates. Always derive from the additive numerator/denominator columns above:

| Metric | Tableau formula |
|---|---|
| GMV per streaming hour | `SUM([total_gmv_during]) / (SUM([total_streaming_mins]) / 60.0)` |
| Pin rate % | `SUM([total_items_pinned]) * 100.0 / SUM([total_items_listed])` |
| Sell-through rate (all) % | `SUM([total_items_sold_during]) * 100.0 / SUM([total_items_listed])` |
| Auction STR % | `SUM([auction_items_sold]) * 100.0 / SUM([total_auction_items])` — guard with `total_auction_items >= 5` per handoff doc |
| Featured STR % | `SUM([pinned_items_sold_during]) * 100.0 / SUM([total_items_pinned])` |
| Quality viewer rate % | `SUM([total_quality_viewers]) * 100.0 / SUM([total_unique_viewers])` |
| Bounce rate % | `SUM([total_bounced_viewers]) * 100.0 / SUM([total_unique_viewers])` |
| % sellers sent chats | `SUM([n_sellers_sent_chats]) * 100.0 / SUM([n_streaming_sellers])` |
| % sellers any tool | `SUM([n_sellers_any_tool]) * 100.0 / SUM([n_streaming_sellers])` |
| Stream proxy failure rate % | `(SUM([n_streams]) - SUM([n_streams_proxy_fired])) * 100.0 / SUM([n_streams])` |

Use `ZN()` or `IFNULL(..., 0)` around denominators in Tableau to avoid divide-by-zero on sparse filter combinations.

---

## Known Caveats (inherited from source)

1. **Pin rate / featured metrics** unreliable for the trailing 14 days (CDC overwrite issue on `LIVE_EVENT_LISTING`) — flag any dashboard view covering recent days.
2. All chat/tool adoption columns (`chats_*_global`, `*_count`) lag 3–5 days because they derive from `HC_UBI_BASE`.
3. Auction STR can exceed 100% when `total_auction_items` is near zero — apply the `>= 5` reliability guard in Tableau calculated fields or filters.
4. `chats_*_global` source columns are **seller-day totals**, not per-stream — the adoption counts here use `COUNT(DISTINCT seller_id)` which is correct regardless, but do not attempt to `SUM(chats_sent_global)` across multiple same-day streams for a seller as it would double count (this table does not expose raw chat volume for that reason).

---

## Cross-Table Note

Dimension columns (`geography`, `launch_phase`, `category`, `gmv_tier`, `onboarding_method`, `seller_background`) and grain columns (`label`, `timeframe`) are consistent across `PRE_STREAM_*_AGG`, `HC_STREAM_METRICS_AGG`, and `SELLER_REGISTRATION_FUNNEL_AGG` — enabling blended Tableau dashboards across tabs. Do not join these tables directly at the row level; each has a different grain and population (event-level, stream-level, seller-cohort-level respectively). Blend in Tableau via the shared dimension + label/timeframe fields only.
