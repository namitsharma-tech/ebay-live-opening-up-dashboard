-- ================================================================
-- PRE-STREAM TAB — GRAIN & FILTER AWARE SQL
-- Dashboard: eBay Live Opening Up — Pre-Stream Tab
-- Repo: github.corp.ebay.com/eBay-Live-DS/ebay-live-opening-up-dashboard
--
-- GRAIN TOGGLE: Overall | Daily | Weekly (retail) | Monthly (MTD)
-- FILTER DIMS:  geography | launch_phase | category | gmv_tier
--
-- HOW MASTER QUERIES WORK
--   Each master query returns one row per:
--     (day_period, rtl_week_beg_dt, rtl_week_end_dt, month_period,
--      geography, launch_phase, category, gmv_tier)
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
--     WHERE geography = 'US' AND launch_phase = 'Wave 1' ...  (omit for All)
--
--   Rate computation: ROUND(SUM(numerator)*100.0/NULLIF(SUM(denominator),0),1)
--
-- SOURCE TABLES
--   A   P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
--   B   P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT   [no seller_id — grain only]
--   C   P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
--   D   P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
--   E   P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
--   F   P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
--   G   P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T
--   DIM P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM
--   CAL access_views.dw_cal_rtl_week
-- ================================================================


-- ================================================================
-- SECTION 1 — SELLER SETUP SUCCESS RATE  (Master Grain + Filter)
--
--   Grain date = seller's first CTA click date (cohort-based)
--   Numerator  = sellers with published event AND ≥1 listing
--   Denominator = sellers who clicked Create Event CTA
--
--   ⚠ Cohort metric: recent cohorts show artificially low rates
--     because they haven't had enough time to complete setup.
--     Use Weekly or Monthly grain to see mature cohorts.
-- ================================================================

WITH first_cta AS (
    SELECT
        user_id                                                    AS seller_id,
        MIN(session_start_dt)                                      AS first_cta_dt
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY user_id
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
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM-dd')                    AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM')                       AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT fc.seller_id)                                   AS setup_started,
    COUNT(DISTINCT ss.seller_id)                                   AS setup_success
FROM first_cta fc
LEFT JOIN setup_success ss
    ON  fc.seller_id = ss.seller_id
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(fc.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  fc.first_cta_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- ================================================================
-- SECTION 2 — P0 FULL FUNNEL  (Master Grain + Filter)
--
--   All 5 steps: Setup Started → Event Created → Listing Ready
--                → First Show Ready → 14-Day First Show
--   Grain date = seller's first CTA click date (cohort-based)
--   Each step is a count of distinct sellers — compute step rates
--   in the dashboard as step_N / step0_setup_started.
-- ================================================================

WITH first_cta AS (
    SELECT
        user_id                                                    AS seller_id,
        MIN(session_start_dt)                                      AS first_cta_dt
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
first_stream AS (
    SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
)
SELECT
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM-dd')                    AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM')                       AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT fc.seller_id)                                   AS step0_setup_started,
    COUNT(DISTINCT pe.seller_id)                                   AS step1_event_created,
    COUNT(DISTINCT ls.seller_id)                                   AS step2_listing_ready,
    COUNT(DISTINCT CASE
        WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL
        THEN fc.seller_id END)                                     AS step3_first_show_ready,
    COUNT(DISTINCT CASE
        WHEN fsd.first_stream_dt >= fc.first_cta_dt
          AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
        THEN fc.seller_id END)                                     AS step4_14d_first_show
FROM first_cta fc
LEFT JOIN published_sellers  pe  ON fc.seller_id = pe.seller_id
LEFT JOIN listing_sellers    ls  ON fc.seller_id = ls.seller_id
LEFT JOIN first_stream       fsd ON fc.seller_id = fsd.seller_id
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON CAST(fc.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON fc.first_cta_dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(fc.first_cta_dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- ================================================================
-- SECTION 3 — EVENT COMPLETION QUALITY  (Master Grain + Filter)
--
--   Metric: Event Completion Rate = published events / CTA clicks
--   Grain date = activity date (dt) from COMPLETION_RATE_FINAL_T
--   Seller dims joined from LIVE_SELLER_UNIFIED_ONBOARDING_DIM.
-- ================================================================

SELECT
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd')                             AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM')                                AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    SUM(crf.numerator)                                             AS published_events,
    SUM(crf.denominator)                                           AS cta_clicks
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(crf.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  crf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE crf.metric_name = 'Event Completion Rate'
GROUP BY
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- 3B. CTA click entry point breakdown by grain (diagnostic)
--     No seller_id join possible — grain only.
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(session_start_dt, 'yyyy-MM')                      AS month_period,
    event_type,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS event_count,
    COUNT(DISTINCT user_id)                                        AS unique_sellers
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
SELECT
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd')                             AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM')                                AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    SUM(crf.numerator)                                             AS completed_listings,
    SUM(crf.denominator)                                           AS started_listings
FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(crf.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  crf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE crf.metric_name = 'Express Listing Completion Rate'
GROUP BY
    DATE_FORMAT(crf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(crf.dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- 4B. Express Listing Adoption
SELECT
    DATE_FORMAT(la.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM')                                 AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    SUM(la.total_listings)                                         AS total_listings,
    SUM(la.express_listings)                                       AS express_listings,
    SUM(la.case_break_listings)                                    AS case_break_listings
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(la.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  la.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(la.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- 4C. Avg listings per event by grain (diagnostic)
SELECT
    DATE_FORMAT(la.dt, 'yyyy-MM-dd')                              AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM')                                 AS month_period,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(DISTINCT la.event_id)                                    AS event_count,
    SUM(la.total_listings)                                         AS total_listings,
    SUM(la.express_listings)                                       AS express_listings
FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(la.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  la.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
GROUP BY
    DATE_FORMAT(la.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(la.dt, 'yyyy-MM'),
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC;


-- 4D. Import modal path breakdown (grain only — no seller_id in source)
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


-- ================================================================
-- SECTION 5 — RECOMMENDATION QUALITY  (Grain Only)
--
--   ⚠ EXPRESS_LISTINGS_BASE_PT has no seller_id.
--   Filter dimensions (geography / launch_phase / category / gmv_tier)
--   are NOT available for this section.
--   Grain toggle applies; filter toggles will show All only.
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


-- ================================================================
-- SECTION 6 — ERROR GUARDRAILS  (Master Grain + Filter)
--
--   Event Error Rate = error events / total events
--   user_id from EVENT_CREATION_BASE_PT = seller_id → dim join available
-- ================================================================

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


-- 6B. Error code distribution — identify top error types (diagnostic)
SELECT
    DATE_FORMAT(session_start_dt, 'yyyy-MM-dd')                   AS day_period,
    error_code,
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM) AS error_event_count,
    COUNT(DISTINCT user_id)                                        AS unique_sellers_affected
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE error_code IS NOT NULL AND error_code != ''
GROUP BY DATE_FORMAT(session_start_dt, 'yyyy-MM-dd'), error_code
ORDER BY day_period DESC, error_event_count DESC;


-- ================================================================
-- SECTION 7 — P1 DIAGNOSTICS
--   Draft Save Rate, Updates Before Publish, Listing Row Edit behavior
--   Kept as diagnostic queries; not wired to grain toggle KPI tiles.
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


-- ================================================================
-- SECTION 8 — COMPLETION TIME  (Master Grain + Filter)
--
--   Event Completion Time:   CTA click → event publish
--   Listing Completion Time: CTA click → listing created
--
--   ⚠ PERCENTILE_APPROX cannot be re-aggregated across rows.
--     This query computes percentiles AT daily grain per filter combo.
--     For Weekly: run with date range = rtl_week_beg_dt to rtl_week_end_dt
--     For Monthly MTD: add WHERE DATE_FORMAT(dt,'yyyy-MM') = DATE_FORMAT(CURRENT_DATE(),'yyyy-MM')
--     For Overall: remove date filter
--
--   ⚠ Verify COMPLETION_TIME_FINAL_T has a seller_id column before
--     running. If absent, remove the DIM join and filter dims will be unavailable.
-- ================================================================

-- 8A. Event Completion Time — daily grain + filter dims
SELECT
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd')                             AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM')                                AS month_period,
    ctf.metric_name,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(*)                                                       AS total_rows,
    COUNT(ctf.diff_in_minutes)                                     AS matched_rows,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.50, 10000)            AS p50_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.75, 10000)            AS p75_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.90, 10000)            AS p90_minutes,
    ROUND(AVG(ctf.diff_in_minutes), 2)                             AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(ctf.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ctf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE ctf.diff_in_minutes IS NOT NULL
  AND ctf.diff_in_minutes >= 0
GROUP BY
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM'),
    ctf.metric_name,
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC, ctf.metric_name;


-- 8B. Listing Completion Time — express vs non-express split + filter dims
SELECT
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd')                             AS day_period,
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM')                                AS month_period,
    ctf.is_express,
    COALESCE(d.geography,    'Unknown')                            AS geography,
    COALESCE(d.launch_phase, 'Unknown')                            AS launch_phase,
    COALESCE(d.category,     'Unknown')                            AS category,
    COALESCE(d.gmv_tier,     'Unknown')                            AS gmv_tier,
    COUNT(*)                                                       AS listing_count,
    COUNT(ctf.diff_in_minutes)                                     AS matched_count,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.50, 10000)            AS p50_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.75, 10000)            AS p75_minutes,
    PERCENTILE_APPROX(ctf.diff_in_minutes, 0.90, 10000)            AS p90_minutes,
    ROUND(AVG(ctf.diff_in_minutes), 2)                             AS avg_minutes
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T ctf
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(ctf.seller_id AS STRING) = d.seller_id
LEFT JOIN access_views.dw_cal_rtl_week rw
    ON  ctf.dt BETWEEN rw.rtl_week_beg_dt AND rw.rtl_week_end_dt
WHERE ctf.metric_name = 'Express Listing Completion Time'
  AND ctf.diff_in_minutes IS NOT NULL
  AND ctf.diff_in_minutes >= 0
GROUP BY
    DATE_FORMAT(ctf.dt, 'yyyy-MM-dd'),
    rw.rtl_week_beg_dt,
    rw.rtl_week_end_dt,
    DATE_FORMAT(ctf.dt, 'yyyy-MM'),
    ctf.is_express,
    COALESCE(d.geography, 'Unknown'),
    COALESCE(d.launch_phase, 'Unknown'),
    COALESCE(d.category, 'Unknown'),
    COALESCE(d.gmv_tier, 'Unknown')
ORDER BY day_period DESC, ctf.is_express;


-- 8C. CTA-to-publish match rate — data quality check
SELECT
    metric_name,
    DATE_FORMAT(dt, 'yyyy-MM')                                     AS month_period,
    COUNT(*)                                                        AS total,
    COUNT(last_cta_ts)                                              AS matched,
    ROUND(COUNT(last_cta_ts) * 100.0 / NULLIF(COUNT(*), 0), 1)     AS match_rate_pct
FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
WHERE dt >= DATE_SUB(CURRENT_DATE(), 30)
GROUP BY metric_name, DATE_FORMAT(dt, 'yyyy-MM');


-- ================================================================
-- SECTION 9 — NAVIGATION FUNNEL  (Grain + Filter where possible)
-- ================================================================

-- 9A. Entry-to-CTA conversion rate (grain + filter via user_id)
WITH studio_entries AS (
    SELECT
        session_start_dt,
        user_id                                                    AS seller_id
    FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
    WHERE event_type = 'Live Studio - Entry (Seller Hub)'
),
cta_clicks AS (
    SELECT DISTINCT
        session_start_dt,
        user_id                                                    AS seller_id
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
    ON  se.seller_id = cc.seller_id
    AND se.session_start_dt = cc.session_start_dt
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
    ON  ep.seller_id = cc.seller_id
    AND ep.session_start_dt = cc.session_start_dt
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

-- 10A. Fetch current and last complete retail week dates (use output to parameterize §10B)
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
WITH event_completion AS (
    SELECT
        COALESCE(d.geography,    'Unknown')                        AS geography,
        COALESCE(d.launch_phase, 'Unknown')                        AS launch_phase,
        COALESCE(d.category,     'Unknown')                        AS category,
        COALESCE(d.gmv_tier,     'Unknown')                        AS gmv_tier,
        SUM(crf.numerator)                                         AS published_events,
        SUM(crf.denominator)                                       AS cta_clicks
    FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T crf
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(crf.seller_id AS STRING) = d.seller_id
    WHERE crf.metric_name = 'Event Completion Rate'
      AND crf.dt BETWEEN '${start_dt}' AND '${end_dt}'
    GROUP BY
        COALESCE(d.geography, 'Unknown'),
        COALESCE(d.launch_phase, 'Unknown'),
        COALESCE(d.category, 'Unknown'),
        COALESCE(d.gmv_tier, 'Unknown')
),
listing_adoption AS (
    SELECT
        COALESCE(d.geography,    'Unknown')                        AS geography,
        COALESCE(d.launch_phase, 'Unknown')                        AS launch_phase,
        COALESCE(d.category,     'Unknown')                        AS category,
        COALESCE(d.gmv_tier,     'Unknown')                        AS gmv_tier,
        SUM(la.total_listings)                                     AS total_listings,
        SUM(la.express_listings)                                   AS express_listings
    FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T la
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(la.seller_id AS STRING) = d.seller_id
    WHERE la.dt BETWEEN '${start_dt}' AND '${end_dt}'
    GROUP BY
        COALESCE(d.geography, 'Unknown'),
        COALESCE(d.launch_phase, 'Unknown'),
        COALESCE(d.category, 'Unknown'),
        COALESCE(d.gmv_tier, 'Unknown')
),
setup_funnel AS (
    SELECT
        COALESCE(d.geography,    'Unknown')                        AS geography,
        COALESCE(d.launch_phase, 'Unknown')                        AS launch_phase,
        COALESCE(d.category,     'Unknown')                        AS category,
        COALESCE(d.gmv_tier,     'Unknown')                        AS gmv_tier,
        COUNT(DISTINCT fc.seller_id)                               AS setup_started,
        COUNT(DISTINCT pe.seller_id)                               AS event_created,
        COUNT(DISTINCT ls.seller_id)                               AS listing_ready,
        COUNT(DISTINCT CASE WHEN pe.seller_id IS NOT NULL AND ls.seller_id IS NOT NULL
                            THEN fc.seller_id END)                 AS first_show_ready,
        COUNT(DISTINCT CASE
            WHEN fsd.first_stream_dt >= fc.first_cta_dt
              AND DATEDIFF(fsd.first_stream_dt, fc.first_cta_dt) <= 14
            THEN fc.seller_id END)                                 AS streamed_14d
    FROM (
        SELECT user_id AS seller_id, MIN(session_start_dt) AS first_cta_dt
        FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
        WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
          AND session_start_dt BETWEEN '${start_dt}' AND '${end_dt}'
        GROUP BY user_id
    ) fc
    LEFT JOIN (SELECT DISTINCT seller_id FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T WHERE published_cnt > 0) pe
        ON fc.seller_id = pe.seller_id
    LEFT JOIN (SELECT DISTINCT seller_id FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T WHERE total_listings > 0) ls
        ON fc.seller_id = ls.seller_id
    LEFT JOIN (
        SELECT slr_id AS seller_id, MIN(cal_dt) AS first_stream_dt
        FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
        WHERE deleted_ind = 0 AND event_duration_min > 0
        GROUP BY slr_id
    ) fsd ON fc.seller_id = fsd.seller_id
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(fc.seller_id AS STRING) = d.seller_id
    GROUP BY
        COALESCE(d.geography, 'Unknown'),
        COALESCE(d.launch_phase, 'Unknown'),
        COALESCE(d.category, 'Unknown'),
        COALESCE(d.gmv_tier, 'Unknown')
)
SELECT
    sf.geography,
    sf.launch_phase,
    sf.category,
    sf.gmv_tier,
    -- L0 North Star
    sf.setup_started,
    sf.first_show_ready,
    ROUND(sf.first_show_ready * 100.0 / NULLIF(sf.setup_started, 0), 1)           AS seller_setup_success_rate_pct,
    -- P0 Funnel steps
    ROUND(sf.event_created   * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS event_creation_rate_pct,
    ROUND(sf.listing_ready   * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS listing_readiness_rate_pct,
    ROUND(sf.first_show_ready * 100.0 / NULLIF(sf.setup_started, 0), 1)           AS first_show_ready_rate_pct,
    ROUND(sf.streamed_14d    * 100.0 / NULLIF(sf.setup_started, 0), 1)            AS fourteen_day_first_show_rate_pct,
    -- Event quality
    ROUND(ec.published_events * 100.0 / NULLIF(ec.cta_clicks, 0), 1)              AS event_completion_rate_pct,
    ROUND((1 - ec.published_events / NULLIF(ec.cta_clicks, 0)) * 100.0, 1)        AS event_abandonment_rate_pct,
    -- Listing adoption
    ROUND(la.express_listings * 100.0 / NULLIF(la.total_listings, 0), 1)          AS express_listing_adoption_pct,
    la.total_listings,
    la.express_listings,
    ec.cta_clicks,
    ec.published_events
FROM setup_funnel sf
LEFT JOIN event_completion ec
    ON  sf.geography    = ec.geography
    AND sf.launch_phase = ec.launch_phase
    AND sf.category     = ec.category
    AND sf.gmv_tier     = ec.gmv_tier
LEFT JOIN listing_adoption la
    ON  sf.geography    = la.geography
    AND sf.launch_phase = la.launch_phase
    AND sf.category     = la.category
    AND sf.gmv_tier     = la.gmv_tier
ORDER BY sf.geography, sf.launch_phase, sf.category, sf.gmv_tier;


-- ================================================================
-- NOTES
--
-- 1. SECTIONS WITH GRAIN BUT NO SELLER DIM FILTER
--    Sections 5, 7C, 7D: EXPRESS_LISTINGS_BASE_PT has no seller_id.
--    Grain toggle applies; filter selectors will show All only.
--
-- 2. COMPLETION TIME PERCENTILES
--    PERCENTILE_APPROX output cannot be re-aggregated.
--    Sections 8A/8B compute at daily grain per filter combo.
--    For Weekly/Monthly views: re-run with date range = full week/month.
--
-- 3. COHORT-BASED METRICS (Sections 1, 2, 10)
--    Grain applies to first_cta_dt (cohort entry date), not activity date.
--    Cohorts < 30 days old may show incomplete funnel rates — expected.
--
-- 4. MONTHLY = MTD
--    Filter: WHERE DATE_FORMAT(dt, 'yyyy-MM') = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM')
--    This includes all data from the 1st of the month through today.
--
-- 5. RETAIL WEEK JOIN
--    access_views.dw_cal_rtl_week — confirmed available in Hermes.
--    age_for_rtl_week_id = 0 → current (in-flight) week
--    age_for_rtl_week_id = -1 → last complete retail week
-- ================================================================
