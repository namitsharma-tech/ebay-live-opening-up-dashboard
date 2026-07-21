-- ================================================================
-- PRE_STREAM_FUNNEL_AGG
-- Funnel is rebuilt from source tables (SELLER_FIRST_SHOW_FUNNEL
-- excluded — it has no dt column and cannot be cohorted by date).
-- Cohort base  : LIVE_SELLER_MASTER_V2  (studio_activated_ts)
-- Step sources : LIVE_EVENT, LIVE_EVENT_LISTING, SLNG_LSTG_SUPER_FACT,
--                LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
-- Grain        : seller's studio activation date
--                → Daily / Weekly / Monthly / Overall
-- Date scope   : 2026-07-17 onward (eBay Live launch)
-- ================================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
    WHERE CAL_DT >= '2026-07-17'
),

-- Step 1: sellers who created at least one published event
published_event AS (
    SELECT DISTINCT CAST(hostids[0] AS BIGINT) AS sellerid
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT
    WHERE flag            = 'PROD'
      AND isDeleted       = FALSE
      AND visibilityState = 'PUBLISHED'
      AND dt              >= '2026-07-17'
),

-- Step 2+3: sellers who created a published event AND attached a live listing
event_with_listing AS (
    SELECT DISTINCT CAST(e.hostids[0] AS BIGINT) AS sellerid
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT e
    JOIN P_LIVE_ANALYTICS_V.LIVE_EVENT_LISTING elc
        ON  e.eventId    = elc.eventId
        AND elc.isDeleted = FALSE
        AND elc.dt       >= '2026-07-17'
    JOIN PRS_RESTRICTED_V.SLNG_LSTG_SUPER_FACT l
        ON  elc.ITEMID       = l.ITEM_ID
        AND l.AUCT_END_DT   >= DATE_SUB(CURRENT_DATE(), 365)
    WHERE e.flag            = 'PROD'
      AND e.isDeleted       = FALSE
      AND e.visibilityState = 'PUBLISHED'
      AND e.dt              >= '2026-07-17'
),

-- Step 4: earliest actual stream per seller
first_stream AS (
    SELECT slr_id AS sellerid, MIN(STARTTIME) AS first_stream_start
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind      = 0
      AND event_duration_min > 0
    GROUP BY slr_id
),

-- Cohort: one row per seller activated on or after launch date
funnel_base AS (
    SELECT
        m.user_id_ubi                               AS sellerid,
        CAST(m.studio_activated_ts AS DATE)         AS activated_dt,
        cal.RETAIL_YEAR, cal.RETAIL_WEEK, cal.AGE_FOR_RTL_WEEK_ID, cal.MONTH_ID,
        COALESCE(d.geography,         'Unknown')    AS geography,
        COALESCE(d.launch_phase,      'Unknown')    AS launch_phase,
        COALESCE(d.category,          'Unknown')    AS category,
        COALESCE(d.gmv_tier,          'Unknown')    AS gmv_tier,
        COALESCE(d.onboarding_method, 'Unknown')    AS onboarding_method,
        COALESCE(d.seller_background, 'Unknown')    AS seller_background,
        -- step 0 (denominator): every activated seller counts
        -- step 1: published event exists
        CASE WHEN pe.sellerid  IS NOT NULL THEN 1 ELSE 0 END AS step1_event_created,
        -- step 2: event has a listing attached
        CASE WHEN ewl.sellerid IS NOT NULL THEN 1 ELSE 0 END AS step2_listing_ready,
        -- step 3 = same gate as step 2 (first_show_ready ≡ listing_ready per source logic)
        CASE WHEN ewl.sellerid IS NOT NULL THEN 1 ELSE 0 END AS step3_first_show_ready,
        -- step 4: first actual stream within 14 days of studio activation
        CASE
            WHEN fs.first_stream_start IS NOT NULL
             AND DATEDIFF(
                     CAST(fs.first_stream_start AS DATE),
                     CAST(m.studio_activated_ts AS DATE)
                 ) <= 14
            THEN 1 ELSE 0
        END AS step4_14d_first_show
    FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 m
    -- join on activation date to pull retail calendar columns
    INNER JOIN cal_ref cal
        ON CAST(m.studio_activated_ts AS DATE) = cal.CAL_DT
    -- dimension enrichment
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(m.user_id_ubi AS STRING) = d.seller_id
    -- funnel steps
    LEFT JOIN published_event    pe  ON m.user_id_ubi = pe.sellerid
    LEFT JOIN event_with_listing ewl ON m.user_id_ubi = ewl.sellerid
    LEFT JOIN first_stream       fs  ON m.user_id_ubi = fs.sellerid
    -- latest snapshot only; exclude test users; must have activated studio
    WHERE m.report_dt = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
      AND m.is_test_user     = 0
      AND m.activated_studio = 1
      AND m.studio_activated_ts IS NOT NULL
),

-- ── AGGREGATE CTEs ────────────────────────────────────────────
DAILY AS (
    SELECT
        DATE_FORMAT(activated_dt, 'yyyy-MM-dd') AS label,
        'Daily'                                  AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT sellerid)                                                AS step0_setup_started,
        COUNT(DISTINCT CASE WHEN step1_event_created    = 1 THEN sellerid END) AS step1_event_created,
        COUNT(DISTINCT CASE WHEN step2_listing_ready    = 1 THEN sellerid END) AS step2_listing_ready,
        COUNT(DISTINCT CASE WHEN step3_first_show_ready = 1 THEN sellerid END) AS step3_first_show_ready,
        COUNT(DISTINCT CASE WHEN step4_14d_first_show   = 1 THEN sellerid END) AS step4_14d_first_show
    FROM funnel_base
    GROUP BY DATE_FORMAT(activated_dt, 'yyyy-MM-dd'),
             geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

WEEKLY AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING) AS label,
        'Weekly' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT sellerid)                                                AS step0_setup_started,
        COUNT(DISTINCT CASE WHEN step1_event_created    = 1 THEN sellerid END) AS step1_event_created,
        COUNT(DISTINCT CASE WHEN step2_listing_ready    = 1 THEN sellerid END) AS step2_listing_ready,
        COUNT(DISTINCT CASE WHEN step3_first_show_ready = 1 THEN sellerid END) AS step3_first_show_ready,
        COUNT(DISTINCT CASE WHEN step4_14d_first_show   = 1 THEN sellerid END) AS step4_14d_first_show
    FROM funnel_base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

MONTHLY AS (
    SELECT
        CAST(MONTH_ID AS STRING) AS label,
        'Monthly'                AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT sellerid)                                                AS step0_setup_started,
        COUNT(DISTINCT CASE WHEN step1_event_created    = 1 THEN sellerid END) AS step1_event_created,
        COUNT(DISTINCT CASE WHEN step2_listing_ready    = 1 THEN sellerid END) AS step2_listing_ready,
        COUNT(DISTINCT CASE WHEN step3_first_show_ready = 1 THEN sellerid END) AS step3_first_show_ready,
        COUNT(DISTINCT CASE WHEN step4_14d_first_show   = 1 THEN sellerid END) AS step4_14d_first_show
    FROM funnel_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

OVERALL AS (
    SELECT
        'Overall' AS label,
        'Overall' AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT sellerid)                                                AS step0_setup_started,
        COUNT(DISTINCT CASE WHEN step1_event_created    = 1 THEN sellerid END) AS step1_event_created,
        COUNT(DISTINCT CASE WHEN step2_listing_ready    = 1 THEN sellerid END) AS step2_listing_ready,
        COUNT(DISTINCT CASE WHEN step3_first_show_ready = 1 THEN sellerid END) AS step3_first_show_ready,
        COUNT(DISTINCT CASE WHEN step4_14d_first_show   = 1 THEN sellerid END) AS step4_14d_first_show
    FROM funnel_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

SELECT * FROM DAILY
UNION ALL
SELECT * FROM WEEKLY
UNION ALL
SELECT * FROM MONTHLY
UNION ALL
SELECT * FROM OVERALL;
