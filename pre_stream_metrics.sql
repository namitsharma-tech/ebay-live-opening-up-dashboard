-- ================================================================
-- PRE-STREAM TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: Pre-Stream
--
-- Source tables:
--   A  P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
--   B  P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
--   C  P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
--   D  P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
--   E  P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
--   F  P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
--   G  P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
--   H  P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_RATE_T
--   I  P_LIVE_ANALYTICS_V.LIVE_EVENT
--   J  P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
--
-- Run order: each query is independent — run in any order.
-- All rates use SUM(num)/SUM(denom) — never average of rates.
-- ================================================================


-- ================================================================
-- 0. SHARED CTEs (reference in sections below)
--    Paste these at the top of any multi-section query.
-- ================================================================
/*
WITH setup_sellers AS (
    SELECT DISTINCT user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
),
published_event_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
),
has_listing_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE total_listings > 0
),
first_cta_date AS (
    SELECT user_id AS seller_id, MIN(session_start_dt) AS first_cta_dt
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
),
first_stream_date AS (
    SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
)
*/


-- ================================================================
-- SECTION 1 — L0 NORTH STAR: Seller Setup Success Rate
--   Definition: sellers with published event + ≥1 listing
--               divided by sellers who clicked Create Event CTA.
--   ⚠ Cohort-level metric: best run against a fixed onboarding
--     cohort (e.g., all sellers who clicked CTA in a given month).
-- ================================================================

-- 1A. Overall rate (all time)
WITH setup_sellers AS (
    SELECT DISTINCT user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
),
setup_success AS (
    SELECT DISTINCT ecr.seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T ecr
    INNER JOIN P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
        ON  ecr.seller_id = la.seller_id
    WHERE ecr.published_cnt > 0
      AND la.total_listings > 0
)
SELECT
    COUNT(DISTINCT ss.seller_id)                                                AS setup_started_sellers,
    COUNT(DISTINCT su.seller_id)                                                AS setup_success_sellers,
    ROUND(COUNT(DISTINCT su.seller_id) * 100.0
          / NULLIF(COUNT(DISTINCT ss.seller_id), 0), 1)                         AS seller_setup_success_rate_pct
FROM setup_sellers ss
LEFT JOIN setup_success su ON ss.seller_id = su.seller_id;


-- 1B. Weekly trend of Seller Setup Success Rate
WITH seller_first_cta AS (
    SELECT
        user_id                                         AS seller_id,
        MIN(session_start_dt)                           AS first_cta_dt,
        DATE_TRUNC('week', MIN(session_start_dt))       AS cohort_week
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
),
setup_success AS (
    SELECT DISTINCT ecr.seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T ecr
    INNER JOIN P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la ON ecr.seller_id = la.seller_id
    WHERE ecr.published_cnt > 0 AND la.total_listings > 0
)
SELECT
    fc.cohort_week,
    COUNT(DISTINCT fc.seller_id)                                                AS setup_started_sellers,
    COUNT(DISTINCT su.seller_id)                                                AS setup_success_sellers,
    ROUND(COUNT(DISTINCT su.seller_id) * 100.0
          / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1)                         AS seller_setup_success_rate_pct
FROM seller_first_cta fc
LEFT JOIN setup_success su ON fc.seller_id = su.seller_id
GROUP BY fc.cohort_week
ORDER BY fc.cohort_week DESC;


-- ================================================================
-- SECTION 2 — P0 FUNNEL: All 5 Steps
--   LPG → Event Creation → Listing Readiness → First Show Ready
--   → 14-Day First Show
--
--   All rates expressed as % of setup_started (denominator is fixed
--   so steps can be >100% relative to each other if needed, but in
--   practice each step is a subset of the prior).
-- ================================================================

-- 2A. Single-row funnel snapshot (all time)
WITH setup_sellers AS (
    SELECT DISTINCT user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
),
published_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
),
listing_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE total_listings > 0
),
ready_sellers AS (
    SELECT DISTINCT p.seller_id
    FROM published_sellers p
    INNER JOIN listing_sellers l ON p.seller_id = l.seller_id
),
first_cta_dt AS (
    SELECT user_id AS seller_id, MIN(session_start_dt) AS first_cta_dt
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
),
first_stream_dt AS (
    SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
),
streamed_14d AS (
    SELECT fc.seller_id
    FROM first_cta_dt fc
    INNER JOIN first_stream_dt fsd ON fc.seller_id = fsd.seller_id
    WHERE fsd.first_stream_dt >= fc.first_cta_dt
      AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
)
SELECT
    COUNT(DISTINCT ss.seller_id)                                                AS step0_setup_started,
    COUNT(DISTINCT pe.seller_id)                                                AS step1_event_created,
    COUNT(DISTINCT ls.seller_id)                                                AS step2_listing_ready,
    COUNT(DISTINCT rs.seller_id)                                                AS step3_first_show_ready,
    COUNT(DISTINCT s14.seller_id)                                               AS step4_14d_first_show,
    ROUND(COUNT(DISTINCT pe.seller_id)  * 100.0 / NULLIF(COUNT(DISTINCT ss.seller_id), 0), 1) AS event_creation_rate_pct,
    ROUND(COUNT(DISTINCT ls.seller_id)  * 100.0 / NULLIF(COUNT(DISTINCT ss.seller_id), 0), 1) AS listing_readiness_rate_pct,
    ROUND(COUNT(DISTINCT rs.seller_id)  * 100.0 / NULLIF(COUNT(DISTINCT ss.seller_id), 0), 1) AS first_show_ready_rate_pct,
    ROUND(COUNT(DISTINCT s14.seller_id) * 100.0 / NULLIF(COUNT(DISTINCT ss.seller_id), 0), 1) AS fourteen_day_first_show_rate_pct
FROM setup_sellers ss
LEFT JOIN published_sellers pe  ON ss.seller_id = pe.seller_id
LEFT JOIN listing_sellers   ls  ON ss.seller_id = ls.seller_id
LEFT JOIN ready_sellers     rs  ON ss.seller_id = rs.seller_id
LEFT JOIN streamed_14d      s14 ON ss.seller_id = s14.seller_id;


-- 2B. Funnel by cohort week (for the trend chart)
WITH seller_first_cta AS (
    SELECT
        user_id                                         AS seller_id,
        MIN(session_start_dt)                           AS first_cta_dt,
        DATE_TRUNC('week', MIN(session_start_dt))       AS cohort_week
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
),
published_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
),
listing_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE total_listings > 0
),
first_stream_dt AS (
    SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
)
SELECT
    fc.cohort_week,
    COUNT(DISTINCT fc.seller_id)                                                AS setup_started,
    COUNT(DISTINCT pe.seller_id)                                                AS event_created,
    COUNT(DISTINCT ls.seller_id)                                                AS listing_ready,
    COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL THEN fc.seller_id END) AS first_show_ready,
    COUNT(DISTINCT CASE
        WHEN fsd.first_stream_dt >= fc.first_cta_dt
          AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
        THEN fc.seller_id END)                                                  AS streamed_14d,
    ROUND(COUNT(DISTINCT pe.seller_id) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS event_creation_rate_pct,
    ROUND(COUNT(DISTINCT ls.seller_id) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS listing_readiness_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL THEN fc.seller_id END) * 100.0
          / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1)                         AS first_show_ready_rate_pct,
    ROUND(COUNT(DISTINCT CASE
        WHEN fsd.first_stream_dt >= fc.first_cta_dt
          AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
        THEN fc.seller_id END) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS fourteen_day_first_show_rate_pct
FROM seller_first_cta fc
LEFT JOIN published_sellers  pe  ON fc.seller_id = pe.seller_id
LEFT JOIN listing_sellers    ls  ON fc.seller_id = ls.seller_id
LEFT JOIN first_stream_dt    fsd ON fc.seller_id = fsd.seller_id
GROUP BY fc.cohort_week
ORDER BY fc.cohort_week DESC;


-- 2C. Funnel with seller dimension breakdown (onboarding_method, geography, gmv_tier)
WITH seller_first_cta AS (
    SELECT user_id AS seller_id, MIN(session_start_dt) AS first_cta_dt
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
),
published_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
),
listing_sellers AS (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE total_listings > 0
),
first_stream_dt AS (
    SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
),
seller_dims AS (
    SELECT DISTINCT seller_id, onboarding_method, geography, gmv_tier, seller_tenure, launch_phase
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
)
SELECT
    d.onboarding_method,
    d.geography,
    d.gmv_tier,
    d.seller_tenure,
    COUNT(DISTINCT fc.seller_id)                                                AS setup_started,
    ROUND(COUNT(DISTINCT pe.seller_id) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS event_creation_rate_pct,
    ROUND(COUNT(DISTINCT ls.seller_id) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS listing_readiness_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL THEN fc.seller_id END) * 100.0
          / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1)                         AS first_show_ready_rate_pct,
    ROUND(COUNT(DISTINCT CASE
        WHEN fsd.first_stream_dt >= fc.first_cta_dt
          AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
        THEN fc.seller_id END) * 100.0 / NULLIF(COUNT(DISTINCT fc.seller_id), 0), 1) AS fourteen_day_first_show_rate_pct
FROM seller_first_cta fc
LEFT JOIN published_sellers  pe  ON fc.seller_id = pe.seller_id
LEFT JOIN listing_sellers    ls  ON fc.seller_id = ls.seller_id
LEFT JOIN first_stream_dt    fsd ON fc.seller_id = fsd.seller_id
LEFT JOIN seller_dims        d   ON CAST(fc.seller_id AS STRING) = d.seller_id
GROUP BY d.onboarding_method, d.geography, d.gmv_tier, d.seller_tenure
ORDER BY d.geography, d.gmv_tier, d.seller_tenure;


-- ================================================================
-- SECTION 3 — EVENT CREATION QUALITY
--   Event Completion Rate, Abandonment Rate, daily trend
-- ================================================================

-- 3A. Daily event completion + abandonment rates
SELECT
    dt,
    SUM(numerator)                                                              AS published_events,
    SUM(denominator)                                                            AS cta_clicks,
    ROUND(SUM(numerator) * 100.0 / NULLIF(SUM(denominator), 0), 1)             AS event_completion_rate_pct,
    ROUND((1 - SUM(numerator) / NULLIF(SUM(denominator), 0)) * 100.0, 1)       AS event_abandonment_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
WHERE metric_name = 'Event Completion Rate'
GROUP BY dt
ORDER BY dt DESC;


-- 3B. Event completion rate by seller dimension (last 30 days)
SELECT
    onboarding_method,
    geography,
    gmv_tier,
    seller_tenure,
    SUM(numerator)                                                              AS published_events,
    SUM(denominator)                                                            AS cta_clicks,
    ROUND(SUM(numerator) * 100.0 / NULLIF(SUM(denominator), 0), 1)             AS event_completion_rate_pct,
    ROUND((1 - SUM(numerator) / NULLIF(SUM(denominator), 0)) * 100.0, 1)       AS event_abandonment_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
WHERE metric_name = 'Event Completion Rate'
  AND dt >= DATE_SUB(CURRENT_DATE, 30)
GROUP BY onboarding_method, geography, gmv_tier, seller_tenure
ORDER BY event_completion_rate_pct DESC;


-- 3C. CTA click volume by entry point (Create vs Create First Event)
SELECT
    session_start_dt                                                            AS dt,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS event_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
GROUP BY session_start_dt, event_type
ORDER BY dt DESC, event_type;


-- 3D. Onboarding flow distribution (what flow are sellers on when clicking CTA)
SELECT
    session_start_dt                                                            AS dt,
    onboarding_flow,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS event_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
GROUP BY session_start_dt, onboarding_flow
ORDER BY dt DESC, event_count DESC;


-- ================================================================
-- SECTION 4 — LISTING CREATION QUALITY
--   Listing Completion Rate, Express Listing Adoption,
--   Case Break Adoption, daily trend
-- ================================================================

-- 4A. Daily listing completion rate (Create Listings CTA → Create Listings button)
SELECT
    dt,
    SUM(numerator)                                                              AS completed_cnt,
    SUM(denominator)                                                            AS started_cnt,
    ROUND(SUM(numerator) * 100.0 / NULLIF(SUM(denominator), 0), 1)             AS listing_completion_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
WHERE metric_name = 'Express Listing Completion Rate'
GROUP BY dt
ORDER BY dt DESC;


-- 4B. Express Listing Adoption: daily rate
SELECT
    dt,
    SUM(total_listings)                                                         AS total_listings,
    SUM(express_listings)                                                       AS express_listings,
    SUM(case_break_listings)                                                    AS case_break_listings,
    ROUND(SUM(express_listings)     * 100.0 / NULLIF(SUM(total_listings), 0), 1) AS express_adoption_pct,
    ROUND(SUM(case_break_listings)  * 100.0 / NULLIF(SUM(total_listings), 0), 1) AS case_break_adoption_pct
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
GROUP BY dt
ORDER BY dt DESC;


-- 4C. Express vs case-break adoption by seller segment
SELECT
    d.geography,
    d.gmv_tier,
    d.category,
    d.seller_tenure,
    SUM(la.total_listings)                                                      AS total_listings,
    SUM(la.express_listings)                                                    AS express_listings,
    SUM(la.case_break_listings)                                                 AS case_break_listings,
    ROUND(SUM(la.express_listings)    * 100.0 / NULLIF(SUM(la.total_listings), 0), 1) AS express_adoption_pct,
    ROUND(SUM(la.case_break_listings) * 100.0 / NULLIF(SUM(la.total_listings), 0), 1) AS case_break_adoption_pct
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON CAST(la.seller_id AS STRING) = d.seller_id
WHERE la.dt >= DATE_SUB(CURRENT_DATE, 30)
GROUP BY d.geography, d.gmv_tier, d.category, d.seller_tenure
ORDER BY express_adoption_pct DESC;


-- 4D. Avg listings per event (express vs total) — per day
SELECT
    dt,
    COUNT(DISTINCT event_id)                                                    AS event_count,
    ROUND(SUM(total_listings)    / NULLIF(COUNT(DISTINCT event_id), 0), 1)      AS avg_total_listings_per_event,
    ROUND(SUM(express_listings)  / NULLIF(COUNT(DISTINCT event_id), 0), 1)      AS avg_express_listings_per_event,
    ROUND(SUM(case_break_listings) / NULLIF(COUNT(DISTINCT event_id), 0), 1)    AS avg_case_break_listings_per_event
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
GROUP BY dt
ORDER BY dt DESC;


-- 4E. Import modal path breakdown (which import method do sellers choose?)
SELECT
    session_start_dt                                                            AS dt,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS event_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
WHERE event_type IN (
    'Import Modal - From Template',
    'Import Modal - From Store',
    'Import Modal - Item ID / URL',
    'Import Modal - Add Listings',
    'Import Modal - Template Selected',
    'Import Listings - CTA Click'
)
GROUP BY session_start_dt, event_type
ORDER BY dt DESC, event_count DESC;


-- ================================================================
-- SECTION 5 — RECOMMENDATION QUALITY
--   Category Accept Rate, Shipping Policy Accept Rate
--   Definition: Accept Rate = 1 - (override clicks / modal impressions)
--
--   modal_impression = VIEW event with mi='2548'  (Create Modal)
--   category_override = ACTN on p4613028.m183399.l207370
--   shipping_override = ACTN on p4613028.m183399.l207390
--
--   Note: Override click means the seller changed the pre-filled
--   recommendation rather than accepting it.
-- ================================================================

-- 5A. Daily recommendation acceptance rates
SELECT
    session_start_dt                                                            AS dt,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Category'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS category_overrides,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Shipping Policy'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS shipping_overrides,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Edit'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS edit_clicks,
    -- Accept Rate = sessions without override / sessions with modal impression
    ROUND((1 - COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Category'
                                   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
               * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'
                                                   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0)
           ) * 100.0, 1)                                                        AS category_accept_rate_pct,
    ROUND((1 - COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Shipping Policy'
                                   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
               * 1.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'
                                                   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0)
           ) * 100.0, 1)                                                        AS shipping_accept_rate_pct,
    -- Override Rate (inverse of Accept Rate — for P1 diagnostic)
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Category'
                              THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'
                                               THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0), 1) AS category_override_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Shipping Policy'
                              THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'
                                               THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0), 1) AS shipping_override_rate_pct
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
GROUP BY session_start_dt
ORDER BY dt DESC;


-- 5B. Create Modal step-through funnel
--     Impression → Create Listings (key conversion inside modal)
SELECT
    session_start_dt                                                            AS dt,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression'         THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_impressions,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Edit'               THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_edit_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Category'           THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_category_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Shipping Policy'    THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_shipping_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Create Listings'    THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_create_listings,
    COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Dismiss'            THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS modal_dismiss,
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Create Listings' THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression' THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0), 1) AS modal_conversion_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Dismiss'      THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type = 'Create Modal - Impression' THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0), 1) AS modal_dismiss_rate_pct
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
GROUP BY session_start_dt
ORDER BY dt DESC;


-- ================================================================
-- SECTION 6 — ERROR GUARDRAILS
--   Event Error Rate: from EVENT_CREATION_BASE_PT.error_code
--
--   ⚠ Listing Error Rate is NOT available: error_code is NULL
--     in EXPRESS_LISTINGS_BASE_PT.
--   ⚠ Mandatory Field vs Category Restriction split requires
--     knowing specific error_code values in your environment.
-- ================================================================

-- 6A. Daily event error rate (all errors)
SELECT
    session_start_dt                                                            AS dt,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS total_events,
    COUNT(DISTINCT CASE WHEN error_code IS NOT NULL AND error_code != ''
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS error_events,
    ROUND(COUNT(DISTINCT CASE WHEN error_code IS NOT NULL AND error_code != ''
                              THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM), 0), 1) AS event_error_rate_pct
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
GROUP BY session_start_dt
ORDER BY dt DESC;


-- 6B. Error code distribution — identify top error types
SELECT
    session_start_dt                                                            AS dt,
    error_code,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS error_event_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers_affected
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE error_code IS NOT NULL AND error_code != ''
GROUP BY session_start_dt, error_code
ORDER BY dt DESC, error_event_count DESC;
-- After reviewing: replace <mandatory_field_error_code> and <category_restriction_error_code>
-- below with the actual error codes from query 6B results.


-- 6C. Mandatory field vs category restriction error split
--     ⚠ Replace error code placeholders after running 6B
SELECT
    session_start_dt                                                            AS dt,
    COUNT(DISTINCT CASE WHEN error_code = '<mandatory_field_error_code>'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS mandatory_field_errors,
    COUNT(DISTINCT CASE WHEN error_code = '<category_restriction_error_code>'
                        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS category_restriction_errors,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS total_events,
    ROUND(COUNT(DISTINCT CASE WHEN error_code = '<mandatory_field_error_code>'
                              THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM), 0), 1) AS mandatory_field_error_rate_pct,
    ROUND(COUNT(DISTINCT CASE WHEN error_code = '<category_restriction_error_code>'
                              THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM), 0), 1) AS category_restriction_error_rate_pct
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
GROUP BY session_start_dt
ORDER BY dt DESC;


-- ================================================================
-- SECTION 7 — P1 DIAGNOSTICS
--   Draft Save Rate, Draft→Publish Conversion,
--   Updates Before Publish, Category/Shipping Override Rate,
--   Listing Row Edit behavior
-- ================================================================

-- 7A. Draft Save Rate + Draft→Publish Conversion
--   ⚠ The shared SID (p4613031.m173558.l191918) cannot distinguish
--     save-as-draft vs publish via UBI — both actions fire the same
--     event. This query treats all saves as "form submissions" and
--     compares to actual published events from LIVE_EVENT.
SELECT
    b.session_start_dt                                                          AS dt,
    COUNT(DISTINCT b.SESSION_START_DT || b.GUID || b.SESSION_SKEY || b.SEQNUM) AS form_save_events,  -- primary save SID
    COUNT(DISTINCT c.SESSION_START_DT || c.GUID || c.SESSION_SKEY || c.SEQNUM) AS secondary_save_events,  -- secondary save SID
    COUNT(DISTINCT b.user_id)                                                   AS sellers_with_save,
    -- Draft→Publish: of sellers who saved (via form), how many eventually published?
    COUNT(DISTINCT pub.seller_id)                                               AS sellers_who_published
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT b
LEFT JOIN P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT c
    ON  b.user_id          = c.user_id
    AND c.event_type        = 'Event Form - Save or Publish (secondary)'
LEFT JOIN (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
) pub ON b.user_id = pub.seller_id
WHERE b.event_type = 'Event Form - Save as draft or Publish'
GROUP BY b.session_start_dt
ORDER BY dt DESC;


-- 7B. Updates before publish — avg secondary save actions per seller (proxy for edit iterations)
--   'Event Form - Save or Publish (secondary)' fires each time a seller updates the form.
--   High numbers suggest friction in the form or seller confusion.
WITH secondary_saves_per_seller AS (
    SELECT
        session_start_dt                                                        AS dt,
        user_id                                                                 AS seller_id,
        COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)     AS secondary_save_count
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type = 'Event Form - Save or Publish (secondary)'
    GROUP BY session_start_dt, user_id
)
SELECT
    dt,
    COUNT(DISTINCT seller_id)                                                   AS sellers_with_edits,
    ROUND(AVG(secondary_save_count), 2)                                         AS avg_edits_before_publish,
    PERCENTILE_APPROX(secondary_save_count, 0.50, 10000)                        AS p50_edits,
    PERCENTILE_APPROX(secondary_save_count, 0.75, 10000)                        AS p75_edits,
    PERCENTILE_APPROX(secondary_save_count, 0.90, 10000)                        AS p90_edits,
    COUNT(DISTINCT CASE WHEN secondary_save_count > 5 THEN seller_id END)       AS sellers_above_5_edits,
    ROUND(COUNT(DISTINCT CASE WHEN secondary_save_count > 5 THEN seller_id END)
          * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0), 1)                    AS pct_above_5_edits_threshold
FROM secondary_saves_per_seller
GROUP BY dt
ORDER BY dt DESC;


-- 7C. Category and Shipping Policy Override Rate (P1 Diagnostic)
--     Reuses Section 5A logic — standalone version for the P1 table
SELECT
    DATE_TRUNC('week', session_start_dt)                                        AS week_start,
    SUM(CASE WHEN event_type = 'Create Modal - Impression'      THEN 1 ELSE 0 END) AS modal_impressions,
    SUM(CASE WHEN event_type = 'Create Modal - Category'         THEN 1 ELSE 0 END) AS category_override_clicks,
    SUM(CASE WHEN event_type = 'Create Modal - Shipping Policy'  THEN 1 ELSE 0 END) AS shipping_override_clicks,
    ROUND(SUM(CASE WHEN event_type = 'Create Modal - Category' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN event_type = 'Create Modal - Impression' THEN 1 ELSE 0 END), 0), 1) AS category_override_rate_pct,
    ROUND(SUM(CASE WHEN event_type = 'Create Modal - Shipping Policy' THEN 1 ELSE 0 END)
          * 100.0 / NULLIF(SUM(CASE WHEN event_type = 'Create Modal - Impression' THEN 1 ELSE 0 END), 0), 1) AS shipping_override_rate_pct
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
GROUP BY DATE_TRUNC('week', session_start_dt)
ORDER BY week_start DESC;


-- 7D. Listing row edit behavior — how often do sellers edit after creating?
SELECT
    session_start_dt                                                            AS dt,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing Row - Edit (Pencil)'   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS pencil_edit_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing Row - Overflow Menu'   THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS overflow_menu_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing Row - Save Update'     THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS save_update_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing Row - Close Edit'      THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS close_edit_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing - Duplicate'           THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS duplicate_clicks,
    COUNT(DISTINCT CASE WHEN event_type = 'Listing - Draft Update'        THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS draft_update_clicks,
    -- Save rate within edit sessions: of edits opened, how many were saved vs closed?
    ROUND(COUNT(DISTINCT CASE WHEN event_type = 'Listing Row - Save Update' THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END)
          * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN event_type IN ('Listing Row - Edit (Pencil)', 'Listing Row - Overflow Menu')
                                               THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END), 0), 1) AS edit_save_rate_pct
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
GROUP BY session_start_dt
ORDER BY dt DESC;


-- ================================================================
-- SECTION 8 — COMPLETION TIME  (P50 / P75 / P90 / AVG)
--   Event Completion Time: CTA click → event publish
--   Express Listing Completion Time: CTA click → listing created
-- ================================================================

-- 8A. Daily event completion time percentiles (exclude NULLs = unmatched)
SELECT
    dt,
    metric_name,
    COUNT(*)                                                                    AS total_rows,
    COUNT(diff_in_minutes)                                                      AS matched_rows,
    ROUND(COUNT(diff_in_minutes) * 100.0 / NULLIF(COUNT(*), 0), 1)             AS match_rate_pct,
    PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                            AS p50_minutes,
    PERCENTILE_APPROX(diff_in_minutes, 0.75, 10000)                            AS p75_minutes,
    PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                            AS p90_minutes,
    ROUND(AVG(diff_in_minutes), 2)                                              AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE diff_in_minutes IS NOT NULL
  AND diff_in_minutes >= 0
GROUP BY dt, metric_name
ORDER BY dt DESC, metric_name;


-- 8B. Weekly completion time by metric + seller segment
SELECT
    DATE_TRUNC('week', dt)                                                      AS week_start,
    metric_name,
    geography,
    gmv_tier,
    seller_tenure,
    COUNT(*)                                                                    AS total_rows,
    COUNT(diff_in_minutes)                                                      AS matched_rows,
    PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                            AS p50_minutes,
    PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                            AS p90_minutes,
    ROUND(AVG(diff_in_minutes), 2)                                              AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE diff_in_minutes IS NOT NULL
  AND diff_in_minutes >= 0
GROUP BY DATE_TRUNC('week', dt), metric_name, geography, gmv_tier, seller_tenure
ORDER BY week_start DESC, metric_name;


-- 8C. Express listing time — express vs non-express split
SELECT
    dt,
    is_express,
    COUNT(*)                                                                    AS listing_count,
    COUNT(diff_in_minutes)                                                      AS matched_count,
    PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                            AS p50_minutes,
    PERCENTILE_APPROX(diff_in_minutes, 0.75, 10000)                            AS p75_minutes,
    PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                            AS p90_minutes,
    ROUND(AVG(diff_in_minutes), 2)                                              AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE metric_name = 'Express Listing Completion Time'
  AND diff_in_minutes IS NOT NULL
  AND diff_in_minutes >= 0
GROUP BY dt, is_express
ORDER BY dt DESC, is_express;


-- 8D. CTA-to-publish match rate (data quality check)
--     What % of published events/listings had a preceding CTA click?
SELECT
    metric_name,
    COUNT(*)                                                                    AS total,
    COUNT(last_cta_ts)                                                          AS matched,
    ROUND(COUNT(last_cta_ts) * 100.0 / NULLIF(COUNT(*), 0), 1)                 AS match_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE dt >= DATE_SUB(CURRENT_DATE, 30)
GROUP BY metric_name;


-- ================================================================
-- SECTION 9 — NAVIGATION FUNNEL (Live Studio entry + side menu)
--   Tracks how sellers navigate into the creation flows.
-- ================================================================

-- 9A. Daily navigation event volume by type
SELECT
    session_start_dt                                                            AS dt,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS event_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
GROUP BY session_start_dt, event_type
ORDER BY dt DESC, event_count DESC;


-- 9B. Entry-to-CTA conversion rate
--     How many sellers who entered Live Studio (from Seller Hub) clicked Create Event CTA?
WITH studio_entries AS (
    SELECT DISTINCT
        session_start_dt,
        user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
    WHERE event_type = 'Live Studio - Entry (Seller Hub)'
),
cta_clicks AS (
    SELECT DISTINCT
        session_start_dt,
        user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
)
SELECT
    se.session_start_dt                                                         AS dt,
    COUNT(DISTINCT se.seller_id)                                                AS studio_entry_sellers,
    COUNT(DISTINCT cc.seller_id)                                                AS sellers_who_clicked_cta,
    ROUND(COUNT(DISTINCT cc.seller_id) * 100.0
          / NULLIF(COUNT(DISTINCT se.seller_id), 0), 1)                         AS entry_to_cta_rate_pct
FROM studio_entries se
LEFT JOIN cta_clicks cc
    ON  se.seller_id = cc.seller_id
    AND se.session_start_dt = cc.session_start_dt
GROUP BY se.session_start_dt
ORDER BY dt DESC;


-- 9C. Events page impression → CTA click rate (same session)
WITH events_page_views AS (
    SELECT DISTINCT session_start_dt, user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
    WHERE event_type = 'Events Page - Impression'
),
cta_clicks AS (
    SELECT DISTINCT session_start_dt, user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
)
SELECT
    ep.session_start_dt                                                         AS dt,
    COUNT(DISTINCT ep.seller_id)                                                AS events_page_viewers,
    COUNT(DISTINCT cc.seller_id)                                                AS sellers_who_clicked_cta,
    ROUND(COUNT(DISTINCT cc.seller_id) * 100.0
          / NULLIF(COUNT(DISTINCT ep.seller_id), 0), 1)                         AS events_page_to_cta_rate_pct
FROM events_page_views ep
LEFT JOIN cta_clicks cc
    ON  ep.seller_id = cc.seller_id
    AND ep.session_start_dt = cc.session_start_dt
GROUP BY ep.session_start_dt
ORDER BY dt DESC;


-- 9D. Side menu navigation breakdown (where do sellers navigate from Live Studio?)
SELECT
    session_start_dt                                                            AS dt,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)         AS click_count,
    COUNT(DISTINCT user_id)                                                     AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
WHERE event_type LIKE 'Side Menu%'
GROUP BY session_start_dt, event_type
ORDER BY dt DESC, click_count DESC;


-- ================================================================
-- SECTION 10 — FULL P0/P1 METRIC SUMMARY TABLE
--   Single query outputting all key Pre-Stream rates for a
--   given time window — suitable for a scorecard row.
-- ================================================================

WITH event_completion AS (
    SELECT
        SUM(numerator)                                                          AS published_events,
        SUM(denominator)                                                        AS cta_clicks
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
    WHERE metric_name = 'Event Completion Rate'
      AND dt >= DATE_SUB(CURRENT_DATE, 30)
),
listing_completion AS (
    SELECT
        SUM(numerator)                                                          AS completed_listings,
        SUM(denominator)                                                        AS started_listings
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
    WHERE metric_name = 'Express Listing Completion Rate'
      AND dt >= DATE_SUB(CURRENT_DATE, 30)
),
express_adoption AS (
    SELECT
        SUM(express_listings)                                                   AS express_listings,
        SUM(total_listings)                                                     AS total_listings
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE dt >= DATE_SUB(CURRENT_DATE, 30)
),
recommendation AS (
    SELECT
        SUM(CASE WHEN event_type = 'Create Modal - Impression'    THEN 1 ELSE 0 END) AS modal_impressions,
        SUM(CASE WHEN event_type = 'Create Modal - Category'      THEN 1 ELSE 0 END) AS category_overrides,
        SUM(CASE WHEN event_type = 'Create Modal - Shipping Policy' THEN 1 ELSE 0 END) AS shipping_overrides
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
    WHERE session_start_dt >= DATE_SUB(CURRENT_DATE, 30)
),
errors AS (
    SELECT
        COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)     AS total_events,
        COUNT(DISTINCT CASE WHEN error_code IS NOT NULL AND error_code != ''
                            THEN SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM END) AS error_events
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE session_start_dt >= DATE_SUB(CURRENT_DATE, 30)
),
setup_funnel AS (
    SELECT
        COUNT(DISTINCT ss.seller_id)                                            AS setup_started,
        COUNT(DISTINCT pe.seller_id)                                            AS published,
        COUNT(DISTINCT ls.seller_id)                                            AS listing_ready,
        COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL THEN ss.seller_id END) AS first_show_ready,
        COUNT(DISTINCT CASE WHEN fsd.first_stream_dt >= fc.first_cta_dt
                              AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
                            THEN ss.seller_id END) AS streamed_14d
    FROM (
        SELECT DISTINCT user_id AS seller_id
        FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
        WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
          AND session_start_dt >= DATE_SUB(CURRENT_DATE, 30)
    ) ss
    LEFT JOIN (SELECT DISTINCT seller_id FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T WHERE published_cnt > 0) pe ON ss.seller_id = pe.seller_id
    LEFT JOIN (SELECT DISTINCT seller_id FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T WHERE total_listings > 0) ls ON ss.seller_id = ls.seller_id
    LEFT JOIN (SELECT user_id AS seller_id, MIN(session_start_dt) AS first_cta_dt FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click') GROUP BY user_id) fc ON ss.seller_id = fc.seller_id
    LEFT JOIN (SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS WHERE deleted_ind = 0 AND event_duration_min > 0 GROUP BY slr_id) fsd ON ss.seller_id = fsd.seller_id
)
SELECT
    -- L0
    ROUND(sf.first_show_ready * 100.0 / NULLIF(sf.setup_started, 0), 1)        AS seller_setup_success_rate_pct,
    -- P0
    ROUND(sf.published        * 100.0 / NULLIF(sf.setup_started, 0), 1)        AS event_creation_rate_pct,
    ROUND(sf.listing_ready    * 100.0 / NULLIF(sf.setup_started, 0), 1)        AS listing_readiness_rate_pct,
    ROUND(sf.first_show_ready * 100.0 / NULLIF(sf.setup_started, 0), 1)        AS first_show_ready_rate_pct,
    ROUND(sf.streamed_14d     * 100.0 / NULLIF(sf.setup_started, 0), 1)        AS fourteen_day_first_show_rate_pct,
    ROUND(ea.express_listings * 100.0 / NULLIF(ea.total_listings, 0), 1)       AS express_listing_adoption_pct,
    -- Event quality
    ROUND(ec.published_events * 100.0 / NULLIF(ec.cta_clicks, 0), 1)           AS event_completion_rate_pct,
    ROUND((1 - ec.published_events / NULLIF(ec.cta_clicks, 0)) * 100.0, 1)     AS event_abandonment_rate_pct,
    -- Listing quality
    ROUND(lc.completed_listings * 100.0 / NULLIF(lc.started_listings, 0), 1)   AS listing_completion_rate_pct,
    -- Recommendation quality
    ROUND((1 - rec.category_overrides / NULLIF(rec.modal_impressions, 0)) * 100.0, 1) AS category_accept_rate_pct,
    ROUND((1 - rec.shipping_overrides / NULLIF(rec.modal_impressions, 0)) * 100.0, 1) AS shipping_accept_rate_pct,
    ROUND(rec.category_overrides * 100.0 / NULLIF(rec.modal_impressions, 0), 1) AS category_override_rate_pct,
    ROUND(rec.shipping_overrides * 100.0 / NULLIF(rec.modal_impressions, 0), 1) AS shipping_override_rate_pct,
    -- Error guardrail
    ROUND(err.error_events * 100.0 / NULLIF(err.total_events, 0), 1)            AS event_error_rate_pct,
    -- Raw counts for context
    sf.setup_started,
    sf.published,
    sf.listing_ready,
    sf.first_show_ready,
    sf.streamed_14d,
    ec.cta_clicks,
    ec.published_events,
    ea.total_listings,
    ea.express_listings,
    err.total_events,
    err.error_events
FROM event_completion ec, listing_completion lc, express_adoption ea,
     recommendation rec, errors err, setup_funnel sf;


-- ================================================================
-- NOTES ON NOT-AVAILABLE METRICS
--
-- 1. Listing Error Rate
--    EXPRESS_LISTINGS_BASE_PT.error_code = NULL for all rows.
--    No listing-level error tracking is wired via UBI on this page.
--    Recommendation: add error_code SID capture in the B section
--    base table when instrumentation is available.
--
-- 2. Mandatory Field Error Rate vs Category Restriction Error Rate
--    Both are subsets of Section 6A (event_error_rate_pct).
--    Run Section 6B to enumerate actual error_code values, then
--    substitute them into Section 6C placeholders.
--
-- 3. "Draft Save Rate" vs "Draft Save → Publish Conversion" split
--    SID p4613031.m173558.l191918 fires for BOTH Save as Draft AND
--    Publish (shared SID, cannot split via UBI per code comments).
--    Section 7A approximates this by comparing form save events to
--    actual published count from LIVE_EVENT via EVENT_COMPLETION_RATE_T.
-- ================================================================
