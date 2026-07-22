-- ================================================================
-- PRE-STREAM TAB — GRAIN & FILTER AWARE SQL  (v2)
-- Dashboard: eBay Live Opening Up — Pre-Stream Tab
-- Repo: github.corp.ebay.com/eBay-Live-DS/ebay-live-opening-up-dashboard
--
-- CHANGES FROM v1
--   • Section 1 rewritten: Event Published / Event Creation from
--     COMPLETION_RATE_FINAL_T — no extra joins, dim columns already in table
--   • Section 2 rewritten using LIVE_SELLER_MASTER_V2 as setup base and
--     SELLER_FIRST_SHOW_FUNNEL for funnel steps
--   • Sections 3–4C, 8A/B: dim re-join removed; pre-joined geography /
--     launch_phase / category / gmv_tier columns read directly from
--     COMPLETION_RATE_FINAL_T, LISTING_ADOPTION_T, COMPLETION_TIME_FINAL_T
--   • Section 10B scorecard reworked to match Sections 1–2 sources
--   • Fixed integer-division bug in event_abandonment_rate_pct (Section 10B)
--   • Sections 4D, 5, 6, 7, 9 commented out (not wired to KPI tiles)
--   • Added onboarding_method and seller_background as filter dims
--     alongside geography / launch_phase / category / gmv_tier
--     wherever those columns appear
--
-- GRAIN TOGGLE: Overall | Daily | Weekly (retail) | Monthly (MTD)
-- FILTER DIMS:  geography | launch_phase | category | gmv_tier |
--               onboarding_method | seller_background
--
-- HOW MASTER QUERIES WORK
--   Each master query returns one row per:
--     (day_period, rtl_week_beg_dt, rtl_week_end_dt, month_period,
--      geography, launch_phase, category, gmv_tier,
--      onboarding_method, seller_background)
--   with RAW COUNTS (numerator + denominator) — NOT pre-computed rates.
--
--   Dashboard applies grain by grouping on the right period column:
--     Overall  → SUM all rows (no GROUP BY on period)
--     Daily    → GROUP BY day_period
--     Weekly   → GROUP BY rtl_week_beg_dt, rtl_week_end_dt
--     Monthly  → WHERE month_period = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM')
--                GROUP BY month_period        (MTD: rows up to today)
--
--   Dashboard applies filter:
--     WHERE geography = 'US' AND launch_phase = 'Wave 1'
--       AND onboarding_method = 'Self-Serve' ...  (omit for All)
--
--   Rate computation: ROUND(SUM(numerator)*100.0/NULLIF(SUM(denominator),0),1)
--
-- SOURCE TABLES
--   D   P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
--   E   P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
--   F   P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
--   G   P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL
--   S   P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2           [Section 2 setup base]
--   DIM P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM
--   CAL access_views.dw_cal_rtl_week
-- ================================================================


-- ================================================================
-- SECTION 1 — SELLER SETUP SUCCESS RATE  (Master Grain + Filter)
--
--   Metric     : Distinct sellers completed / Distinct sellers started
--   Denominator: sellers_started  — seller had ≥1 CTA click (denominator > 0)
--   Numerator  : sellers_completed — seller published ≥1 event (numerator > 0)
--   Grain date : activity date (dt)
--   Dim columns already joined into COMPLETION_RATE_FINAL_T — no re-join needed.
--
--   NOTE: COUNT(DISTINCT seller_id) is exact within a single day/dim combo.
--   For weekly/monthly, dashboard should re-aggregate with COUNT(DISTINCT)
--   across the full date range rather than SUMming daily distinct counts.
-- ================================================================

SELECT
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd')                                        AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM')                                           AS month_period,
    COALESCE(crf.geography,         'Unknown')                                AS geography,
    COALESCE(crf.launch_phase,      'Unknown')                                AS launch_phase,
    COALESCE(crf.category,          'Unknown')                                AS category,
    COALESCE(crf.gmv_tier,          'Unknown')                                AS gmv_tier,
    COALESCE(crf.onboarding_method, 'Unknown')                                AS onboarding_method,
    COALESCE(crf.seller_background, 'Unknown')                                AS seller_background,
    COUNT(DISTINCT CASE WHEN crf.denominator > 0 THEN crf.seller_id END)     AS setup_started,
    COUNT(DISTINCT CASE WHEN crf.numerator   > 0 THEN crf.seller_id END)     AS setup_success
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  crf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE crf.metric_name = 'Event Completion Rate'
GROUP BY
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM'),
    COALESCE(crf.geography,         'Unknown'),
    COALESCE(crf.launch_phase,      'Unknown'),
    COALESCE(crf.category,          'Unknown'),
    COALESCE(crf.gmv_tier,          'Unknown'),
    COALESCE(crf.onboarding_method, 'Unknown'),
    COALESCE(crf.seller_background, 'Unknown')
ORDER BY day_period DESC;


-- ================================================================
-- SECTION 2 — P0 FULL FUNNEL  (Master Grain + Filter)
--
--   Step 0 — Setup Started    : activated_studio = 1 in LIVE_SELLER_MASTER_V2
--   Step 1 — Event Created    : seller published ≥1 event (COMPLETION_RATE_FINAL_T)
--   Step 2 — Listing Ready    : seller has ≥1 listing in a live event (LISTING_ADOPTION_T)
--   Step 3 — First Show Ready : event created AND listing ready (steps 1 ∩ 2)
--   Step 4 — 14-Day First Show: streamed within 14d of studio activation
--                                (SELLER_FIRST_SHOW_FUNNEL)
--
--   Grain date = studio_activated_ts (cohort entry date)
--   Dashboard computes step rates as step_N / step0_setup_started.
-- ================================================================

WITH setup_base AS (
    SELECT
        user_id_ubi                                                AS sellerid,
        CAST(studio_activated_ts AS DATE)                          AS activated_dt
    FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
    WHERE report_dt    = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
      AND is_test_user = 0
      AND activated_studio    = 1
      AND studio_activated_ts IS NOT NULL
),
published_sellers AS (
    -- Step 1: seller has published ≥1 event (numerator > 0 in Event Completion Rate)
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
    WHERE metric_name = 'Event Completion Rate'
      AND numerator   > 0
),
listing_sellers AS (
    -- Step 2: seller has ≥1 listing attached to a live event
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
    WHERE total_listings > 0
),
streamed_sellers AS (
    -- Step 4: seller streamed within 14 days of studio activation
    SELECT DISTINCT sellerid AS seller_id
    FROM P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL
    WHERE streamed_within_14d_of_studio_activation = 1
)
SELECT
    DATE_FORMAT(sb.activated_dt, 'yyyy-MM-dd')                     AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(sb.activated_dt, 'yyyy-MM')                        AS month_period,
    COALESCE(d.geography,         'Unknown')                        AS geography,
    COALESCE(d.launch_phase,      'Unknown')                        AS launch_phase,
    COALESCE(d.category,          'Unknown')                        AS category,
    COALESCE(d.gmv_tier,          'Unknown')                        AS gmv_tier,
    COALESCE(d.onboarding_method, 'Unknown')                        AS onboarding_method,
    COALESCE(d.seller_background, 'Unknown')                        AS seller_background,
    COUNT(DISTINCT sb.sellerid)                                     AS step0_setup_started,
    COUNT(DISTINCT pe.seller_id)                                    AS step1_event_created,
    COUNT(DISTINCT ls.seller_id)                                    AS step2_listing_ready,
    COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL
                         AND ls.seller_id IS NOT NULL
                        THEN sb.sellerid END)                       AS step3_first_show_ready,
    COUNT(DISTINCT ss.seller_id)                                    AS step4_14d_first_show
FROM setup_base sb
LEFT JOIN published_sellers pe  ON sb.sellerid = pe.seller_id
LEFT JOIN listing_sellers   ls  ON sb.sellerid = ls.seller_id
LEFT JOIN streamed_sellers  ss  ON sb.sellerid = ss.seller_id
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(sb.sellerid AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  sb.activated_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(sb.activated_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(sb.activated_dt, 'yyyy-MM'),
    COALESCE(d.geography,         'Unknown'),
    COALESCE(d.launch_phase,      'Unknown'),
    COALESCE(d.category,          'Unknown'),
    COALESCE(d.gmv_tier,          'Unknown'),
    COALESCE(d.onboarding_method, 'Unknown'),
    COALESCE(d.seller_background, 'Unknown')
ORDER BY day_period DESC;


-- ================================================================
-- SECTION 3 — EVENT COMPLETION QUALITY  (Master Grain + Filter)
--
--   Metric: Event Completion Rate = published events / CTA clicks
--   Source: COMPLETION_RATE_FINAL_T (dim columns already joined in)
--   Grain date = activity date (dt)
-- ================================================================

SELECT
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM')                                 AS month_period,
    COALESCE(crf.geography,         'Unknown')                      AS geography,
    COALESCE(crf.launch_phase,      'Unknown')                      AS launch_phase,
    COALESCE(crf.category,          'Unknown')                      AS category,
    COALESCE(crf.gmv_tier,          'Unknown')                      AS gmv_tier,
    COALESCE(crf.onboarding_method, 'Unknown')                      AS onboarding_method,
    COALESCE(crf.seller_background, 'Unknown')                      AS seller_background,
    SUM(crf.numerator)                                              AS published_events,
    SUM(crf.denominator)                                            AS cta_clicks
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  crf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE crf.metric_name = 'Event Completion Rate'
GROUP BY
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM'),
    COALESCE(crf.geography,         'Unknown'),
    COALESCE(crf.launch_phase,      'Unknown'),
    COALESCE(crf.category,          'Unknown'),
    COALESCE(crf.gmv_tier,          'Unknown'),
    COALESCE(crf.onboarding_method, 'Unknown'),
    COALESCE(crf.seller_background, 'Unknown')
ORDER BY day_period DESC;


-- 3B. CTA click entry point breakdown by grain (diagnostic — grain only)
--     Source: EVENT_CREATION_BASE_PT. No seller dim available.
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                    AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                       AS month_period,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS event_count,
    COUNT(DISTINCT user_id)                                         AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM'),
    event_type
ORDER BY day_period DESC;


-- ================================================================
-- SECTION 4 — LISTING CREATION QUALITY  (Master Grain + Filter)
-- ================================================================

-- 4A. Listing Completion Rate
--     Source: COMPLETION_RATE_FINAL_T (dim columns already joined in)
SELECT
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM')                                 AS month_period,
    COALESCE(crf.geography,         'Unknown')                      AS geography,
    COALESCE(crf.launch_phase,      'Unknown')                      AS launch_phase,
    COALESCE(crf.category,          'Unknown')                      AS category,
    COALESCE(crf.gmv_tier,          'Unknown')                      AS gmv_tier,
    COALESCE(crf.onboarding_method, 'Unknown')                      AS onboarding_method,
    COALESCE(crf.seller_background, 'Unknown')                      AS seller_background,
    SUM(crf.numerator)                                              AS completed_listings,
    SUM(crf.denominator)                                            AS started_listings
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  crf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE crf.metric_name = 'Express Listing Completion Rate'
GROUP BY
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM'),
    COALESCE(crf.geography,         'Unknown'),
    COALESCE(crf.launch_phase,      'Unknown'),
    COALESCE(crf.category,          'Unknown'),
    COALESCE(crf.gmv_tier,          'Unknown'),
    COALESCE(crf.onboarding_method, 'Unknown'),
    COALESCE(crf.seller_background, 'Unknown')
ORDER BY day_period DESC;


-- 4B. Express Listing Adoption
--     Source: LISTING_ADOPTION_T (dim columns already joined in)
SELECT
    DATE_FORMAT(la.dt, 'yyyy-MM-dd')                               AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM')                                  AS month_period,
    COALESCE(la.geography,         'Unknown')                       AS geography,
    COALESCE(la.launch_phase,      'Unknown')                       AS launch_phase,
    COALESCE(la.category,          'Unknown')                       AS category,
    COALESCE(la.gmv_tier,          'Unknown')                       AS gmv_tier,
    COALESCE(la.onboarding_method, 'Unknown')                       AS onboarding_method,
    COALESCE(la.seller_background, 'Unknown')                       AS seller_background,
    SUM(la.total_listings)                                          AS total_listings,
    SUM(la.express_listings)                                        AS express_listings,
    SUM(la.case_break_listings)                                     AS case_break_listings
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  la.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(la.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM'),
    COALESCE(la.geography,         'Unknown'),
    COALESCE(la.launch_phase,      'Unknown'),
    COALESCE(la.category,          'Unknown'),
    COALESCE(la.gmv_tier,          'Unknown'),
    COALESCE(la.onboarding_method, 'Unknown'),
    COALESCE(la.seller_background, 'Unknown')
ORDER BY day_period DESC;


-- 4C. Avg listings per event by grain (diagnostic)
--     Source: LISTING_ADOPTION_T (dim columns already joined in)
SELECT
    DATE_FORMAT(la.dt, 'yyyy-MM-dd')                               AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM')                                  AS month_period,
    COALESCE(la.geography,         'Unknown')                       AS geography,
    COALESCE(la.launch_phase,      'Unknown')                       AS launch_phase,
    COALESCE(la.category,          'Unknown')                       AS category,
    COALESCE(la.gmv_tier,          'Unknown')                       AS gmv_tier,
    COALESCE(la.onboarding_method, 'Unknown')                       AS onboarding_method,
    COALESCE(la.seller_background, 'Unknown')                       AS seller_background,
    COUNT(DISTINCT la.event_id)                                     AS event_count,
    SUM(la.total_listings)                                          AS total_listings,
    SUM(la.express_listings)                                        AS express_listings
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  la.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(la.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM'),
    COALESCE(la.geography,         'Unknown'),
    COALESCE(la.launch_phase,      'Unknown'),
    COALESCE(la.category,          'Unknown'),
    COALESCE(la.gmv_tier,          'Unknown'),
    COALESCE(la.onboarding_method, 'Unknown'),
    COALESCE(la.seller_background, 'Unknown')
ORDER BY day_period DESC;


/*
-- ================================================================
-- SECTION 4D — Import modal path breakdown (diagnostic — grain only)
--   ⚠ Not wired to KPI tiles. Commented out for dashboard build.
-- ================================================================
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS event_count,
    COUNT(DISTINCT user_id)                                        AS unique_sellers
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE event_type IN (
    'Import Modal - From Template',
    'Import Modal - From Store',
    'Import Modal - Item ID / URL',
    'Import Modal - Add Listings',
    'Import Modal - Template Selected',
    'Import Listings - CTA Click'
)
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM'),
    event_type
ORDER BY day_period DESC, event_count DESC;
*/


/*
-- ================================================================
-- SECTION 5 — RECOMMENDATION QUALITY  (Grain Only)
--   ⚠ Not wired to KPI tiles. Commented out for dashboard build.
--   EXPRESS_LISTINGS_BASE_PT has no seller_id — filter dims unavailable.
-- ================================================================
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    SUM(CASE WHEN event_type = 'Create Modal - Impression'        THEN 1 ELSE 0 END) AS modal_impressions,
    SUM(CASE WHEN event_type = 'Create Modal - Category'          THEN 1 ELSE 0 END) AS category_overrides,
    SUM(CASE WHEN event_type = 'Create Modal - Shipping Policy'   THEN 1 ELSE 0 END) AS shipping_overrides,
    SUM(CASE WHEN event_type = 'Create Modal - Create Listings'   THEN 1 ELSE 0 END) AS modal_conversions,
    SUM(CASE WHEN event_type = 'Create Modal - Dismiss'           THEN 1 ELSE 0 END) AS modal_dismisses,
    SUM(CASE WHEN event_type = 'Create Modal - Edit'              THEN 1 ELSE 0 END) AS modal_edits
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')
ORDER BY day_period DESC;
*/


/*
-- ================================================================
-- SECTION 6 — ERROR GUARDRAILS  (Master Grain + Filter)
--   ⚠ Not wired to KPI tiles. Commented out for dashboard build.
-- ================================================================

-- 6A. Event error rate by grain + filter
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT ec.SESSION_START_DT || ec.GUID || ec.SESSION_SKEY || ec.SEQNUM)  AS total_events,
    COUNT(DISTINCT CASE WHEN ec.error_code IS NOT NULL AND ec.error_code != ''
        THEN ec.SESSION_START_DT || ec.GUID || ec.SESSION_SKEY || ec.SEQNUM END)    AS error_events
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT ec
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(ec.user_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ec.session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;

-- 6B. Error code distribution (diagnostic)
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    error_code,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS error_event_count,
    COUNT(DISTINCT user_id)                                        AS unique_sellers_affected
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE error_code IS NOT NULL AND error_code != ''
GROUP BY DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'), error_code
ORDER BY day_period DESC, error_event_count DESC;
*/


/*
-- ================================================================
-- SECTION 7 — P1 DIAGNOSTICS
--   ⚠ Not wired to KPI tiles. Commented out for dashboard build.
-- ================================================================

-- 7A. Draft Save + Draft→Publish Conversion (grain only)
SELECT
    DATE_FORMAT(b.session_start_dt, 'yyyy-MM-dd')                 AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(b.session_start_dt, 'yyyy-MM')                    AS month_period,
    COUNT(DISTINCT b.SESSION_START_DT || b.GUID || b.SESSION_SKEY || b.SEQNUM) AS form_save_events,
    COUNT(DISTINCT b.user_id)                                      AS sellers_with_save,
    COUNT(DISTINCT pub.seller_id)                                  AS sellers_who_published
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT b
LEFT JOIN (
    SELECT DISTINCT seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
    WHERE published_cnt > 0
) pub ON b.user_id = pub.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  b.session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE b.event_type = 'Event Form - Save as draft or Publish'
GROUP BY
    DATE_FORMAT(b.session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(b.session_start_dt, 'yyyy-MM')
ORDER BY day_period DESC;

-- 7B. Updates before publish — avg secondary save actions (grain only)
WITH secondary_saves AS (
    SELECT
        session_start_dt,
        user_id                                                    AS seller_id,
        COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS save_count
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type = 'Event Form - Save or Publish (secondary)'
    GROUP BY session_start_dt, user_id
)
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    COUNT(DISTINCT ss.seller_id)                                   AS sellers_with_edits,
    ROUND(AVG(ss.save_count), 2)                                   AS avg_edits_before_publish,
    PERCENTILE_APPROX(ss.save_count, 0.50, 10000)                  AS p50_edits,
    PERCENTILE_APPROX(ss.save_count, 0.90, 10000)                  AS p90_edits
FROM secondary_saves ss
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ss.session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')
ORDER BY day_period DESC;

-- 7C. Listing row edit behavior by grain (diagnostic)
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    SUM(CASE WHEN event_type = 'Listing Row - Edit (Pencil)'   THEN 1 ELSE 0 END) AS pencil_edit_clicks,
    SUM(CASE WHEN event_type = 'Listing Row - Overflow Menu'   THEN 1 ELSE 0 END) AS overflow_menu_clicks,
    SUM(CASE WHEN event_type = 'Listing Row - Save Update'     THEN 1 ELSE 0 END) AS save_update_clicks,
    SUM(CASE WHEN event_type = 'Listing Row - Close Edit'      THEN 1 ELSE 0 END) AS close_edit_clicks,
    SUM(CASE WHEN event_type = 'Listing - Duplicate'           THEN 1 ELSE 0 END) AS duplicate_clicks
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')
ORDER BY day_period DESC;
*/


-- ================================================================
-- SECTION 8 — COMPLETION TIME  (Master Grain + Filter)
--
--   Source: COMPLETION_TIME_FINAL_T (dim columns already joined in)
--
--   ⚠ PERCENTILE_APPROX cannot be re-aggregated across rows.
--     This query computes percentiles AT daily grain per filter combo.
--     For Weekly: run with date range = rtl_week_beg_dt to rtl_week_end_dt
--     For Monthly MTD: add WHERE DATE_FORMAT(dt,'yyyy-MM') = DATE_FORMAT(CURRENT_DATE(),'yyyy-MM')
--     For Overall: remove date filter
-- ================================================================

-- 8A. Event Completion Time — daily grain + filter dims
SELECT
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM')                                 AS month_period,
    ctf.metric_name,
    COALESCE(ctf.geography,         'Unknown')                      AS geography,
    COALESCE(ctf.launch_phase,      'Unknown')                      AS launch_phase,
    COALESCE(ctf.category,          'Unknown')                      AS category,
    COALESCE(ctf.gmv_tier,          'Unknown')                      AS gmv_tier,
    COALESCE(ctf.onboarding_method, 'Unknown')                      AS onboarding_method,
    COALESCE(ctf.seller_background, 'Unknown')                      AS seller_background,
    COUNT(*)                                                        AS total_rows,
    COUNT(ctf.diff_in_minutes)                                      AS matched_rows,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.50, 10000)             AS p50_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.75, 10000)             AS p75_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.90, 10000)             AS p90_minutes,
    ROUND(AVG(ctf.diff_in_minutes), 2)                              AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ctf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE ctf.metric_name     = 'Event Completion Time'
    AND ctf.diff_in_minutes IS NOT NULL
  AND ctf.diff_in_minutes >= 0
GROUP BY
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM'),
    ctf.metric_name,
    COALESCE(ctf.geography,         'Unknown'),
    COALESCE(ctf.launch_phase,      'Unknown'),
    COALESCE(ctf.category,          'Unknown'),
    COALESCE(ctf.gmv_tier,          'Unknown'),
    COALESCE(ctf.onboarding_method, 'Unknown'),
    COALESCE(ctf.seller_background, 'Unknown')
ORDER BY day_period DESC, ctf.metric_name;


-- 8B. Listing Completion Time — express vs non-express split + filter dims
SELECT
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM')                                 AS month_period,
    ctf.is_express,
    COALESCE(ctf.geography,         'Unknown')                      AS geography,
    COALESCE(ctf.launch_phase,      'Unknown')                      AS launch_phase,
    COALESCE(ctf.category,          'Unknown')                      AS category,
    COALESCE(ctf.gmv_tier,          'Unknown')                      AS gmv_tier,
    COALESCE(ctf.onboarding_method, 'Unknown')                      AS onboarding_method,
    COALESCE(ctf.seller_background, 'Unknown')                      AS seller_background,
    COUNT(*)                                                        AS listing_count,
    COUNT(ctf.diff_in_minutes)                                      AS matched_count,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.50, 10000)             AS p50_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.75, 10000)             AS p75_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.90, 10000)             AS p90_minutes,
    ROUND(AVG(ctf.diff_in_minutes), 2)                              AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ctf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE ctf.metric_name     = 'Express Listing Completion Time'
  AND ctf.diff_in_minutes IS NOT NULL
  AND ctf.diff_in_minutes >= 0
GROUP BY
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM'),
    ctf.is_express,
    COALESCE(ctf.geography,         'Unknown'),
    COALESCE(ctf.launch_phase,      'Unknown'),
    COALESCE(ctf.category,          'Unknown'),
    COALESCE(ctf.gmv_tier,          'Unknown'),
    COALESCE(ctf.onboarding_method, 'Unknown'),
    COALESCE(ctf.seller_background, 'Unknown')
ORDER BY day_period DESC, ctf.is_express;


-- 8C. CTA-to-publish match rate — data quality check
SELECT
    metric_name,
    DATE_FORMAT(dt, 'yyyy-MM')                                      AS month_period,
    COUNT(*)                                                         AS total,
    COUNT(last_cta_ts)                                               AS matched,
    ROUND(COUNT(last_cta_ts) * 100.0 / NULLIF(COUNT(*), 0), 1)      AS match_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE dt >= DATE_SUB(CURRENT_DATE(), 30)
GROUP BY metric_name, DATE_FORMAT(dt, 'yyyy-MM');


/*
-- ================================================================
-- SECTION 9 — NAVIGATION FUNNEL  (Grain + Filter where possible)
--   ⚠ Not wired to KPI tiles. Commented out for dashboard build.
-- ================================================================

-- 9A. Entry-to-CTA conversion rate (grain + filter via user_id)
WITH studio_entries AS (
    SELECT session_start_dt, user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
    WHERE event_type = 'Live Studio - Entry (Seller Hub)'
),
cta_clicks AS (
    SELECT DISTINCT session_start_dt, user_id AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
)
SELECT
    DATE_FORMAT(se.session_start_dt, 'yyyy-MM-dd')                AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(se.session_start_dt, 'yyyy-MM')                   AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT se.seller_id)                                   AS studio_entry_sellers,
    COUNT(DISTINCT cc.seller_id)                                   AS cta_click_sellers
FROM studio_entries se
LEFT JOIN cta_clicks cc
    ON  se.seller_id = cc.seller_id AND se.session_start_dt = cc.session_start_dt
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(se.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  se.session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(se.session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(se.session_start_dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;

-- 9B. Events Page impression → CTA rate (grain + filter)
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
    DATE_FORMAT(ep.session_start_dt, 'yyyy-MM-dd')                AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ep.session_start_dt, 'yyyy-MM')                   AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT ep.seller_id)                                   AS page_viewers,
    COUNT(DISTINCT cc.seller_id)                                   AS cta_click_sellers
FROM events_page_views ep
LEFT JOIN cta_clicks cc
    ON  ep.seller_id = cc.seller_id AND ep.session_start_dt = cc.session_start_dt
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(ep.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ep.session_start_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(ep.session_start_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ep.session_start_dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;
*/


-- ================================================================
-- SECTION 10 — SUMMARY SCORECARD  (Grain + Filter — all metrics)
--
--   Single wide query for the KPI tile row.
--   Parameterize date range based on grain:
--     Overall : remove date filters below (show all available data)
--     Daily   : WHERE dt = DATE_SUB(CURRENT_DATE(), 1)
--     Weekly  : WHERE dt BETWEEN <rtl_week_beg_dt> AND <rtl_week_end_dt>
--               (fetch current week from dw_cal_rtl_week where age_for_rtl_week_id = 0)
--     Monthly : WHERE DATE_FORMAT(dt,'yyyy-MM') = DATE_FORMAT(CURRENT_DATE(),'yyyy-MM')
-- ================================================================

-- 10A. Fetch current and last complete retail week dates
--      (use output to parameterize §10B)
SELECT
    rtl_week_beg_dt,
    rtl_week_end_dt,
    rtl_week_name,
    age_for_rtl_week_id
FROM access_views.dw_cal_rtl_week
WHERE age_for_rtl_week_id IN (0, -1)
ORDER BY age_for_rtl_week_id DESC;


-- 10B. Grain-parameterized scorecard
--   Replace ${start_dt} and ${end_dt} based on output of §10A or chosen grain.
--   For Overall: remove the date WHERE clauses entirely.
--   Sources:
--     Funnel  : LIVE_SELLER_MASTER_V2 (setup) + SELLER_FIRST_SHOW_FUNNEL (steps 1–4)
--     Rate    : COMPLETION_RATE_FINAL_T  (dim already joined, no re-join needed)
--     Adoption: LISTING_ADOPTION_T       (dim already joined, no re-join needed)
WITH event_completion AS (
    SELECT
        COALESCE(crf.geography,         'Unknown')                  AS geography,
        COALESCE(crf.launch_phase,      'Unknown')                  AS launch_phase,
        COALESCE(crf.category,          'Unknown')                  AS category,
        COALESCE(crf.gmv_tier,          'Unknown')                  AS gmv_tier,
        COALESCE(crf.onboarding_method, 'Unknown')                  AS onboarding_method,
        COALESCE(crf.seller_background, 'Unknown')                  AS seller_background,
        SUM(crf.numerator)                                          AS published_events,
        SUM(crf.denominator)                                        AS cta_clicks
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
    WHERE crf.metric_name = 'Event Completion Rate'
      AND crf.dt BETWEEN '${start_dt}' AND '${end_dt}'
    GROUP BY
        COALESCE(crf.geography,         'Unknown'),
        COALESCE(crf.launch_phase,      'Unknown'),
        COALESCE(crf.category,          'Unknown'),
        COALESCE(crf.gmv_tier,          'Unknown'),
        COALESCE(crf.onboarding_method, 'Unknown'),
        COALESCE(crf.seller_background, 'Unknown')
),
listing_adoption AS (
    SELECT
        COALESCE(la.geography,         'Unknown')                   AS geography,
        COALESCE(la.launch_phase,      'Unknown')                   AS launch_phase,
        COALESCE(la.category,          'Unknown')                   AS category,
        COALESCE(la.gmv_tier,          'Unknown')                   AS gmv_tier,
        COALESCE(la.onboarding_method, 'Unknown')                   AS onboarding_method,
        COALESCE(la.seller_background, 'Unknown')                   AS seller_background,
        SUM(la.total_listings)                                      AS total_listings,
        SUM(la.express_listings)                                    AS express_listings
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
    WHERE la.dt BETWEEN '${start_dt}' AND '${end_dt}'
    GROUP BY
        COALESCE(la.geography,         'Unknown'),
        COALESCE(la.launch_phase,      'Unknown'),
        COALESCE(la.category,          'Unknown'),
        COALESCE(la.gmv_tier,          'Unknown'),
        COALESCE(la.onboarding_method, 'Unknown'),
        COALESCE(la.seller_background, 'Unknown')
),
setup_funnel AS (
    SELECT
        COALESCE(d.geography,         'Unknown')                    AS geography,
        COALESCE(d.launch_phase,      'Unknown')                    AS launch_phase,
        COALESCE(d.category,          'Unknown')                    AS category,
        COALESCE(d.gmv_tier,          'Unknown')                    AS gmv_tier,
        COALESCE(d.onboarding_method, 'Unknown')                    AS onboarding_method,
        COALESCE(d.seller_background, 'Unknown')                    AS seller_background,
        COUNT(DISTINCT sb.sellerid)                                 AS setup_started,
        COUNT(DISTINCT f.sellerid)                                  AS event_created,
        COUNT(DISTINCT CASE WHEN f.published_event_with_listing_created = 1
                            THEN f.sellerid END)                    AS listing_ready,
        COUNT(DISTINCT CASE WHEN f.published_event_with_listing_created = 1
                            THEN f.sellerid END)                    AS first_show_ready,
        COUNT(DISTINCT CASE WHEN f.streamed_within_14d_of_studio_activation = 1
                            THEN f.sellerid END)                    AS streamed_14d
    FROM (
        SELECT
            user_id_ubi                                            AS sellerid,
            CAST(studio_activated_ts AS DATE)                      AS activated_dt
        FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
        WHERE report_dt    = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
          AND is_test_user = 0
          AND activated_studio    = 1
          AND studio_activated_ts IS NOT NULL
          AND CAST(studio_activated_ts AS DATE) BETWEEN '${start_dt}' AND '${end_dt}'
    ) sb
    LEFT JOIN P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL f
        ON  sb.sellerid = f.sellerid
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON  CAST(sb.sellerid AS STRING) = d.seller_id
    GROUP BY
        COALESCE(d.geography,         'Unknown'),
        COALESCE(d.launch_phase,      'Unknown'),
        COALESCE(d.category,          'Unknown'),
        COALESCE(d.gmv_tier,          'Unknown'),
        COALESCE(d.onboarding_method, 'Unknown'),
        COALESCE(d.seller_background, 'Unknown')
)
SELECT
    sf.geography,
    sf.launch_phase,
    sf.category,
    sf.gmv_tier,
    sf.onboarding_method,
    sf.seller_background,
    -- L0 North Star
    sf.setup_started,
    sf.first_show_ready,
    ROUND(sf.first_show_ready  * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS seller_setup_success_rate_pct,
    -- P0 Funnel steps
    ROUND(sf.event_created     * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS event_creation_rate_pct,
    ROUND(sf.listing_ready     * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS listing_readiness_rate_pct,
    ROUND(sf.first_show_ready  * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS first_show_ready_rate_pct,
    ROUND(sf.streamed_14d      * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS fourteen_day_first_show_rate_pct,
    -- Event quality
    ROUND(ec.published_events  * 100.0 / NULLIF(ec.cta_clicks, 0), 1)               AS event_completion_rate_pct,
    ROUND((1.0 - ec.published_events * 1.0 / NULLIF(ec.cta_clicks, 0)) * 100.0, 1) AS event_abandonment_rate_pct,
    -- Listing adoption
    ROUND(la.express_listings  * 100.0 / NULLIF(la.total_listings, 0), 1)           AS express_listing_adoption_pct,
    la.total_listings,
    la.express_listings,
    ec.cta_clicks,
    ec.published_events
FROM setup_funnel sf
LEFT JOIN event_completion ec
    ON  sf.geography         = ec.geography
    AND sf.launch_phase      = ec.launch_phase
    AND sf.category          = ec.category
    AND sf.gmv_tier          = ec.gmv_tier
    AND sf.onboarding_method = ec.onboarding_method
    AND sf.seller_background = ec.seller_background
LEFT JOIN listing_adoption la
    ON  sf.geography         = la.geography
    AND sf.launch_phase      = la.launch_phase
    AND sf.category          = la.category
    AND sf.gmv_tier          = la.gmv_tier
    AND sf.onboarding_method = la.onboarding_method
    AND sf.seller_background = la.seller_background
ORDER BY sf.geography, sf.launch_phase, sf.category, sf.gmv_tier,
    sf.onboarding_method, sf.seller_background;


-- ================================================================
-- NOTES
--
-- 1. SECTION 1 — Event Published / Event Creation
--    Direct read from COMPLETION_RATE_FINAL_T (metric_name = 'Event Completion Rate').
--    denominator = CTA clicks, numerator = published events.
--    Grain date is activity date (dt), same as Section 3.
--
-- 2. SETUP BASE (Sections 2, 10B)
--    Grain date is studio_activated_ts from LIVE_SELLER_MASTER_V2.
--    Only sellers with activated_studio = 1 AND non-null
--    studio_activated_ts are included.  SELLER_FIRST_SHOW_FUNNEL
--    is an all-time table — no rolling-window deflation.
--
-- 3. STEP 4 — 14-Day First Show
--    Uses streamed_within_14d_of_studio_activation from
--    SELLER_FIRST_SHOW_FUNNEL — anchored to studio_activated_ts,
--    not to the first CTA click.
--
-- 4. SECTIONS WITH NO SELLER DIM FILTER
--    Section 3B: EVENT_CREATION_BASE_PT — grain only.
--
-- 5. COMPLETION TIME PERCENTILES
--    PERCENTILE_APPROX output cannot be re-aggregated.
--    Sections 8A/8B compute at daily grain per filter combo.
--    For Weekly/Monthly views: re-run with date range = full week/month.
--
-- 6. MONTHLY = MTD
--    Filter: WHERE DATE_FORMAT(dt, 'yyyy-MM') = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM')
--    This includes all data from the 1st of the month through today.
--
-- 7. RETAIL WEEK JOIN
--    access_views.dw_cal_rtl_week — confirmed available in Hermes.
--    age_for_rtl_week_id = 0  → current (in-flight) week
--    age_for_rtl_week_id = -1 → last complete retail week
-- ================================================================
