-- ================================================================
-- PRE_STREAM_LISTING_METRICS_AGG
-- Sources : LISTING_ADOPTION_T  (listing counts per event/seller)
--         + COMPLETION_TIME_FINAL_T (listing side, metric_name = 'Express Listing Completion Time')
-- Grain   : listing creation dt (SLNG_LSTG_SUPER_FACT.SITE_CREATE_DATE)
--           → Daily / Weekly / Monthly / Overall
-- AVG     : computed at all 4 grains (additive)
-- P50/75/90 : computed at Overall grain only; split by is_express (0/1)
-- Date scope: 2026-07-17 onward (eBay Live launch)
-- ================================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.PRE_STREAM_LISTING_METRICS_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.PRE_STREAM_LISTING_METRICS_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
    WHERE CAL_DT >= '2026-07-17'
),

adoption_base AS (
    SELECT
        la.dt, la.seller_id, la.event_id,
        la.total_listings, la.express_listings, la.case_break_listings,
        cal.RETAIL_YEAR, cal.RETAIL_WEEK, cal.AGE_FOR_RTL_WEEK_ID, cal.MONTH_ID,
        COALESCE(la.geography,         'Unknown') AS geography,
        COALESCE(la.launch_phase,      'Unknown') AS launch_phase,
        COALESCE(la.category,          'Unknown') AS category,
        COALESCE(la.gmv_tier,          'Unknown') AS gmv_tier,
        COALESCE(la.onboarding_method, 'Unknown') AS onboarding_method,
        COALESCE(la.seller_background, 'Unknown') AS seller_background
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
    INNER JOIN cal_ref cal ON la.dt = cal.CAL_DT
),

listing_time_base AS (
    SELECT
        ctf.dt, ctf.diff_in_minutes, ctf.is_express,
        cal.RETAIL_YEAR, cal.RETAIL_WEEK, cal.AGE_FOR_RTL_WEEK_ID, cal.MONTH_ID,
        COALESCE(ctf.geography,         'Unknown') AS geography,
        COALESCE(ctf.launch_phase,      'Unknown') AS launch_phase,
        COALESCE(ctf.category,          'Unknown') AS category,
        COALESCE(ctf.gmv_tier,          'Unknown') AS gmv_tier,
        COALESCE(ctf.onboarding_method, 'Unknown') AS onboarding_method,
        COALESCE(ctf.seller_background, 'Unknown') AS seller_background
    FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
    INNER JOIN cal_ref cal ON ctf.dt = cal.CAL_DT
    WHERE ctf.metric_name     = 'Express Listing Completion Time'
      AND ctf.diff_in_minutes IS NOT NULL
      AND ctf.diff_in_minutes >= 0
),

-- ── ADOPTION CTEs ─────────────────────────────────────────────
adoption_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(total_listings)         AS total_listings,
           SUM(express_listings)       AS express_listings,
           SUM(case_break_listings)    AS case_break_listings,
           COUNT(DISTINCT event_id)    AS event_count
    FROM adoption_base
    GROUP BY DATE_FORMAT(dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

adoption_weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING) AS label,
        'Weekly' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        SUM(total_listings)         AS total_listings,
        SUM(express_listings)       AS express_listings,
        SUM(case_break_listings)    AS case_break_listings,
        COUNT(DISTINCT event_id)    AS event_count
    FROM adoption_base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

adoption_monthly AS (
    SELECT CAST(MONTH_ID AS STRING) AS label, 'Monthly' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(total_listings)         AS total_listings,
           SUM(express_listings)       AS express_listings,
           SUM(case_break_listings)    AS case_break_listings,
           COUNT(DISTINCT event_id)    AS event_count
    FROM adoption_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

adoption_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(total_listings)         AS total_listings,
           SUM(express_listings)       AS express_listings,
           SUM(case_break_listings)    AS case_break_listings,
           COUNT(DISTINCT event_id)    AS event_count
    FROM adoption_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

-- ── LISTING TIME CTEs (avg at all grains; percentiles at Overall only) ──
listing_time_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                                                               AS listing_time_total_rows,
           COUNT(diff_in_minutes)                                                 AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2)      AS express_listing_avg,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2)      AS standard_listing_avg
    FROM listing_time_base
    GROUP BY DATE_FORMAT(dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

listing_time_weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING) AS label,
        'Weekly' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                                                               AS listing_time_total_rows,
        COUNT(diff_in_minutes)                                                 AS listing_time_matched_rows,
        ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2)      AS express_listing_avg,
        ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2)      AS standard_listing_avg
    FROM listing_time_base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

listing_time_monthly AS (
    SELECT CAST(MONTH_ID AS STRING) AS label, 'Monthly' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                                                               AS listing_time_total_rows,
           COUNT(diff_in_minutes)                                                 AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2)      AS express_listing_avg,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2)      AS standard_listing_avg
    FROM listing_time_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

listing_time_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                                                                AS listing_time_total_rows,
           COUNT(diff_in_minutes)                                                  AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2)       AS express_listing_avg,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.50, 10000) AS express_listing_p50,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.75, 10000) AS express_listing_p75,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.90, 10000) AS express_listing_p90,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2)       AS standard_listing_avg,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.50, 10000) AS standard_listing_p50,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.75, 10000) AS standard_listing_p75,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.90, 10000) AS standard_listing_p90
    FROM listing_time_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

-- ── DAILY: adoption + avg time; percentiles NULL ───────────────
SELECT
    COALESCE(a.label,             t.label)             AS label,
    COALESCE(a.timeframe,         t.timeframe)         AS timeframe,
    COALESCE(a.geography,         t.geography)         AS geography,
    COALESCE(a.launch_phase,      t.launch_phase)      AS launch_phase,
    COALESCE(a.category,          t.category)          AS category,
    COALESCE(a.gmv_tier,          t.gmv_tier)          AS gmv_tier,
    COALESCE(a.onboarding_method, t.onboarding_method) AS onboarding_method,
    COALESCE(a.seller_background, t.seller_background) AS seller_background,
    COALESCE(a.total_listings,       0)                AS total_listings,
    COALESCE(a.express_listings,     0)                AS express_listings,
    COALESCE(a.case_break_listings,  0)                AS case_break_listings,
    COALESCE(a.event_count,          0)                AS event_count,
    t.listing_time_total_rows,
    t.listing_time_matched_rows,
    t.express_listing_avg,
    NULL AS express_listing_p50,
    NULL AS express_listing_p75,
    NULL AS express_listing_p90,
    t.standard_listing_avg,
    NULL AS standard_listing_p50,
    NULL AS standard_listing_p75,
    NULL AS standard_listing_p90
FROM adoption_daily a
FULL OUTER JOIN listing_time_daily t
    ON  a.label              = t.label
    AND a.timeframe          = t.timeframe
    AND a.geography          = t.geography
    AND a.launch_phase       = t.launch_phase
    AND a.category           = t.category
    AND a.gmv_tier           = t.gmv_tier
    AND a.onboarding_method  = t.onboarding_method
    AND a.seller_background  = t.seller_background

UNION ALL

-- ── WEEKLY: adoption + avg time; percentiles NULL ──────────────
SELECT
    COALESCE(a.label,             t.label),
    COALESCE(a.timeframe,         t.timeframe),
    COALESCE(a.geography,         t.geography),
    COALESCE(a.launch_phase,      t.launch_phase),
    COALESCE(a.category,          t.category),
    COALESCE(a.gmv_tier,          t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method),
    COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings,       0),
    COALESCE(a.express_listings,     0),
    COALESCE(a.case_break_listings,  0),
    COALESCE(a.event_count,          0),
    t.listing_time_total_rows,
    t.listing_time_matched_rows,
    t.express_listing_avg, NULL, NULL, NULL,
    t.standard_listing_avg, NULL, NULL, NULL
FROM adoption_weekly a
FULL OUTER JOIN listing_time_weekly t
    ON  a.label              = t.label
    AND a.timeframe          = t.timeframe
    AND a.geography          = t.geography
    AND a.launch_phase       = t.launch_phase
    AND a.category           = t.category
    AND a.gmv_tier           = t.gmv_tier
    AND a.onboarding_method  = t.onboarding_method
    AND a.seller_background  = t.seller_background

UNION ALL

-- ── MONTHLY: adoption + avg time; percentiles NULL ─────────────
SELECT
    COALESCE(a.label,             t.label),
    COALESCE(a.timeframe,         t.timeframe),
    COALESCE(a.geography,         t.geography),
    COALESCE(a.launch_phase,      t.launch_phase),
    COALESCE(a.category,          t.category),
    COALESCE(a.gmv_tier,          t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method),
    COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings,       0),
    COALESCE(a.express_listings,     0),
    COALESCE(a.case_break_listings,  0),
    COALESCE(a.event_count,          0),
    t.listing_time_total_rows,
    t.listing_time_matched_rows,
    t.express_listing_avg, NULL, NULL, NULL,
    t.standard_listing_avg, NULL, NULL, NULL
FROM adoption_monthly a
FULL OUTER JOIN listing_time_monthly t
    ON  a.label              = t.label
    AND a.timeframe          = t.timeframe
    AND a.geography          = t.geography
    AND a.launch_phase       = t.launch_phase
    AND a.category           = t.category
    AND a.gmv_tier           = t.gmv_tier
    AND a.onboarding_method  = t.onboarding_method
    AND a.seller_background  = t.seller_background

UNION ALL

-- ── OVERALL: adoption + avg + percentiles ─────────────────────
SELECT
    COALESCE(a.label,             t.label),
    COALESCE(a.timeframe,         t.timeframe),
    COALESCE(a.geography,         t.geography),
    COALESCE(a.launch_phase,      t.launch_phase),
    COALESCE(a.category,          t.category),
    COALESCE(a.gmv_tier,          t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method),
    COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings,       0),
    COALESCE(a.express_listings,     0),
    COALESCE(a.case_break_listings,  0),
    COALESCE(a.event_count,          0),
    t.listing_time_total_rows,
    t.listing_time_matched_rows,
    t.express_listing_avg,  t.express_listing_p50,  t.express_listing_p75,  t.express_listing_p90,
    t.standard_listing_avg, t.standard_listing_p50, t.standard_listing_p75, t.standard_listing_p90
FROM adoption_overall a
FULL OUTER JOIN listing_time_overall t
    ON  a.geography          = t.geography
    AND a.launch_phase       = t.launch_phase
    AND a.category           = t.category
    AND a.gmv_tier           = t.gmv_tier
    AND a.onboarding_method  = t.onboarding_method
    AND a.seller_background  = t.seller_background;
