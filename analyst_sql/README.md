# eBay Live Opening Up — Dashboard Aggregate Tables

Pre-aggregated, Tableau-ready SQL tables backing the **eBay Live Opening Up** seller dashboard. Each tab of the dashboard (Pre-Stream, Instream, Registration) is powered by one or more `CREATE TABLE` scripts that roll raw event/seller data up to Daily / Weekly / Monthly / Overall grains, so Tableau reads pre-computed aggregates instead of querying raw fact tables live.

## Directory Structure

```
ebay-live-opening-up/
├── pre_stream/                        # Pre-Stream tab (event setup, listing, funnel)
│   ├── listing_studio_metrics_store.sql   # Source metric store + all 3 aggregate CREATE TABLE statements
│   ├── TABLE_USAGE.md                     # Handoff doc: columns, label formats, Tableau filter pattern
│   └── backup/                            # Original standalone aggregate SQL files (pre-consolidation)
│       ├── pre_stream_event_metrics_agg.sql
│       ├── pre_stream_listing_metrics_agg.sql
│       └── pre_stream_funnel_agg.sql
│
├── instream/                          # Instream tab (stream-level GMV, inventory, engagement)
│   ├── hc_stream_metrics_agg.sql          # CREATE TABLE for HC_STREAM_METRICS_AGG
│   └── TABLE_USAGE.md                     # Handoff doc
│
├── registration/                      # Registration tab (seller onboarding funnel)
│   ├── seller_registration_funnel_agg.sql # CREATE TABLE for SELLER_REGISTRATION_FUNNEL_AGG
│   └── TABLE_USAGE.md                     # Handoff doc
│
└── references/                        # Reference SQL patterns used to design these tables
    └── sample_aggregate_query.sql
```

## Tables at a Glance

| Tab | Table | Source | Grain(s) |
|---|---|---|---|
| Pre-Stream | `P_LIVE_ANALYTICS_T.PRE_STREAM_EVENT_METRICS_AGG` | `COMPLETION_RATE_FINAL_T` + `COMPLETION_TIME_FINAL_T` | Daily / Weekly / Monthly / Overall |
| Pre-Stream | `P_LIVE_ANALYTICS_T.PRE_STREAM_LISTING_METRICS_AGG` | `LISTING_ADOPTION_T` + `COMPLETION_TIME_FINAL_T` | Daily / Weekly / Monthly / Overall |
| Pre-Stream | `P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG` | `LIVE_SELLER_MASTER_V2` + rebuilt funnel CTEs | Daily / Weekly / Monthly / Overall |
| Instream | `P_LIVE_ANALYTICS_T.HC_STREAM_METRICS_AGG` | `HC_STREAM_METRICS` | Daily / Weekly / Monthly / Overall |
| Registration | `P_LIVE_ANALYTICS_T.SELLER_REGISTRATION_FUNNEL_AGG` | `LIVE_SELLER_MASTER_V2` | Daily / Weekly / Monthly / Overall |

## Conventions Shared Across All Tables

- **Grain labels:** Daily = `yyyy-MM-dd`, Weekly = `YYYYRWnn` (retail week, complete weeks only), Monthly = `YYYYMM`, Overall = `'Overall'`
- **Dimensions:** `geography`, `launch_phase`, `category`, `gmv_tier`, `onboarding_method`, `seller_background` (from `LIVE_SELLER_UNIFIED_ONBOARDING_DIM`) — consistent across tables to support cross-tab Tableau filtering
- **Rates/ratios** are never pre-aggregated as `AVG()` of rates — tables store additive numerator/denominator sums, and Tableau calculated fields derive the rate at query time
- **Percentiles** (`PERCENTILE_APPROX`) are computed only at the `Overall` grain (non-re-aggregatable) and are `NULL` at Daily/Weekly/Monthly

See each subfolder's `TABLE_USAGE.md` for full column references, formulas, and known data caveats.
