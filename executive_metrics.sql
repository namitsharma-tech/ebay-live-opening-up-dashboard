-- ================================================================
-- EXECUTIVE TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: Executive
--
-- Source tables (all via LIVE_SELLER_MASTER_V2):
--   P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
--     Q1 — Cohort funnel counts (n_first_show, n_show_w_sales, etc.)
--     Q2 — Approval & onboarding timing
--     Q5 — Seller snapshot / outreach view
--
-- Mandatory filter (ALL queries):
--   WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
--     AND is_test_user = 0
--
-- ⚠ NOTE: As of Jul-14-2026 no sellers have streamed yet.
--   All first_show_* columns return NULL — this is expected.
--   Queries are structurally complete and will return data once
--   sellers begin live streaming.
--
-- Run order: each section is independent.
-- All rates: SUM(numerator) / SUM(denominator) — never AVG of rates.
-- ================================================================


-- ================================================================
-- SECTION 1 — L0 NORTH STARS: E2E Registration → Outcome Rates
--   Cohort-matured, 14-day window.
--   Numerator: sellers who reached each outcome.
--   Denominator: total_in_funnel (all sellers who entered the
--                registration flow for the program).
-- ================================================================

SELECT
    -- Denominator
    COUNT(*)                                                          AS total_in_funnel,

    -- E2E Reg → First Show Rate
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_reached_first_show,
    ROUND(
        COUNT(CASE WHEN n_first_show >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS e2e_first_show_rate_pct,

    -- E2E Reg → Show with Sales Rate
    COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END)                  AS n_show_with_sales,
    ROUND(
        COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS e2e_show_w_sales_rate_pct,

    -- E2E Reg → Order Fulfilled Rate
    COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END)               AS n_order_fulfilled,
    ROUND(
        COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS e2e_order_fulfilled_rate_pct,

    -- E2E Reg → Full Fulfillment Rate
    COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END)                 AS n_all_fulfilled,
    ROUND(
        COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS e2e_full_fulfill_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 2 — GMV PER STREAMING HOUR
--   Numerator : SUM(total_gmv) across all sellers
--   Denominator: SUM(total_streaming_min / 60)
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    SUM(total_gmv)                                                    AS total_gmv,
    ROUND(SUM(total_streaming_min) / 60.0, 1)                        AS total_streaming_hours,
    ROUND(
        SUM(total_gmv) / NULLIF(SUM(total_streaming_min) / 60.0, 0),
    2)                                                                AS gmv_per_streaming_hour

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;   -- only sellers who have streamed


-- ================================================================
-- SECTION 3 — REPEAT STREAMING RATE (14-DAY)
--   ⚠ LABEL CONFLICT: dashboard shows "7-Day Repeat" but
--   LIVE_SELLER_MASTER_V2 only surfaces days_to_second_show
--   without a 7-day pre-built flag. Using 14-day window here.
--   Rename dashboard label to "14-Day Repeat" before GA.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_first_show_sellers,
    COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END)            AS n_repeat_14d,
    ROUND(
        COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0),
    1)                                                                AS repeat_streaming_rate_14d_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 4 — ORDER FULFILLMENT RATE (guardrail cross-tab)
--   Hard stop: < 60%. GA gate: ≥ 90%.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END)                  AS n_sellers_with_sales,
    COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END)               AS n_sellers_fulfilled,
    ROUND(
        COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END), 0),
    1)                                                                AS order_fulfillment_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 5 — 21-DAY SELLER RETENTION RATE
--   Definition: sellers with ≥1 stream between day 8 and day 21
--               post first_show_date / sellers with ≥1 stream.
--   LIVE_SELLER_MASTER_V2 has no pre-built d8–21 flag; derive with
--   CASE on last_show_date and first_show_date.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_first_show_sellers,
    COUNT(CASE WHEN
        n_first_show >= 1
        AND last_show_date IS NOT NULL
        AND DATEDIFF(last_show_date, first_show_date) BETWEEN 8 AND 21
    THEN 1 END)                                                       AS n_retained_21d,
    ROUND(
        COUNT(CASE WHEN
            n_first_show >= 1
            AND last_show_date IS NOT NULL
            AND DATEDIFF(last_show_date, first_show_date) BETWEEN 8 AND 21
        THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0),
    1)                                                                AS retention_21d_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 6 — E2E VELOCITY (MEDIAN DAYS: ACCOUNT → FIRST SHOW)
--   LIVE_SELLER_MASTER_V2 has median_days_entry_to_first_show
--   but session_entry_ts is NULL for all sellers (landing page
--   event not yet captured). Using account_created_ts as start.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_first_show_sellers,
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(first_show_date, CAST(account_created_ts AS DATE)),
            0.5
        ), 1)                                                         AS median_days_acct_to_first_show,
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(first_show_date, CAST(account_created_ts AS DATE)),
            0.9
        ), 1)                                                         AS p90_days_acct_to_first_show

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1
  AND account_created_ts IS NOT NULL;


-- ================================================================
-- SECTION 7 — BBE RATE (14-DAY)
--   ✗ SOURCE NOT IDENTIFIED — stub only.
--   BBE is not in LIVE_SELLER_MASTER_V2 or any current pipeline.
--   Return 0 as placeholder until source is confirmed.
-- ================================================================

-- TODO: replace with actual BBE source table once identified.
SELECT
    0.0                                                               AS bbe_rate_14d_pct,
    'Source TBD'                                                      AS data_status;


-- ================================================================
-- SECTION 8 — S1 PROACTIVE OUTREACH
--   ✗ NOT IN LIVE_SELLER_MASTER_V2
--   Outbound seller success contacts require a separate source.
--   OpeningUp_TnS_DashInput contains UPI rates but not outreach.
-- ================================================================

-- TODO: identify outbound contact table (e.g. SELLER_SUPPORT_CONTACTS_T)
-- and join on seller_id to get proactive outreach flag.
SELECT
    0                                                                 AS n_sellers_outreached,
    0.0                                                               AS s1_proactive_outreach_rate_pct,
    'Source TBD'                                                      AS data_status;


-- ================================================================
-- SECTION 9 — S2 INBOUND GCX CONTACT RATE
--   gcx_has_inbound is a pre-built flag in LIVE_SELLER_MASTER_V2.
--   Denominator: all sellers in funnel.
-- ================================================================

SELECT
    COUNT(*)                                                          AS total_in_funnel,
    COUNT(CASE WHEN gcx_has_inbound = 1 THEN 1 END)                  AS n_gcx_inbound,
    ROUND(
        COUNT(CASE WHEN gcx_has_inbound = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS s2_inbound_gcx_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 10 — WEEKLY COHORT TREND (all L0 rates by cohort week)
--   For trend charts: partition by the week of account_created_ts
--   and compute each E2E rate per cohort.
-- ================================================================

SELECT
    DATE_FORMAT(account_created_ts, 'yyyy-MM-dd')                    AS cohort_week_start,
    COUNT(*)                                                          AS cohort_size,
    ROUND(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)                                   AS e2e_first_show_rate_pct,
    ROUND(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)                                   AS e2e_show_w_sales_rate_pct,
    ROUND(COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)                                   AS e2e_order_fulfilled_rate_pct,
    ROUND(COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)                                   AS e2e_full_fulfill_rate_pct,
    ROUND(SUM(total_gmv) / NULLIF(SUM(total_streaming_min) / 60.0, 0), 2)
                                                                      AS gmv_per_streaming_hour,
    ROUND(COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END) * 100.0
          / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0), 1)
                                                                      AS repeat_streaming_rate_14d_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND account_created_ts IS NOT NULL
GROUP BY DATE_FORMAT(account_created_ts, 'yyyy-MM-dd')
ORDER BY cohort_week_start;
