-- ================================================================
-- REGISTRATION TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: Registration
--
-- Source tables:
--   PRIMARY  P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 (Q1, Q2)
--   SECONDARY USER_FUNNEL × TUV join (Q4) — manual review queue only
--
-- Mandatory filter (ALL queries):
--   WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
--     AND is_test_user = 0
--
-- ⚠ APPROVAL TIME CONFLICT:
--   Data guide confirms approval timing is 0.8–2.1 minutes
--   (fully automated). Dashboard currently shows 1.8 hrs —
--   this is a definition mismatch. Queries below return minutes;
--   divide by 60 only if dashboard label is updated to "hours".
--
-- ⚠ DENOMINATOR NOTE:
--   LPG Rate denominator: Q2 uses cohort_size = account_created.
--   Dashboard shows LPG / submitted (different denominator).
--   Both are computed below — align on one definition before GA.
--
-- Run order: each section is independent.
-- All rates: SUM(numerator) / SUM(denominator) — never AVG of rates.
-- ================================================================


-- ================================================================
-- SECTION 1 — REGISTRATION FUNNEL COUNTS (snapshot)
--   One row showing current state of the full cohort.
--   Grain: seller (user_id) level except account_created (GUID).
-- ================================================================

SELECT
    COUNT(*)                                                          AS total_in_funnel,

    -- Step 1: Account Created
    COUNT(CASE WHEN account_created_ts IS NOT NULL THEN 1 END)        AS n_acct_created,
    ROUND(
        COUNT(CASE WHEN account_created_ts IS NOT NULL THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS acct_creation_rate_pct,

    -- Step 2: Streaming App Submitted
    COUNT(CASE WHEN streaming_app_submitted_ts IS NOT NULL THEN 1 END) AS n_app_submitted,
    ROUND(
        COUNT(CASE WHEN streaming_app_submitted_ts IS NOT NULL THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN account_created_ts IS NOT NULL THEN 1 END), 0), 1)
                                                                      AS streaming_reg_rate_pct,

    -- Step 3: Live Privilege Granted (LPG / studio activated)
    COUNT(CASE WHEN activated_studio = 1 THEN 1 END)                 AS n_lpg_granted,

    -- LPG rate — denominator: submitted (matches dashboard label)
    ROUND(
        COUNT(CASE WHEN activated_studio = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN streaming_app_submitted_ts IS NOT NULL THEN 1 END), 0), 1)
                                                                      AS lpg_rate_vs_submitted_pct,

    -- LPG rate — denominator: cohort_size/account_created (Q2 definition)
    ROUND(
        COUNT(CASE WHEN activated_studio = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN account_created_ts IS NOT NULL THEN 1 END), 0), 1)
                                                                      AS lpg_rate_vs_acct_created_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 2 — MEDIAN APPROVAL TIME (submit → activate)
--   ⚠ Returns MINUTES. Data guide confirms 0.8–2.1 minutes actual.
--   Dashboard shows 1.8 hrs — update label or definition before GA.
-- ================================================================

SELECT
    COUNT(CASE WHEN activated_studio = 1 THEN 1 END)                 AS n_approved,

    -- Median in minutes (actual measurement)
    ROUND(
        PERCENTILE_APPROX(minutes_submitted_to_activated, 0.5), 1)   AS median_approval_minutes,

    -- P90 in minutes
    ROUND(
        PERCENTILE_APPROX(minutes_submitted_to_activated, 0.9), 1)   AS p90_approval_minutes,

    -- Median in hours (for comparison to dashboard's current display)
    ROUND(
        PERCENTILE_APPROX(minutes_submitted_to_activated, 0.5) / 60.0, 2)
                                                                      AS median_approval_hours,

    -- Was denied at first then reapproved
    COUNT(CASE WHEN was_initially_denied = 1 AND activated_studio = 1 THEN 1 END)
                                                                      AS n_initially_denied_then_approved,
    ROUND(
        COUNT(CASE WHEN was_initially_denied = 1 AND activated_studio = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(CASE WHEN activated_studio = 1 THEN 1 END), 0), 1)
                                                                      AS reapproval_rate_pct

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND streaming_app_submitted_ts IS NOT NULL
  AND minutes_submitted_to_activated IS NOT NULL;


-- ================================================================
-- SECTION 3 — PHASE TIMING BREAKDOWN (median + P90 each step)
--   Four sub-steps: Entry→Account, Account→Submitted,
--   Submitted→Activated, Activated→First Show.
--   Useful for velocity targets table on Registration tab.
-- ================================================================

SELECT
    -- Entry → Account Created
    ROUND(PERCENTILE_APPROX(minutes_entry_to_account_created, 0.5), 1)
                                                                      AS med_min_entry_to_acct,
    ROUND(PERCENTILE_APPROX(minutes_entry_to_account_created, 0.9), 1)
                                                                      AS p90_min_entry_to_acct,

    -- Account Created → App Submitted
    ROUND(PERCENTILE_APPROX(minutes_account_created_to_submitted, 0.5) / 60.0, 1)
                                                                      AS med_hrs_acct_to_submitted,
    ROUND(PERCENTILE_APPROX(minutes_account_created_to_submitted, 0.9) / 60.0, 1)
                                                                      AS p90_hrs_acct_to_submitted,

    -- App Submitted → Studio Activated (LPG)
    ROUND(PERCENTILE_APPROX(minutes_submitted_to_activated, 0.5), 1)
                                                                      AS med_min_submitted_to_activated,
    ROUND(PERCENTILE_APPROX(minutes_submitted_to_activated, 0.9), 1)
                                                                      AS p90_min_submitted_to_activated,

    -- Studio Activated → First Show
    ROUND(PERCENTILE_APPROX(minutes_activated_to_first_show, 0.5) / 1440.0, 1)
                                                                      AS med_days_activated_to_first_show,
    ROUND(PERCENTILE_APPROX(minutes_activated_to_first_show, 0.9) / 1440.0, 1)
                                                                      AS p90_days_activated_to_first_show

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0;


-- ================================================================
-- SECTION 4 — MANUAL REVIEW RATE
--   ⚠ PARTIAL — LIVE_SELLER_MASTER_V2 does not have a direct
--   manual_review flag. This requires a secondary join to
--   USER_FUNNEL and TUV tables (Q4 in the data guide).
--   Query below is a placeholder structure.
-- ================================================================

-- TODO: replace with actual Q4 join once table access confirmed.
-- Pattern (not executable without USER_FUNNEL and TUV schemas):
/*
SELECT
    COUNT(DISTINCT uf.seller_id)                                      AS n_apps_submitted,
    COUNT(DISTINCT CASE WHEN tuv.queue_type = 'MANUAL' THEN tuv.seller_id END)
                                                                      AS n_manual_review,
    ROUND(
        COUNT(DISTINCT CASE WHEN tuv.queue_type = 'MANUAL' THEN tuv.seller_id END) * 100.0
        / NULLIF(COUNT(DISTINCT uf.seller_id), 0), 1)                AS manual_review_rate_pct
FROM USER_FUNNEL uf
LEFT JOIN TUV tuv ON uf.seller_id = tuv.seller_id
WHERE uf.program = 'LIVE_OPENING_UP'
  AND uf.step = 'APP_SUBMITTED';
*/
SELECT 'Manual review rate requires USER_FUNNEL × TUV join — source pending' AS data_status;


-- ================================================================
-- SECTION 5 — COHORT TREND (weekly registration funnel rates)
--   For trend charts: group by week of app submission.
-- ================================================================

SELECT
    DATE_FORMAT(streaming_app_submitted_ts, 'yyyy-MM-dd')            AS cohort_week_start,
    COUNT(*)                                                          AS n_submitted,

    -- LPG rate by cohort
    COUNT(CASE WHEN activated_studio = 1 THEN 1 END)                 AS n_lpg_granted,
    ROUND(
        COUNT(CASE WHEN activated_studio = 1 THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0), 1)                                     AS lpg_rate_vs_submitted_pct,

    -- Median approval time for this cohort (minutes)
    ROUND(PERCENTILE_APPROX(minutes_submitted_to_activated, 0.5), 1) AS med_approval_minutes,

    -- Activated → First Show median (days)
    ROUND(PERCENTILE_APPROX(minutes_activated_to_first_show, 0.5) / 1440.0, 1)
                                                                      AS med_days_activated_to_first_show

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
  AND streaming_app_submitted_ts IS NOT NULL
GROUP BY DATE_FORMAT(streaming_app_submitted_ts, 'yyyy-MM-dd')
ORDER BY cohort_week_start;


-- ================================================================
-- SECTION 6 — SELLER SNAPSHOT (seller-level detail for ops)
--   One row per seller with key registration milestones.
--   Used by Seller Success and CRM for proactive outreach.
-- ================================================================

SELECT
    seller_id,
    seller_name,
    seller_category_name,
    account_created_ts,
    streaming_app_submitted_ts,
    activated_studio,
    was_initially_denied,
    ROUND(minutes_submitted_to_activated, 1)                          AS approval_time_min,

    -- Outreach flags
    ok_to_email,
    ok_to_call,

    -- Status label
    CASE
        WHEN activated_studio = 1 THEN 'LPG Granted'
        WHEN streaming_app_submitted_ts IS NOT NULL AND activated_studio = 0
            THEN 'Pending Review'
        WHEN account_created_ts IS NOT NULL AND streaming_app_submitted_ts IS NULL
            THEN 'App Not Submitted'
        ELSE 'Account Not Created'
    END                                                               AS onboarding_status

FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
WHERE report_dt = DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd')
  AND is_test_user = 0
ORDER BY streaming_app_submitted_ts DESC NULLS LAST;
