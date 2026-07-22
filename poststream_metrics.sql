-- ============================================================
-- P_LIVE_ANALYTICS_T.POST_STREAM_SHIPMENT_QUERIES_V2
--
-- Grain:   time_period x seller_grouping x seller_id x metric_name
--          x numerator x denominator
-- Source:  P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
--          joined to LIVE_SELLER_UNIFIED_ONBOARDING_DIM by seller_id
-- Cohort:  account_created_ts (seller account creation date) --
--          applied uniformly to every metric
-- Scope:   Shipment / fulfillment metrics calculable from MASTER only.
--          All seven metrics below are scoped to a seller's FIRST SHOW --
--          MASTER has no lifetime/all-show shipment columns
--          (total_gmv exists lifetime, but there is no
--          total_shipped_gmv / total_shipped_order_count equivalent).
--
-- Additivity: every numerator/denominator pair here is a ratio-of-sums
-- (GMV or order-count values), so SUM(numerator) / SUM(denominator) is
-- valid at ANY rollup level (any subset of dims, any time grain).
--
-- Out of scope: SLA/handling-time-based fulfillment (no handling-time
-- source in MASTER) and BBE-based metrics (no BBE source in MASTER or
-- any pipeline table -- see dashboard data guide).
--
-- ------------------------------------------------------------
-- README -- Metric Definitions
-- ------------------------------------------------------------
-- Order Fulfilled Rate
--   At least one order from the seller's first show was shipped
--   (carrier acceptance scan recorded).
--   num: first_show_first_fulfillment_ts IS NOT NULL
--   den: first_show_txn_cnt > 0  (sellers with first-show sales)
--
-- Full Fulfillment Rate
--   Every order from the seller's first show was shipped
--   (shipped_count >= paid_count).
--   num: first_show_all_fulfilled_ts IS NOT NULL
--   den: first_show_txn_cnt > 0
--
-- Shipped GMV Rate
--   Share of first-show order GMV that was actually shipped.
--   num: first_show_shipped_gmv
--   den: first_show_gmv
--
-- Paid-to-Shipped Order Gap Rate
--   Share of paid first-show orders that were shipped -- surfaces
--   sellers who took payment but haven't fulfilled.
--   num: first_show_shipped_order_count
--   den: first_show_paid_order_count
--
-- eBay Label Usage Rate
--   Share of shipped first-show orders sent with an eBay-issued label.
--   num: first_show_ebay_label_cnt
--   den: first_show_shipped_order_count
--
-- Off-Platform Carrier Rate
--   Share of shipped first-show orders sent via the seller's own
--   carrier/label (outside eBay's label system).
--   num: first_show_off_platform_cnt
--   den: first_show_shipped_order_count
--
-- Untracked Shipment Rate
--   Share of shipped first-show orders with no tracking recorded.
--   num: first_show_untracked_cnt
--   den: first_show_shipped_order_count
-- ------------------------------------------------------------
-- ============================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.POST_STREAM_SHIPMENT_QUERIES_V2;
CREATE TABLE P_LIVE_ANALYTICS_T.POST_STREAM_SHIPMENT_QUERIES_V2 AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
),

base AS (
    SELECT
        m.user_id_ubi,
        CAST(m.account_created_ts AS DATE)           AS account_created_dt,
        m.first_show_gmv,
        m.first_show_shipped_gmv,
        m.first_show_paid_order_count,
        m.first_show_shipped_order_count,
        m.first_show_ebay_label_cnt,
        m.first_show_off_platform_cnt,
        m.first_show_untracked_cnt,
        m.first_show_txn_cnt,
        m.first_show_first_fulfillment_ts,
        m.first_show_all_fulfilled_ts,
        COALESCE(d.geography,         'Unknown')     AS geography,
        COALESCE(d.launch_phase,      'Unknown')     AS launch_phase,
        COALESCE(d.category,          'Unknown')     AS category,
        COALESCE(d.gmv_tier,          'Unknown')     AS gmv_tier,
        COALESCE(d.onboarding_method, 'Unknown')     AS onboarding_method,
        COALESCE(d.seller_background, 'Unknown')     AS seller_background,
        cal.RETAIL_YEAR,
        cal.RETAIL_WEEK,
        cal.AGE_FOR_RTL_WEEK_ID,
        cal.MONTH_ID
    FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 m
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(m.user_id_ubi AS BIGINT) = CAST(d.seller_id AS BIGINT)
    INNER JOIN cal_ref cal
        ON CAST(m.account_created_ts AS DATE) = cal.CAL_DT
    WHERE m.report_dt = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
      AND m.is_test_user = 0
      AND m.account_created_ts IS NOT NULL
),

-- One row per seller per metric (long/tall format). Every
-- numerator/denominator is a ratio-of-sums value -- GMV or order
-- counts, all scoped to first show.
metric_flags AS (

    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Order Fulfilled Rate'                                    AS metric_name,
           CAST(CASE WHEN first_show_first_fulfillment_ts IS NOT NULL THEN 1 ELSE 0 END AS DOUBLE) AS numerator,
           CAST(CASE WHEN first_show_txn_cnt > 0 THEN 1 ELSE 0 END AS DOUBLE) AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Full Fulfillment Rate'                                   AS metric_name,
           CAST(CASE WHEN first_show_all_fulfilled_ts IS NOT NULL THEN 1 ELSE 0 END AS DOUBLE) AS numerator,
           CAST(CASE WHEN first_show_txn_cnt > 0 THEN 1 ELSE 0 END AS DOUBLE) AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Shipped GMV Rate'                                        AS metric_name,
           CAST(first_show_shipped_gmv AS DOUBLE)                    AS numerator,
           CAST(first_show_gmv AS DOUBLE)                            AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Paid-to-Shipped Order Gap Rate'                          AS metric_name,
           CAST(first_show_shipped_order_count AS DOUBLE)            AS numerator,
           CAST(first_show_paid_order_count AS DOUBLE)                AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'eBay Label Usage Rate'                                   AS metric_name,
           CAST(first_show_ebay_label_cnt AS DOUBLE)                 AS numerator,
           CAST(first_show_shipped_order_count AS DOUBLE)            AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Off-Platform Carrier Rate'                                AS metric_name,
           CAST(first_show_off_platform_cnt AS DOUBLE)               AS numerator,
           CAST(first_show_shipped_order_count AS DOUBLE)            AS denominator
    FROM base

    UNION ALL
    SELECT user_id_ubi, account_created_dt, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID,
           'Untracked Shipment Rate'                                  AS metric_name,
           CAST(first_show_untracked_cnt AS DOUBLE)                  AS numerator,
           CAST(first_show_shipped_order_count AS DOUBLE)            AS denominator
    FROM base

),

-- Relabeling passes, not aggregation -- each seller has exactly one
-- account_created_ts, so each seller-metric row appears exactly once
-- per time grain.
daily AS (
    SELECT
        DATE_FORMAT(account_created_dt, 'yyyy-MM-dd')  AS label,
        'Daily'                                         AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        user_id_ubi, metric_name, numerator, denominator
    FROM metric_flags
),

weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING)                 AS label,
        'Weekly'                                         AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        user_id_ubi, metric_name, numerator, denominator
    FROM metric_flags
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
),

monthly AS (
    SELECT
        CAST(MONTH_ID AS STRING)                        AS label,
        'Monthly'                                        AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        user_id_ubi, metric_name, numerator, denominator
    FROM metric_flags
),

overall AS (
    SELECT
        'Overall'                                        AS label,
        'Overall'                                        AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        user_id_ubi, metric_name, numerator, denominator
    FROM metric_flags
)

SELECT * FROM daily
UNION ALL SELECT * FROM weekly
UNION ALL SELECT * FROM monthly
UNION ALL SELECT * FROM overall;
