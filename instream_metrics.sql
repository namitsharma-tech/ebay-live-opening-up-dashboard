-- ================================================================
-- IN-STREAM TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: In-Stream
--
-- Source tables:
--   PRIMARY  P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 (Q1, Q5)
--              — in-stream column group (total_streaming_min,
--                total_gmv, first_show_pinned_cnt, etc.)
--
-- Mandatory filter (ALL queries):
--   WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
--     AND is_test_user = 0
--
-- ⚠ NOTE: As of Jul-14-2026 no sellers have streamed yet.
--   All in-stream columns (streaming_min, gmv, pinned_cnt, etc.)
--   return NULL — this is expected. Queries are structurally
--   complete and will return data once sellers begin streaming.
--
-- ⚠ GLOBAL PROGRAM: do NOT filter on operating_site_id.
--   The Opening Up program is global; site filtering would
--   misrepresent cohort size.
--
-- Run order: each section is independent.
-- All rates: SUM(numerator) / SUM(denominator) — never AVG of rates.
-- ================================================================


-- ================================================================
-- SECTION 1 — L0 NORTH STAR: GMV PER STREAMING HOUR
--   Numerator : total_gmv across all streaming sellers
--   Denominator: total_streaming_min / 60
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_streaming_sellers,
    SUM(total_gmv)                                                    AS total_gmv,
    ROUND(SUM(total_streaming_min) / 60.0, 1)                        AS total_streaming_hours,
    ROUND(
        SUM(total_gmv)
        / NULLIF(SUM(total_streaming_min) / 60.0, 0),
    2)                                                                AS gmv_per_streaming_hour,

    -- Average stream duration per seller
    ROUND(
        AVG(CASE WHEN total_streaming_min > 0 THEN total_streaming_min END),
    1)                                                                AS avg_stream_duration_min

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 2 — REPEAT STREAMING RATE (14-DAY)
--   Sellers who came back within 14 days of first show.
--   ⚠ Dashboard label says "7-Day" — table only surfaces 14-day.
--   Align definition before GA.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_first_show_sellers,
    COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END)            AS n_repeat_within_14d,
    ROUND(
        COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0),
    1)                                                                AS repeat_streaming_rate_14d_pct,

    -- Median days to second show (for sellers who came back)
    ROUND(
        PERCENTILE_APPROX(
            CASE WHEN days_to_second_show IS NOT NULL THEN days_to_second_show END,
            0.5),
    1)                                                                AS median_days_to_second_show

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 3 — FIRST SHOW STREAM QUALITY
--   Pinned items, GMV, order counts, label type breakdown.
--   All from first_show_* column group in LIVE_SELLER_MASTER_V2.
--   ⚠ NULL until first seller streams.
-- ================================================================

SELECT
    COUNT(CASE WHEN n_first_show >= 1 THEN 1 END)                    AS n_streaming_sellers,

    -- Items pinned during first show
    SUM(first_show_pinned_cnt)                                        AS total_items_pinned,
    ROUND(AVG(CASE WHEN n_first_show >= 1 THEN first_show_pinned_cnt END), 1)
                                                                      AS avg_items_pinned_per_seller,

    -- Transactions and orders
    SUM(first_show_txn_cnt)                                           AS total_txns,
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,

    -- GMV from first show
    SUM(first_show_gmv)                                               AS total_first_show_gmv,
    ROUND(
        SUM(first_show_gmv)
        / NULLIF(COUNT(CASE WHEN n_first_show >= 1 THEN 1 END), 0),
    2)                                                                AS avg_gmv_per_streaming_seller,

    -- Label type breakdown (shipping method)
    SUM(first_show_ebay_label_cnt)                                    AS total_ebay_label_orders,
    SUM(first_show_off_platform_cnt)                                  AS total_off_platform_orders,
    SUM(first_show_untracked_cnt)                                     AS total_untracked_orders,

    -- eBay label adoption rate
    ROUND(
        SUM(first_show_ebay_label_cnt) * 100.0
        / NULLIF(SUM(first_show_paid_order_count), 0),
    1)                                                                AS ebay_label_adoption_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 4 — UNPAID ORDER RATE (in-stream guardrail)
--   Orders created during stream that were not paid.
-- ================================================================

SELECT
    SUM(first_show_txn_cnt)                                           AS total_orders_created,
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,
    SUM(first_show_txn_cnt) - SUM(first_show_paid_order_count)        AS total_unpaid_orders,
    ROUND(
        (SUM(first_show_txn_cnt) - SUM(first_show_paid_order_count)) * 100.0
        / NULLIF(SUM(first_show_txn_cnt), 0),
    1)                                                                AS unpaid_order_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 5 — DISPUTE RATES (INR + SNAD guardrails)
--   Counts from first show. Rate = disputes / paid orders.
-- ================================================================

SELECT
    SUM(first_show_paid_order_count)                                  AS total_paid_orders,
    SUM(first_show_inr_count)                                         AS total_inr_disputes,
    SUM(first_show_snad_count)                                        AS total_snad_disputes,
    ROUND(
        SUM(first_show_inr_count) * 100.0
        / NULLIF(SUM(first_show_paid_order_count), 0),
    2)                                                                AS inr_rate_pct,
    ROUND(
        SUM(first_show_snad_count) * 100.0
        / NULLIF(SUM(first_show_paid_order_count), 0),
    2)                                                                AS snad_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1;


-- ================================================================
-- SECTION 6 — UPI RATES (1d / 4d / 7d / 14d)
--   Source: P_LIVE_ANALYTICS_T.OpeningUp_TnS_DashInput
--   ⚠ Raw queries in PDF had hardcoded seller_id = 2855317553.
--   Removed for program-wide view below.
-- ================================================================

SELECT
    COUNT(DISTINCT seller_id)                                         AS n_sellers,
    ROUND(AVG(upi_1d_rate) * 100.0, 2)                               AS avg_upi_1d_pct,
    ROUND(AVG(upi_4d_rate) * 100.0, 2)                               AS avg_upi_4d_pct,
    ROUND(AVG(upi_7d_rate) * 100.0, 2)                               AS avg_upi_7d_pct,
    ROUND(AVG(upi_14d_rate) * 100.0, 2)                              AS avg_upi_14d_pct

FROM P_LIVE_ANALYTICS_T.OpeningUp_TnS_DashInput
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
-- NOTE: verify column names against actual OpeningUp_TnS_DashInput schema.


-- ================================================================
-- SECTION 7 — WEEKLY TREND (in-stream metrics by first show week)
-- ================================================================

SELECT
    DATE_FORMAT(first_show_date, 'yyyy-MM-dd')                       AS first_show_week,
    COUNT(*)                                                          AS n_sellers,
    ROUND(SUM(total_gmv) / NULLIF(SUM(total_streaming_min) / 60.0, 0), 2)
                                                                      AS gmv_per_streaming_hour,
    ROUND(COUNT(CASE WHEN days_to_second_show <= 14 THEN 1 END) * 100.0
          / NULLIF(COUNT(*), 0), 1)                                   AS repeat_streaming_rate_14d_pct,
    ROUND(AVG(first_show_pinned_cnt), 1)                              AS avg_items_pinned,
    ROUND((SUM(first_show_txn_cnt) - SUM(first_show_paid_order_count)) * 100.0
          / NULLIF(SUM(first_show_txn_cnt), 0), 1)                   AS unpaid_order_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND n_first_show >= 1
GROUP BY DATE_FORMAT(first_show_date, 'yyyy-MM-dd')
ORDER BY first_show_week;
