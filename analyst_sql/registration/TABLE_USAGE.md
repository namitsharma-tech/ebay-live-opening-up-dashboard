# SELLER_REGISTRATION_FUNNEL_AGG — Table Usage Guide

**Table:** `P_LIVE_ANALYTICS_T.SELLER_REGISTRATION_FUNNEL_AGG`
**SQL:** `seller_registration_funnel_agg.sql` (same folder)
**Source:** `P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2` joined to `LIVE_SELLER_UNIFIED_ONBOARDING_DIM` by `seller_id`
**Cohort anchor:** `account_created_ts` (seller account creation date)
**Scope:** No lower date bound — full cohort history (unlike pre_stream/instream which start at eBay Live launch)

This table backs the **Registration** tab of the eBay Live Opening Up dashboard: a 5-step seller onboarding funnel cohorted by account creation date.

---

## Grain & Label Format

| Timeframe | Label format | Example | Notes |
|---|---|---|---|
| `Daily` | `yyyy-MM-dd` | `2026-07-22` | One row per account-creation day |
| `Weekly` | `YYYYRWnn` | `2026RW30` | Retail week; **complete weeks only** (`AGE_FOR_RTL_WEEK_ID <= -1`) |
| `Monthly` | `YYYYMM` | `202607` | Retail month |
| `Overall` | `'Overall'` | `Overall` | All cohorts to date |

Cohort is based on when the seller **created their account**, not when they streamed — a seller who registered in June and had their first show in July is counted in the June cohort.

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

Same dimension set as `HC_STREAM_METRICS_AGG` and the pre_stream tables — enables consistent cross-tab filtering in Tableau.

---

## Funnel Step Columns

| Column | Formula | Meaning |
|---|---|---|
| `n_account_created` | `COUNT(*)` | Cohort size — all sellers with a non-null `account_created_ts` |
| `n_lpg_granted` | `SUM(activated_studio)` | Sellers granted Live Product Gate / Studio activation |
| `n_step1_first_event` | Sellers with `activated_studio=1` AND a first live event created | |
| `n_step2_first_listing` | Sellers with `activated_studio=1` AND a first listing created | |
| `n_step3_shipping_policy_added` | **Hardcoded 0** — stub, data not yet available | |
| `n_step4_tutorial_done` | **Hardcoded 0** — stub, data not yet available | |
| `n_step5_first_show` | Sellers with `activated_studio=1` AND a first live show | |

> Steps 3 and 4 are placeholders. **Exclude them from funnel visualizations** (bar/waterfall charts) until real data is wired in — including them will show a false 100%→0%→0%→X% drop.

---

## Derived Conversion Rates — Compute in Tableau

| Metric | Tableau formula |
|---|---|
| LPG / activation rate | `SUM([n_lpg_granted]) / SUM([n_account_created])` |
| Event creation rate | `SUM([n_step1_first_event]) / SUM([n_lpg_granted])` |
| Listing rate | `SUM([n_step2_first_listing]) / SUM([n_lpg_granted])` |
| First show rate | `SUM([n_step5_first_show]) / SUM([n_lpg_granted])` |
| End-to-end funnel rate | `SUM([n_step5_first_show]) / SUM([n_account_created])` |

Use `ZN()` / `IFNULL(..., 0)` around denominators to avoid divide-by-zero on sparse filter combinations.

---

## Known Caveats

1. **`report_dt` snapshot:** `LIVE_SELLER_MASTER_V2` is filtered to `MAX(report_dt)` — this table reflects the latest snapshot, not a historical time series of funnel state. Cohort membership (which day/week/month a seller falls into) is fixed by `account_created_ts`, but funnel step completion (`activated_studio`, `first_event_created_ts`, etc.) reflects the seller's state as of the latest snapshot, not as of the cohort date.
2. **No site filter** — this table is global (all `operating_site_id` values included), consistent with source query intent.
3. **Test users excluded** — `is_test_user = 0` filter applied in the base CTE.
4. Funnel counts should be monotonically non-increasing left to right (`n_account_created >= n_lpg_granted >= n_step1_first_event ...` for step 1/2, and `>= n_step5_first_show`) — see verification query in the plan.

---

## Cross-Table Note

Dimension columns (`geography`, `launch_phase`, `category`, `gmv_tier`, `onboarding_method`, `seller_background`) and grain columns (`label`, `timeframe`) are consistent across `PRE_STREAM_*_AGG`, `HC_STREAM_METRICS_AGG`, and `SELLER_REGISTRATION_FUNNEL_AGG` — enabling blended Tableau dashboards across tabs. Do not join these tables directly at the row level; each has a different grain and population (event-level, stream-level, seller-cohort-level respectively). Blend in Tableau via the shared dimension + label/timeframe fields only.
