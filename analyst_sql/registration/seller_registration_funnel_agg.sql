-- ============================================================
-- P_LIVE_ANALYTICS_T.SELLER_REGISTRATION_FUNNEL_AGG
-- Pre-aggregated Tableau-ready table for the Registration tab of
-- the eBay Live Opening Up dashboard.
--
-- Source:  P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
--          joined to LIVE_SELLER_UNIFIED_ONBOARDING_DIM by seller_id
-- Cohort:  account_created_ts (seller account creation date)
-- Grains:  Daily | Weekly (retail, complete weeks) | Monthly | Overall
-- Scope:   No lower date bound — full cohort history
-- Dims:    geography, launch_phase, category, gmv_tier, onboarding_method,
--          seller_background (matches instream / pre_stream dimension set)
--
-- Steps 3 (shipping_policy) and 4 (tutorial) are hardcoded 0 — stub
-- placeholders until that data is wired in. Exclude from funnel charts.
-- ============================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.SELLER_REGISTRATION_FUNNEL_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.SELLER_REGISTRATION_FUNNEL_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
),

base AS (
    SELECT
        m.user_id_ubi,
        CAST(m.account_created_ts AS DATE)           AS account_created_dt,
        m.activated_studio,
        m.first_event_created_ts,
        m.first_listing_created_ts,
        m.first_show_date,
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

daily AS (
    SELECT
        DATE_FORMAT(account_created_dt, 'yyyy-MM-dd') AS label,
        'Daily'                                        AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                                       AS n_account_created,
        SUM(activated_studio)                          AS n_lpg_granted,
        SUM(CASE WHEN activated_studio = 1 AND first_event_created_ts   IS NOT NULL THEN 1 ELSE 0 END) AS n_step1_first_event,
        SUM(CASE WHEN activated_studio = 1 AND first_listing_created_ts IS NOT NULL THEN 1 ELSE 0 END) AS n_step2_first_listing,
        CAST(0 AS BIGINT)                              AS n_step3_shipping_policy_added,
        CAST(0 AS BIGINT)                              AS n_step4_tutorial_done,
        SUM(CASE WHEN activated_studio = 1 AND first_show_date IS NOT NULL THEN 1 ELSE 0 END)          AS n_step5_first_show
    FROM base
    GROUP BY DATE_FORMAT(account_created_dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING)               AS label,
        'Weekly'                                      AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                                      AS n_account_created,
        SUM(activated_studio)                         AS n_lpg_granted,
        SUM(CASE WHEN activated_studio = 1 AND first_event_created_ts   IS NOT NULL THEN 1 ELSE 0 END) AS n_step1_first_event,
        SUM(CASE WHEN activated_studio = 1 AND first_listing_created_ts IS NOT NULL THEN 1 ELSE 0 END) AS n_step2_first_listing,
        CAST(0 AS BIGINT)                             AS n_step3_shipping_policy_added,
        CAST(0 AS BIGINT)                             AS n_step4_tutorial_done,
        SUM(CASE WHEN activated_studio = 1 AND first_show_date IS NOT NULL THEN 1 ELSE 0 END)          AS n_step5_first_show
    FROM base
    WHERE AGE_FOR_RTL_WEEK_ID <= -1
    GROUP BY
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING),
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

monthly AS (
    SELECT
        CAST(MONTH_ID AS STRING)                      AS label,
        'Monthly'                                     AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                                      AS n_account_created,
        SUM(activated_studio)                         AS n_lpg_granted,
        SUM(CASE WHEN activated_studio = 1 AND first_event_created_ts   IS NOT NULL THEN 1 ELSE 0 END) AS n_step1_first_event,
        SUM(CASE WHEN activated_studio = 1 AND first_listing_created_ts IS NOT NULL THEN 1 ELSE 0 END) AS n_step2_first_listing,
        CAST(0 AS BIGINT)                             AS n_step3_shipping_policy_added,
        CAST(0 AS BIGINT)                             AS n_step4_tutorial_done,
        SUM(CASE WHEN activated_studio = 1 AND first_show_date IS NOT NULL THEN 1 ELSE 0 END)          AS n_step5_first_show
    FROM base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

overall AS (
    SELECT
        'Overall'                                     AS label,
        'Overall'                                     AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(*)                                      AS n_account_created,
        SUM(activated_studio)                         AS n_lpg_granted,
        SUM(CASE WHEN activated_studio = 1 AND first_event_created_ts   IS NOT NULL THEN 1 ELSE 0 END) AS n_step1_first_event,
        SUM(CASE WHEN activated_studio = 1 AND first_listing_created_ts IS NOT NULL THEN 1 ELSE 0 END) AS n_step2_first_listing,
        CAST(0 AS BIGINT)                             AS n_step3_shipping_policy_added,
        CAST(0 AS BIGINT)                             AS n_step4_tutorial_done,
        SUM(CASE WHEN activated_studio = 1 AND first_show_date IS NOT NULL THEN 1 ELSE 0 END)          AS n_step5_first_show
    FROM base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

SELECT * FROM daily
UNION ALL SELECT * FROM weekly
UNION ALL SELECT * FROM monthly
UNION ALL SELECT * FROM overall;
