-- ================================================================
-- POST-STREAM TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: Post-Stream
--
-- Source tables:
--   PRIMARY  P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 (Q1, Q5)
--
-- Mandatory filter (ALL queries):
--   WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
--     AND is_test_user = 0
--
-- ⚠ NOTE: As of Jul-14-2026 no sellers have streamed yet.
--   All first_show_* columns return NULL — this is expected.
--   Queries are structurally complete; data populates automatically
--   once sellers complete their first live stream.
--
-- ✗ INSIGHTS PAGE METRICS (4 metrics) — NO SOURCE:
--   Insights Landing Rate, Report Download Rate, Non-Default View
--   Adoption, and Repeat Insights Revisit Rate are NOT in
--   LIVE_SELLER_MASTER_V2. They require a separate UBI / page-event
--   instrumentation table. Stubs are included below.
--
-- ✗ BBE RATE — NO SOURCE:
--   BBE is not in LIVE_SELLER_MASTER_V2 or any current pipeline.
--   Stub included below.
--
-- Run order: each section is independent.
-- All rates: SUM(numerator) / SUM(denominator) — never AVG of rates.
-- ================================================================


-- ================================================================
-- SECTION 1 — L0 NORTH STARS: FULFILLMENT RATES
--   Order Fulfillment Rate (1-Order): ≥1 item shipped
--   Full Fulfillment Rate: ALL items shipped
--   GA gates: 1-Order ≥ 90%, Full ≥ 80%.
--   Hard stop: 1-Order < 60%.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    -- Sellers with any sales
    COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END)                  AS n_sellers_with_sales,

    -- 1-Order Fulfillment Rate
    COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END)               AS n_sellers_1order_fulfilled,
    ROUND(
        COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END), 0), 1)
                                                                      AS order_fulfill_rate_pct,

    -- Full Fulfillment Rate
    COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END)                 AS n_sellers_full_fulfilled,
    ROUND(
        COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END), 0), 1)
                                                                      AS full_fulfill_rate_pct,

    -- Order-level counts
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,
    SUM(first_show_shipped_order_count)                               AS total_shipped_orders

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 2 — FULFILLMENT TIMING (median + P90 days)
--   first_show_first_fulfillment_ts: timestamp of first shipment
--   first_show_all_fulfilled_ts: timestamp all items shipped
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN first_show_first_fulfillment_ts IS NOT NULL THEN 1 END)
                                                                      AS n_sellers_with_fulfillment,

    -- Median days: first show date → first item shipped
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(
                CAST(first_show_first_fulfillment_ts AS DATE),
                first_show_date
            ), 0.5), 1)                                               AS median_days_to_first_fulfillment,
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(
                CAST(first_show_first_fulfillment_ts AS DATE),
                first_show_date
            ), 0.9), 1)                                               AS p90_days_to_first_fulfillment,

    -- Median days: first show date → all items shipped
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(
                CAST(first_show_all_fulfilled_ts AS DATE),
                first_show_date
            ), 0.5), 1)                                               AS median_days_to_full_fulfillment,
    ROUND(
        PERCENTILE_APPROX(
            DATEDIFF(
                CAST(first_show_all_fulfilled_ts AS DATE),
                first_show_date
            ), 0.9), 1)                                               AS p90_days_to_full_fulfillment

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 3 — UNPAID ORDER RATE
--   Unpaid = txn created but not paid.
--   Lower is better. Guardrail watch: >6% = elevated.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    SUM(first_show_txn_cnt)                                           AS total_orders_created,
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,
    SUM(first_show_txn_cnt) - SUM(first_show_paid_order_count)        AS total_unpaid_orders,
    ROUND(
        (SUM(first_show_txn_cnt) - SUM(first_show_paid_order_count)) * 100.0
        / NULLIF(SUM(first_show_txn_cnt), 0), 1)                     AS unpaid_order_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 4 — PAID BUT UNFULFILLED (7-DAY)
--   Paid orders with no shipment event after 7 days from show.
--   ⚠ 7-day threshold requires comparing fulfillment timestamp
--   to first_show_date. Count derivable; exact SLA threshold
--   needs a fulfillment_deadline column (not confirmed in guide).
-- ================================================================

SELECT
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,
    SUM(first_show_paid_order_count) - SUM(first_show_shipped_order_count)
                                                                      AS total_paid_not_shipped,
    ROUND(
        (SUM(first_show_paid_order_count) - SUM(first_show_shipped_order_count)) * 100.0
        / NULLIF(SUM(first_show_paid_order_count), 0), 1)            AS paid_unfulfilled_rate_pct
    -- NOTE: this is total unshipped, not strictly 7-day SLA.
    -- To enforce 7-day window, add: AND first_show_date <= DATE_SUB(CURRENT_DATE(), 7)

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1
  AND first_show_date <= DATE_SUB(CURRENT_DATE(), 7);  -- only cohorts old enough to evaluate


-- ================================================================
-- SECTION 5 — 21-DAY SELLER RETENTION RATE
--   Sellers with ≥1 show between day 8 and day 21 post first show.
--   LIVE_SELLER_MASTER_V2 has no pre-built d8–21 flag;
--   derived using DATEDIFF(last_show_date, first_show_date).
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
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0), 1)
                                                                      AS retention_21d_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 6 — 21-DAY SELLER CHURN (guardrail)
--   Hard stop: > 30% churn for ≥ 2 consecutive weeks.
--   Churn: sellers who have streamed but have no activity for 21+ days.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_ever_streamed,
    COUNT(CASE WHEN
        n_first_show >= 1
        AND days_since_last_show > 21
    THEN 1 END)                                                       AS n_churned_21d,
    ROUND(
        COUNT(CASE WHEN
            n_first_show >= 1
            AND days_since_last_show > 21
        THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0), 1)
                                                                      AS churn_21d_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 7 — LATE SHIPMENT RATE (guardrail)
--   Label type breakdown as a proxy.
--   Exact SLA breach requires a fulfillment_deadline column
--   not confirmed in the data guide — partial derivation below.
-- ================================================================

SELECT
    SUM(first_show_shipped_order_count)                               AS total_shipped_orders,

    -- Label type breakdown (shipping method distribution)
    SUM(first_show_ebay_label_cnt)                                    AS orders_ebay_label,
    SUM(first_show_off_platform_cnt)                                  AS orders_off_platform,
    SUM(first_show_untracked_cnt)                                     AS orders_untracked,

    -- eBay label adoption (proxy for trackable shipments)
    ROUND(
        SUM(first_show_ebay_label_cnt) * 100.0
        / NULLIF(SUM(first_show_shipped_order_count), 0), 1)         AS ebay_label_pct,
    ROUND(
        SUM(first_show_untracked_cnt) * 100.0
        / NULLIF(SUM(first_show_shipped_order_count), 0), 1)         AS untracked_pct
    -- NOTE: true late shipment rate requires SLA deadline column — confirm with data team.

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 8 — BBE RATE (14-DAY) — GUARDRAIL
--   ✗ SOURCE NOT IDENTIFIED — stub only.
--   BBE is not in LIVE_SELLER_MASTER_V2 or any current pipeline.
-- ================================================================

-- TODO: replace with actual BBE pipeline table once confirmed.
SELECT
    0.0                                                               AS bbe_rate_14d_pct,
    'Source TBD — not in LIVE_SELLER_MASTER_V2'                       AS data_status;


-- ================================================================
-- SECTION 9 — INSIGHTS PAGE METRICS — ALL MISSING
--   ✗ NO SOURCE — requires UBI / page-event instrumentation.
--   Four metrics: Insights Landing Rate, Report Download Rate,
--   Non-Default View Adoption, Repeat Insights Revisit Rate.
-- ================================================================

-- TODO: once LIVE_INSIGHTS_PAGE_EVENTS_T or equivalent UBI table
-- is available, implement these queries:
/*
-- Insights Landing Rate (same day)
SELECT
    n_streaming_sellers,
    n_insights_landers_1d,
    ROUND(n_insights_landers_1d * 100.0 / NULLIF(n_streaming_sellers, 0), 1) AS insights_landing_rate_1d_pct
FROM ...

-- Report Download Rate
-- Non-Default View Adoption
-- Repeat Insights Revisit Rate (sellers with 2+ sessions)
*/
SELECT 'Insights page metrics require UBI page-event instrumentation — source pending' AS data_status;


-- ================================================================
-- SECTION 10 — WEEKLY TREND (post-stream metrics by first show week)
-- ================================================================

SELECT
    DATE_FORMAT(first_show_date, 'yyyy-MM-dd')                       AS first_show_week,
    COUNT(*)                                                          AS n_sellers,

    -- Fulfillment rates
    ROUND(COUNT(CASE WHEN n_order_fulfilled >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END), 0), 1)
                                                                      AS order_fulfill_rate_pct,
    ROUND(COUNT(CASE WHEN n_all_fulfilled >= 1 THEN 1 END) * 100.0
          / NULLIF(COUNT(CASE WHEN n_show_w_sales >= 1 THEN 1 END), 0), 1)
                                                                      AS full_fulfill_rate_pct,

    -- Timing medians
    ROUND(PERCENTILE_APPROX(
        DATEDIFF(CAST(first_show_first_fulfillment_ts AS DATE), first_show_date), 0.5), 1)
                                                                      AS median_days_to_first_fulfill,
    ROUND(PERCENTILE_APPROX(
        DATEDIFF(CAST(first_show_all_fulfilled_ts AS DATE), first_show_date), 0.5), 1)
                                                                      AS median_days_to_full_fulfill,

    -- 21-day retention
    ROUND(COUNT(CASE WHEN
        n_first_show >= 1
        AND last_show_date IS NOT NULL
        AND DATEDIFF(last_show_date, first_show_date) BETWEEN 8 AND 21
    THEN 1 END) * 100.0
    / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0), 1)  AS retention_21d_rate_pct,

    -- Churn
    ROUND(COUNT(CASE WHEN n_first_show >= 1 AND days_since_last_show > 21 THEN 1 END) * 100.0
          / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0), 1)
                                                                      AS churn_21d_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1
GROUP BY DATE_FORMAT(first_show_date, 'yyyy-MM-dd')
ORDER BY first_show_week;


-- ================================================================
-- SECTION 11 — SELLER OUTREACH SNAPSHOT (lapsed + at-risk)
--   For Seller Success team: identify sellers who streamed but
--   haven't returned (lapsed) or have low fulfillment.
-- ================================================================

SELECT
    seller_id,
    seller_name,
    seller_category_name,
    first_show_date,
    last_show_date,
    days_since_last_show,
    n_first_show,
    days_to_second_show,
    first_show_paid_order_count,
    first_show_shipped_order_count,
    ok_to_email,
    ok_to_call,

    CASE
        WHEN days_since_last_show > 21            THEN 'Lapsed (>21d no stream)'
        WHEN days_since_last_show BETWEEN 14 AND 21 THEN 'At Risk (14–21d no stream)'
        WHEN n_first_show >= 1 AND days_to_second_show IS NULL THEN 'One-Time Streamer'
        WHEN n_first_show >= 2                    THEN 'Active Repeat Streamer'
        ELSE 'No Stream Yet'
    END                                                               AS seller_status

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
ORDER BY days_since_last_show DESC NULLS LAST;
