-- ================================================================
-- PRE_STREAM_EVENT_METRICS_AGG
-- Sources : COMPLETION_RATE_FINAL_T  (rate metrics — both metric_names)
--         + COMPLETION_TIME_FINAL_T  (event side, metric_name = 'Event Completion Time')
-- Grain   : event publication / activity dt  →  Daily / Weekly / Monthly / Overall
-- AVG     : computed at all 4 grains from raw rows (additive)
-- P50/75/90 : computed at Overall grain only (non-re-aggregatable)
-- Date scope: 2026-07-17 onward (eBay Live launch)
-- Merge   : FULL OUTER JOIN per grain on (label, timeframe, filter_dims)
-- ================================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.PRE_STREAM_EVENT_METRICS_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.PRE_STREAM_EVENT_METRICS_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
    WHERE CAL_DT >= '2026-07-17'
),

rate_base AS (
    SELECT
        crf.dt, crf.seller_id, crf.metric_name, crf.numerator, crf.denominator,
        cal.RETAIL_YEAR, cal.RETAIL_WEEK, cal.AGE_FOR_RTL_WEEK_ID, cal.MONTH_ID,
        COALESCE(crf.geography,         'Unknown') AS geography,
        COALESCE(crf.launch_phase,      'Unknown') AS launch_phase,
        COALESCE(crf.category,          'Unknown') AS category,
        COALESCE(crf.gmv_tier,          'Unknown') AS gmv_tier,
        COALESCE(crf.onboarding_method, 'Unknown') AS onboarding_method,
        COALESCE(crf.seller_background, 'Unknown') AS seller_background
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
    INNER JOIN cal_ref cal ON crf.dt = cal.CAL_DT
),

event_time_base AS (
    SELECT
        ctf.dt, ctf.diff_in_minutes,
        cal.RETAIL_YEAR, cal.RETAIL_WEEK, cal.AGE_FOR_RTL_WEEK_ID, cal.MONTH_ID,
        COALESCE(ctf.geography,         'Unknown') AS geography,
        COALESCE(ctf.launch_phase,      'Unknown') AS launch_phase,
        COALESCE(ctf.category,          'Unknown') AS category,
        COALESCE(ctf.gmv_tier,          'Unknown') AS gmv_tier,
        COALESCE(ctf.onboarding_method, 'Unknown') AS onboarding_method,
        COALESCE(ctf.seller_background, 'Unknown') AS seller_background
    FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
    INNER JOIN cal_ref cal ON ctf.dt = cal.CAL_DT
    WHERE ctf.metric_name     = 'Event Completion Time'
      AND ctf.diff_in_minutes IS NOT NULL
      AND ctf.diff_in_minutes >= 0
),

-- ── RATE CTEs ─────────────────────────────────────────────────
rate_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN numerator   ELSE 0 END) AS published_events,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN denominator ELSE 0 END) AS cta_clicks,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND denominator > 0 THEN seller_id END) AS seller_setup_started,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND numerator   > 0 THEN seller_id END) AS seller_setup_success,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN numerator   ELSE 0 END) AS listings_completed,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN denominator ELSE 0 END) AS listings_started
    FROM rate_base
    GROUP BY DATE_FORMAT(dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

rate_weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING) AS label,
        'Weekly' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN numerator   ELSE 0 END) AS published_events,
        SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN denominator ELSE 0 END) AS cta_clicks,
        COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND denominator > 0 THEN seller_id END) AS seller_setup_started,
        COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND numerator   > 0 THEN seller_id END) AS seller_setup_success,
        SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN numerator   ELSE 0 END) AS listings_completed,
        SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN denominator ELSE 0 END) AS listings_started
    FROM rate_base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

rate_monthly AS (
    SELECT CAST(MONTH_ID AS STRING) AS label, 'Monthly' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN numerator   ELSE 0 END) AS published_events,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN denominator ELSE 0 END) AS cta_clicks,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND denominator > 0 THEN seller_id END) AS seller_setup_started,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND numerator   > 0 THEN seller_id END) AS seller_setup_success,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN numerator   ELSE 0 END) AS listings_completed,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN denominator ELSE 0 END) AS listings_started
    FROM rate_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

rate_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN numerator   ELSE 0 END) AS published_events,
           SUM(CASE WHEN metric_name = 'Event Completion Rate'           THEN denominator ELSE 0 END) AS cta_clicks,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND denominator > 0 THEN seller_id END) AS seller_setup_started,
           COUNT(DISTINCT CASE WHEN metric_name = 'Event Completion Rate' AND numerator   > 0 THEN seller_id END) AS seller_setup_success,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN numerator   ELSE 0 END) AS listings_completed,
           SUM(CASE WHEN metric_name = 'Express Listing Completion Rate' THEN denominator ELSE 0 END) AS listings_started
    FROM rate_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

-- ── EVENT TIME CTEs (avg at all grains; percentiles at Overall only) ──
event_time_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                       AS event_time_total_rows,
           COUNT(diff_in_minutes)         AS event_time_matched_rows,
           ROUND(AVG(diff_in_minutes), 2) AS event_completion_avg
    FROM event_time_base
    GROUP BY DATE_FORMAT(dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

event_time_weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING) AS label,
        'Weekly' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                       AS event_time_total_rows,
        COUNT(diff_in_minutes)         AS event_time_matched_rows,
        ROUND(AVG(diff_in_minutes), 2) AS event_completion_avg
    FROM event_time_base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

event_time_monthly AS (
    SELECT CAST(MONTH_ID AS STRING) AS label, 'Monthly' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                       AS event_time_total_rows,
           COUNT(diff_in_minutes)         AS event_time_matched_rows,
           ROUND(AVG(diff_in_minutes), 2) AS event_completion_avg
    FROM event_time_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

event_time_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*)                                          AS event_time_total_rows,
           COUNT(diff_in_minutes)                            AS event_time_matched_rows,
           ROUND(AVG(diff_in_minutes), 2)                   AS event_completion_avg,
           PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)  AS event_completion_p50,
           PERCENTILE_APPROX(diff_in_minutes, 0.75, 10000)  AS event_completion_p75,
           PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)  AS event_completion_p90
    FROM event_time_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

-- ── DAILY: rate + avg time; percentiles NULL ───────────────────
SELECT
    COALESCE(r.label,             t.label)             AS label,
    COALESCE(r.timeframe,         t.timeframe)         AS timeframe,
    COALESCE(r.geography,         t.geography)         AS geography,
    COALESCE(r.launch_phase,      t.launch_phase)      AS launch_phase,
    COALESCE(r.category,          t.category)          AS category,
    COALESCE(r.gmv_tier,          t.gmv_tier)          AS gmv_tier,
    COALESCE(r.onboarding_method, t.onboarding_method) AS onboarding_method,
    COALESCE(r.seller_background, t.seller_background) AS seller_background,
    COALESCE(r.published_events,  0)                   AS published_events,
    COALESCE(r.cta_clicks,        0)                   AS cta_clicks,
    COALESCE(r.seller_setup_started, 0)                AS seller_setup_started,
    COALESCE(r.seller_setup_success, 0)                AS seller_setup_success,
    COALESCE(r.listings_completed, 0)                  AS listings_completed,
    COALESCE(r.listings_started,  0)                   AS listings_started,
    t.event_time_total_rows,
    t.event_time_matched_rows,
    t.event_completion_avg,
    NULL AS event_completion_p50,
    NULL AS event_completion_p75,
    NULL AS event_completion_p90
FROM rate_daily r
FULL OUTER JOIN event_time_daily t
    ON  r.label              = t.label
    AND r.timeframe          = t.timeframe
    AND r.geography          = t.geography
    AND r.launch_phase       = t.launch_phase
    AND r.category           = t.category
    AND r.gmv_tier           = t.gmv_tier
    AND r.onboarding_method  = t.onboarding_method
    AND r.seller_background  = t.seller_background

UNION ALL

-- ── WEEKLY: rate + avg time; percentiles NULL ──────────────────
SELECT
    COALESCE(r.label,             t.label),
    COALESCE(r.timeframe,         t.timeframe),
    COALESCE(r.geography,         t.geography),
    COALESCE(r.launch_phase,      t.launch_phase),
    COALESCE(r.category,          t.category),
    COALESCE(r.gmv_tier,          t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method),
    COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events,  0),
    COALESCE(r.cta_clicks,        0),
    COALESCE(r.seller_setup_started, 0),
    COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0),
    COALESCE(r.listings_started,  0),
    t.event_time_total_rows,
    t.event_time_matched_rows,
    t.event_completion_avg,
    NULL,
    NULL,
    NULL
FROM rate_weekly r
FULL OUTER JOIN event_time_weekly t
    ON  r.label              = t.label
    AND r.timeframe          = t.timeframe
    AND r.geography          = t.geography
    AND r.launch_phase       = t.launch_phase
    AND r.category           = t.category
    AND r.gmv_tier           = t.gmv_tier
    AND r.onboarding_method  = t.onboarding_method
    AND r.seller_background  = t.seller_background

UNION ALL

-- ── MONTHLY: rate + avg time; percentiles NULL ─────────────────
SELECT
    COALESCE(r.label,             t.label),
    COALESCE(r.timeframe,         t.timeframe),
    COALESCE(r.geography,         t.geography),
    COALESCE(r.launch_phase,      t.launch_phase),
    COALESCE(r.category,          t.category),
    COALESCE(r.gmv_tier,          t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method),
    COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events,  0),
    COALESCE(r.cta_clicks,        0),
    COALESCE(r.seller_setup_started, 0),
    COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0),
    COALESCE(r.listings_started,  0),
    t.event_time_total_rows,
    t.event_time_matched_rows,
    t.event_completion_avg,
    NULL,
    NULL,
    NULL
FROM rate_monthly r
FULL OUTER JOIN event_time_monthly t
    ON  r.label              = t.label
    AND r.timeframe          = t.timeframe
    AND r.geography          = t.geography
    AND r.launch_phase       = t.launch_phase
    AND r.category           = t.category
    AND r.gmv_tier           = t.gmv_tier
    AND r.onboarding_method  = t.onboarding_method
    AND r.seller_background  = t.seller_background

UNION ALL

-- ── OVERALL: rate + avg + percentiles ─────────────────────────
SELECT
    COALESCE(r.label,             t.label),
    COALESCE(r.timeframe,         t.timeframe),
    COALESCE(r.geography,         t.geography),
    COALESCE(r.launch_phase,      t.launch_phase),
    COALESCE(r.category,          t.category),
    COALESCE(r.gmv_tier,          t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method),
    COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events,  0),
    COALESCE(r.cta_clicks,        0),
    COALESCE(r.seller_setup_started, 0),
    COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0),
    COALESCE(r.listings_started,  0),
    t.event_time_total_rows,
    t.event_time_matched_rows,
    t.event_completion_avg,
    t.event_completion_p50,
    t.event_completion_p75,
    t.event_completion_p90
FROM rate_overall r
FULL OUTER JOIN event_time_overall t
    ON  r.geography          = t.geography
    AND r.launch_phase       = t.launch_phase
    AND r.category           = t.category
    AND r.gmv_tier           = t.gmv_tier
    AND r.onboarding_method  = t.onboarding_method
    AND r.seller_background  = t.seller_background;
