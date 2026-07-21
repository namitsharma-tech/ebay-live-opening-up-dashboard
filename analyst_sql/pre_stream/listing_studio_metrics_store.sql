-- ================================================================
-- BASE TABLE CREATION
-- Run order: A → B → C, then metrics below
-- ================================================================


-- ================================================================
-- SECTION A — EVENT_CREATION_BASE_PT
--   p4613030.m173118.l191337  — Create Event CTA (page 4613030)
--   p4613031.m173558.l191918  — Save as Draft / Publish (page 4613031)
--                               ⚠ Both CTAs share this SID — cannot split via UBI
--   p4613031.m173560.l191919  — Save as Draft / Publish (secondary; fires on both)
--   p4681902.m182219.l207351  — Create First Event - CTA Click
-- ================================================================
DELETE FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
WHERE dt = DATE_SUB(CURRENT_DATE, 2);

INSERT INTO P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
SELECT
    u.event_timestamp,
    u.session_start_dt,
    u.session_skey,
    u.seqnum,
    u.guid,
    u.site_id,
    u.page_id                                                                    AS original_page_id,
    COALESCE(
        CAST(sojlib.soj_nvl(u.soj, 'callingPageId') AS INT),
        CAST(sojlib.soj_nvl(u.soj, 'cp')            AS INT)
    )                                                                            AS calling_page_id,
    COALESCE(u.user_id, COALESCE(s.signedin_user_id, s.mapped_user_id))         AS user_id,
    sojlib.soj_nvl(u.soj, 'efam')                                               AS event_family,
    sojlib.soj_nvl(u.soj, 'eactn')                                              AS event_action,
    sojlib.soj_nvl(u.soj, 'actn')                                               AS action_kind,
    sojlib.soj_nvl(u.soj, 'sid')                                                AS sid,
    sojlib.soj_nvl(u.soj, 'mi')                                                 AS module_id,
    sojlib.soj_nvl(u.soj, 'onboardingflow')                                     AS onboarding_flow,
    sojlib.soj_nvl(u.soj, 'tags')                                               AS tags,
    sojlib.soj_nvl(u.soj, 'errorcode')                                          AS error_code,
    sojlib.soj_nvl(u.soj, 'eventId')                                            AS eventId,
    u.soj,
    CASE
        WHEN sojlib.soj_nvl(u.soj, 'sid') IN ('p4613030.m173118.l191337') THEN 'Create Event - CTA Click'
        WHEN sojlib.soj_nvl(u.soj, 'sid') IN ('p4681902.m182219.l207351') THEN 'Create First Event - CTA Click'
        WHEN sojlib.soj_nvl(u.soj, 'sid') IN ('p4613031.m173558.l191918') THEN 'Event Form - Save as draft or Publish'
        WHEN sojlib.soj_nvl(u.soj, 'sid') IN ('p4613031.m173560.l191919') THEN 'Event Form - Save or Publish (secondary)'
        ELSE sojlib.soj_nvl(u.soj, 'sid')
    END                                                                          AS event_type,
    u.session_start_dt                                                           AS dt

FROM ubi_v.ubi_event u
INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
    ON  cal.CAL_DT        = u.SESSION_START_DT
    AND cal.AGE_FOR_DT_ID = -2
LEFT JOIN access_views.clav_session_ext s
    ON  u.guid             = s.guid
    AND u.session_skey     = s.session_skey
    AND u.session_start_dt = s.session_start_dt
    AND u.site_id          = s.site_id
    AND s.exclude          = 0
    AND s.cobrand          IN (0, 6, 7)
WHERE 1=1
  AND u.site_id = 0
  AND sojlib.soj_nvl(u.soj, 'sid') IN (
        'p4613030.m173118.l191337',
        'p4613031.m173558.l191918',
        'p4613031.m173560.l191919',
        'p4681902.m182219.l207351'
      )
  AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN';

SELECT
    event_type,
    original_page_id,
    calling_page_id,
    sid,
    module_id,
    onboarding_flow,
    count(*),
    count(distinct guid),
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)
FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
GROUP BY ALL;


-- ================================================================
-- SECTION B — EXPRESS_LISTINGS_BASE_PT
-- Scope: Create Listings CTA + modal, Import Listings CTA + modal,
--        Template flow, Edit flow, Duplicate, Draft Update
-- Page:  4613028 (Live Studio — Express Listings tab)
--
-- Validated SIDs:
--   p4613028.m176279.l207386  — Create Listings CTA
--   p4613028.m176279.l207388  — Import Listings CTA
--                               ⚠ Also fires as Import Modal - Dismiss (shared SID)
--   p4613028.m183399.l207369  — Create Modal - Edit
--   p4613028.m183399.l207390  — Create Modal - Shipping Policy
--   p4613028.m183399.l207370  — Create Modal - Category
--   p4613028.m183399.l207371  — Create Modal - Create Listings (KEY conversion)
--   p4613028.m183399.l9480    — Create Modal - Dismiss
--   p4613028.m173118.l196291  — Import Modal - From Template
--   p4613028.m173118.l196290  — Import Modal - From Store
--   p4613028.m173118.l196289  — Import Modal - Item ID / URL
--   p4613028.m173118.l196296  — Import Modal - Add Listings (KEY conversion)
--   p4613028.m173118.l196294  — Import Modal - Template Selected
--   p4613028.m176279.l196292  — Create Listings - Create (from Template)
--   p4613028.m183281.l206990  — Listing Row - Overflow Menu
--   p4613028.m183281.l206989  — Listing Row - Edit (Pencil)
--   p4613028.m183021.l206672  — Listing Row - Save Update
--   p4613028.m183021.l190072  — Listing Row - Close Edit
--   p4613028.m173119.l161517  — Listing - Duplicate
--   p4613028.m175239.l191959  — Listing - Draft Update
--
-- Modal VIEW impressions: Create modal mi = 2548 (confirmed in Braavos)
-- ================================================================
DELETE FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
WHERE dt = DATE_SUB(CURRENT_DATE, 2);

INSERT INTO P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
SELECT
    u.event_timestamp,
    u.session_start_dt,
    u.session_skey,
    u.seqnum,
    u.guid,
    u.site_id,
    u.page_id                                                               AS original_page_id,
    COALESCE(
        CAST(sojlib.soj_nvl(u.soj, 'callingPageId') AS INT),
        CAST(sojlib.soj_nvl(u.soj, 'cp')            AS INT)
    )                                                                       AS calling_page_id,
    COALESCE(u.user_id, COALESCE(s.signedin_user_id, s.mapped_user_id))    AS user_id,
    sojlib.soj_nvl(u.soj, 'efam')                                          AS event_family,
    sojlib.soj_nvl(u.soj, 'eactn')                                         AS event_action,
    sojlib.soj_nvl(u.soj, 'actn')                                          AS action_kind,
    sojlib.soj_nvl(u.soj, 'sid')                                           AS sid,
    sojlib.soj_nvl(u.soj, 'mi')                                            AS module_id,
    sojlib.soj_nvl(u.soj, 'onboardingflow')                                AS onboarding_flow,
    sojlib.soj_nvl(u.soj, 'filtername')                                    AS filter_name,
    NULL                                                                    AS tags,
    NULL                                                                    AS error_code,
    NULL                                                                    AS eventId,
    u.soj,
    CASE
        -- Create Listings flow — CTA
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m176279.l207386'  AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN' THEN 'Create Listings - CTA Click'
        -- Create Listings flow — Modal impression (VIEW, mi = 2548)
        WHEN sojlib.soj_nvl(u.soj, 'eactn') = 'VIEW'
             AND sojlib.soj_nvl(u.soj, 'mi') = '2548'                                                         THEN 'Create Modal - Impression'
        -- Create Listings flow — Modal interactions
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183399.l207369' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Modal - Edit'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183399.l207390' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Modal - Shipping Policy'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183399.l207370' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Modal - Category'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183399.l207371' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Modal - Create Listings'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183399.l9480'   AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Modal - Dismiss'
        -- Import Listings flow — CTA
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m176279.l207388' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Listings - CTA Click'
        -- Import Listings flow — Modal interactions
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173118.l196291' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Modal - From Template'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173118.l196290' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Modal - From Store'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173118.l196289' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Modal - Item ID / URL'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173118.l196296' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Modal - Add Listings'
        -- Template flow
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173118.l196294' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Import Modal - Template Selected'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m176279.l196292' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Create Listings - Create (from Template)'
        -- Listing row actions (Edit flow)
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183281.l206990' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing Row - Overflow Menu'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183281.l206989' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing Row - Edit (Pencil)'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183021.l206672' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing Row - Save Update'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m183021.l190072' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing Row - Close Edit'
        -- Duplicate and draft update
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m173119.l161517' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing - Duplicate'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4613028.m175239.l191959' AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'  THEN 'Listing - Draft Update'
        ELSE sojlib.soj_nvl(u.soj, 'sid')
    END                                                                     AS event_type,
    u.session_start_dt                                                      AS dt

FROM ubi_v.ubi_event u
INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
    ON  cal.CAL_DT        = u.SESSION_START_DT
    AND cal.AGE_FOR_DT_ID = -2
LEFT JOIN access_views.clav_session_ext s
    ON  u.guid             = s.guid
    AND u.session_skey     = s.session_skey
    AND u.session_start_dt = s.session_start_dt
    AND u.site_id          = s.site_id
    AND s.exclude          = 0
    AND s.cobrand          IN (0, 6, 7)
WHERE 1=1
  AND u.site_id = 0
  AND (
        (
            sojlib.soj_nvl(u.soj, 'sid') IN (
                'p4613028.m176279.l207386',  -- Create Listings CTA
                'p4613028.m176279.l207388',  -- Import Listings CTA / Import Modal Dismiss
                'p4613028.m183399.l207369',  -- Create Modal - Edit
                'p4613028.m183399.l207390',  -- Create Modal - Shipping Policy
                'p4613028.m183399.l207370',  -- Create Modal - Category
                'p4613028.m183399.l207371',  -- Create Modal - Create Listings
                'p4613028.m183399.l9480',    -- Create Modal - Dismiss
                'p4613028.m173118.l196291',  -- Import Modal - From Template
                'p4613028.m173118.l196290',  -- Import Modal - From Store
                'p4613028.m173118.l196289',  -- Import Modal - Item ID / URL
                'p4613028.m173118.l196296',  -- Import Modal - Add Listings
                'p4613028.m173118.l196294',  -- Import Modal - Template Selected
                'p4613028.m176279.l196292',  -- Create Listings - Create (from Template)
                'p4613028.m183281.l206990',  -- Listing Row - Overflow Menu
                'p4613028.m183281.l206989',  -- Listing Row - Edit (Pencil)
                'p4613028.m183021.l206672',  -- Listing Row - Save Update
                'p4613028.m183021.l190072',  -- Listing Row - Close Edit
                'p4613028.m173119.l161517',  -- Listing - Duplicate
                'p4613028.m175239.l191959'   -- Listing - Draft Update
            )
            AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'
        )
        OR
        (sojlib.soj_nvl(u.soj, 'eactn') = 'VIEW' AND sojlib.soj_nvl(u.soj, 'mi') = '2548')
  );

SELECT
    event_type,
    original_page_id,
    calling_page_id,
    sid,
    module_id,
    count(*),
    count(distinct guid),
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)
FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
GROUP BY ALL
ORDER BY count(*) DESC;


-- ================================================================
-- SECTION C — EVENT_FORM_NAV_BASE_PT
-- Captures: Events page VIEW impression (callingPageId=4613030)
--           + Live Studio entry from Seller Hub
--           + side menu nav clicks
-- Impression: eventAction=VIEW, no sid, callingPageId=4613030, page_id=2208336
-- Entry:      p2380676.m4380.l206168, page_id=4613030
-- Side menu:  p4681902.m182219.l205209/208/210/228/089/281/215/288
-- ================================================================
DELETE FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
WHERE dt = DATE_SUB(CURRENT_DATE, 2);

INSERT INTO P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
SELECT
    u.event_timestamp,
    u.session_start_dt,
    u.session_skey,
    u.seqnum,
    u.guid,
    u.site_id,
    u.page_id                                                                    AS original_page_id,
    COALESCE(
        CAST(sojlib.soj_nvl(u.soj, 'callingPageId') AS INT),
        CAST(sojlib.soj_nvl(u.soj, 'cp')            AS INT)
    )                                                                            AS calling_page_id,
    COALESCE(u.user_id, COALESCE(s.signedin_user_id, s.mapped_user_id))         AS user_id,
    sojlib.soj_nvl(u.soj, 'efam')                                               AS event_family,
    sojlib.soj_nvl(u.soj, 'eactn')                                              AS event_action,
    sojlib.soj_nvl(u.soj, 'actn')                                               AS action_kind,
    sojlib.soj_nvl(u.soj, 'sid')                                                AS sid,
    sojlib.soj_nvl(u.soj, 'mi')                                                 AS module_id,
    u.soj,
    CASE
        WHEN sojlib.soj_nvl(u.soj, 'eactn') = 'VIEW'
             AND COALESCE(
                     CAST(sojlib.soj_nvl(u.soj, 'callingPageId') AS INT),
                     CAST(sojlib.soj_nvl(u.soj, 'cp')            AS INT)
                 ) = 4613030
             AND u.page_id = 2208336                                             THEN 'Events Page - Impression'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p2380676.m4380.l206168'
             AND u.page_id = 4613030
             AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'                        THEN 'Live Studio - Entry (Seller Hub)'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l205209'          THEN 'Side Menu - Events'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l205208'          THEN 'Side Menu - Home'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l205210'          THEN 'Side Menu - Insights'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l207228'          THEN 'Side Menu - Shipments'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l207089'          THEN 'Side Menu - Sellers Hub'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l207281'          THEN 'Side Menu - Resource Centre'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l205215'          THEN 'Side Menu - Live Seller Support'
        WHEN sojlib.soj_nvl(u.soj, 'sid') = 'p4681902.m182219.l207288'          THEN 'Side Menu - Settings & Policies'
        ELSE sojlib.soj_nvl(u.soj, 'sid')
    END                                                                          AS event_type,
    u.session_start_dt                                                           AS dt

FROM ubi_v.ubi_event u
INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
    ON  cal.CAL_DT        = u.SESSION_START_DT
    AND cal.AGE_FOR_DT_ID = -2
LEFT JOIN access_views.clav_session_ext s
    ON  u.guid             = s.guid
    AND u.session_skey     = s.session_skey
    AND u.session_start_dt = s.session_start_dt
    AND u.site_id          = s.site_id
    AND s.exclude          = 0
    AND s.cobrand          IN (0, 6, 7)
WHERE 1=1
  AND u.site_id = 0
  AND (
      (
          sojlib.soj_nvl(u.soj, 'eactn') = 'VIEW'
          AND COALESCE(
                  CAST(sojlib.soj_nvl(u.soj, 'callingPageId') AS INT),
                  CAST(sojlib.soj_nvl(u.soj, 'cp')            AS INT)
              ) = 4613030
          AND u.page_id = 2208336
      )
      OR
      (
          sojlib.soj_nvl(u.soj, 'sid') = 'p2380676.m4380.l206168'
          AND sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'
          AND u.page_id = 4613030
      )
      OR
      (
          sojlib.soj_nvl(u.soj, 'eactn') = 'ACTN'
          AND sojlib.soj_nvl(u.soj, 'sid') IN (
              'p4681902.m182219.l205209',  -- Events
              'p4681902.m182219.l205208',  -- Home
              'p4681902.m182219.l205210',  -- Insights
              'p4681902.m182219.l207228',  -- Shipments
              'p4681902.m182219.l207089',  -- Sellers Hub
              'p4681902.m182219.l207281',  -- Resource Centre
              'p4681902.m182219.l205215',  -- Live Seller Support
              'p4681902.m182219.l207288'   -- Settings & Policies
          )
      )
  );

SELECT
    event_type,
    original_page_id,
    calling_page_id,
    sid,
    module_id,
    count(*),
    count(distinct guid),
    COUNT(DISTINCT SESSION_START_DT || GUID || SESSION_SKEY || SEQNUM)
FROM P_LIVE_ANALYTICS_T.EVENT_FORM_NAV_BASE_PT
GROUP BY ALL;


-- ================================================================
-- Creating a Live Event Base   
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.LIVE_EVENT_PUBLISHED_BASE;
CREATE TABLE P_LIVE_ANALYTICS_T.LIVE_EVENT_PUBLISHED_BASE AS
SELECT
    e.creation_time,
    CAST(e.creation_time AS DATE)   AS dt,
    CAST(e.hostids[0] AS BIGINT)            AS seller_id,
    e.eventId
FROM P_LIVE_ANALYTICS_V.LIVE_EVENT e
WHERE e.visibilityState = 'PUBLISHED'
    AND e.flag             = 'PROD'
    AND e.isDeleted        = FALSE;
    
-- ================================================================
-- 1. Event Completion Rate
--    Normal (non-partitioned) table — full refresh on each run.
--    Numerator   : events published (by publication date + seller)
--    Denominator : unique Create Event CTA clicks (by session date + seller)
--    Join: FULL OUTER JOIN on (dt, seller_id).
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T;
CREATE TABLE P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T AS
WITH published AS (
    SELECT
        CAST(e.creation_time AS DATE)   AS dt,
        CAST(e.hostids[0] AS BIGINT)            AS seller_id,
        COUNT(DISTINCT e.eventId)       AS published_cnt
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT e
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  CAST(e.creation_time AS DATE) = cal.CAL_DT
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE e.visibilityState = 'PUBLISHED'
      AND e.flag             = 'PROD'
      AND e.isDeleted        = FALSE
    GROUP BY CAST(e.creation_time AS DATE), CAST(e.hostids[0] AS BIGINT)
),
clicks AS (
    SELECT
        b.session_start_dt              AS dt,
        b.user_id                       AS seller_id,
        COUNT(DISTINCT b.SESSION_START_DT || b.GUID || b.SESSION_SKEY || b.SEQNUM) AS click_cnt
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT b
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  cal.CAL_DT        = b.session_start_dt
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE b.event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
    GROUP BY b.session_start_dt, b.user_id
)
SELECT
    COALESCE(p.dt, c.dt)                AS dt,
    COALESCE(p.seller_id, c.seller_id)  AS seller_id,
    COALESCE(p.published_cnt, 0)        AS published_cnt,
    COALESCE(c.click_cnt, 0)            AS click_cnt
FROM published p
FULL OUTER JOIN clicks c ON p.dt = c.dt AND p.seller_id = c.seller_id;


-- ================================================================
-- 2. Event Completion Time
--    Normal (non-partitioned) table — full refresh on each run.
--    Grain: one row per event.
--    diff_minutes is NULL when no CTA click was found before publication.
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.EVENT_COMPLETION_TIME_T;
CREATE TABLE P_LIVE_ANALYTICS_T.EVENT_COMPLETION_TIME_T AS
WITH event_with_seller AS (
    SELECT DISTINCT
        e.eventId,
        e.creation_time,
        CAST(e.hostids[0] AS BIGINT)            AS seller_id
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT e
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  CAST(e.creation_time AS DATE) = cal.CAL_DT
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE 1=1
      AND e.visibilityState = 'PUBLISHED'
      AND e.flag             = 'PROD'
      AND e.isDeleted        = FALSE
),
cta_clicks AS (
    SELECT user_id, event_timestamp AS cta_ts
    FROM P_LIVE_ANALYTICS_T.EVENT_CREATION_BASE_PT
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  cal.CAL_DT        = session_start_dt
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE event_type IN ('Create Event - CTA Click', 'Create First Event - CTA Click')
),
matched AS (
    SELECT
        e.eventId,
        e.creation_time,
        e.seller_id,
        MAX(c.cta_ts) AS last_cta_ts
    FROM event_with_seller e
    LEFT JOIN cta_clicks c
        ON  c.user_id = e.seller_id
        AND c.cta_ts  < e.creation_time
    GROUP BY e.eventId, e.creation_time, e.seller_id
)
SELECT
    CAST(creation_time AS DATE)   AS dt,
    eventId,
    creation_time,
    last_cta_ts,
    seller_id,
    CASE
        WHEN last_cta_ts IS NULL THEN NULL
        ELSE ROUND((UNIX_TIMESTAMP(creation_time) - UNIX_TIMESTAMP(last_cta_ts)) / 60.0, 2)
    END AS diff_minutes,
    CASE
        WHEN last_cta_ts IS NULL THEN NULL
        ELSE (UNIX_TIMESTAMP(creation_time) - UNIX_TIMESTAMP(last_cta_ts))
    END AS diff_seconds
FROM matched;


-- Run once to create the table:
-- DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.LIVE_STUDIO_METRICS_PT;
-- CREATE TABLE P_LIVE_ANALYTICS_T.LIVE_STUDIO_METRICS_PT (
--     dt             DATE,
--     seller_id      BIGINT,
--     event_id       STRING,
--     metric_name    STRING,
--     numerator      BIGINT,
--     denominator    BIGINT,
--     p50_minutes    DOUBLE,
--     p75_minutes    DOUBLE,
--     p90_minutes    DOUBLE,
--     avg_minutes    DOUBLE
-- ) USING DELTA PARTITIONED BY (dt);




-- ================================================================
-- 3. Express Listing Completion Rate
--    Normal (non-partitioned) table — full refresh on each run.
--    Grain: (dt, seller_id).
--    started_cnt  : unique 'Create Listings - CTA Click' clicks per seller per day
--    completed_cnt: unique 'Create Modal - Create Listings' clicks per seller per day
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_RATE_T;
CREATE TABLE P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_RATE_T AS
WITH flow_started AS (
    SELECT
        b.session_start_dt                                                              AS dt,
        b.user_id                                                                       AS seller_id,
        COUNT(DISTINCT b.SESSION_START_DT || b.GUID || b.SESSION_SKEY || b.SEQNUM)     AS started_cnt
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT b
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  cal.CAL_DT        = b.session_start_dt
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE b.event_type = 'Create Listings - CTA Click'
    GROUP BY b.session_start_dt, b.user_id
),
flow_completed AS (
    SELECT
        b.session_start_dt                                                              AS dt,
        b.user_id                                                                       AS seller_id,
        COUNT(DISTINCT b.SESSION_START_DT || b.GUID || b.SESSION_SKEY || b.SEQNUM)     AS completed_cnt
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT b
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  cal.CAL_DT        = b.session_start_dt
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE b.event_type = 'Create Modal - Create Listings'
    GROUP BY b.session_start_dt, b.user_id
)
SELECT
    COALESCE(s.dt, c.dt)                AS dt,
    COALESCE(s.seller_id, c.seller_id)  AS seller_id,
    COALESCE(s.started_cnt, 0)          AS started_cnt,
    COALESCE(c.completed_cnt, 0)        AS completed_cnt
FROM flow_started s
LEFT JOIN flow_completed c ON s.dt = c.dt AND s.seller_id = c.seller_id;


-- ================================================================
-- 4. Listing Adoption  (Case Break + Express — merged, grain: dt × event_id × seller_id)
--    Normal (non-partitioned) table — full refresh on each run.
--    is_case_break : FC_SUB_NAME from LIVE_COMMERCE_EVENTS
--    is_express    : APP_ID IN (590363, 456309) from SLNG_LSTG_SUPER_FACT
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T;
CREATE TABLE P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T AS
WITH listing_base AS (
    SELECT
        DATE(L.SITE_CREATE_DATE)                                                AS dt,
        CAST(e.eventId AS STRING)                                               AS event_id,
        EB.seller_id                                                            AS seller_id,
        e.ITEMID,
        CASE WHEN e.LIVE_CATEG_LVL3_NAME IN (
            'Trading Cards CCG Case Break',
            'Trading Cards NSTC Case Break',
            'Trading Cards STC Case Breaks',
            'Sports Memorabilia Box & Case Breaks'
        ) THEN 1 ELSE 0 END                                                     AS is_case_break,
        CASE WHEN L.APP_ID IN (590363, 456309) THEN 1 ELSE 0 END               AS is_express
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT_LISTING_CATEGORY e
    INNER JOIN P_LIVE_ANALYTICS_T.LIVE_EVENT_PUBLISHED_BASE AS EB 
        ON e.eventId = EB.eventId
        AND e.isDeleted = FALSE 
    LEFT JOIN PRS_RESTRICTED_V.SLNG_LSTG_SUPER_FACT L
        ON  e.ITEMID = L.ITEM_ID
        AND L.AUCT_END_DT            >= DATE_SUB(CURRENT_DATE, 365)
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  DATE(L.SITE_CREATE_DATE) = cal.CAL_DT
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
),
aggregated AS (
    SELECT
        dt,
        event_id,
        seller_id,
        COUNT(DISTINCT ITEMID)                                                  AS total_listings,
        COUNT(DISTINCT CASE WHEN is_express    = 1 THEN ITEMID END)            AS express_listings,
        COUNT(DISTINCT CASE WHEN is_case_break = 1 THEN ITEMID END)            AS case_break_listings
    FROM listing_base
    GROUP BY dt, event_id, seller_id
)
SELECT
    a.dt,
    a.event_id,
    a.seller_id,
    a.total_listings,
    a.express_listings,
    a.case_break_listings,
    d.onboarding_method,
    d.seller_background,
    d.geography,
    d.category,
    d.expected_gmv_tier,
    d.gmv_tier,
    d.onboarded_flag,
    d.first_event_flag,
    d.seller_tenure,
    d.launch_phase,
    d.lead_source,
    d.seller_support_type
FROM aggregated a
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(a.seller_id AS STRING) = d.seller_id;


-- ================================================================
-- 5. Express Listing Completion Time
--    Normal (non-partitioned) table — full refresh on each run.
--    Grain: one row per listing (event_id × seller_id × lstg_id).
--    listings_created: LIVE_COMMERCE_EVENTS → LIVE_EVENT_LISTING → SLNG_LSTG_SUPER_FACT
--    Note: SLNG_LSTG_SUPER_FACT.SITE_CREATE_DATE — verify if TIMESTAMP or DATE in your schema.
--    diff_in_minutes / diff_in_seconds are NULL when no CTA click preceded the listing.
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_TIME_T;
CREATE TABLE P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_TIME_T AS
WITH listing_base AS (
    SELECT
        e.eventId                                                           AS event_id,
        EB.seller_id                                                        AS seller_id,
        e.ITEMID                                                            AS lstg_id,
        L.SITE_CREATE_DATE                                                  AS creation_time,
        CASE WHEN L.APP_ID IN (590363, 456309) THEN 1 ELSE 0 END           AS is_express
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT_LISTING_CATEGORY e
    INNER JOIN P_LIVE_ANALYTICS_T.LIVE_EVENT_PUBLISHED_BASE AS EB 
        ON e.eventId = EB.eventId
        AND e.isDeleted = FALSE 
    LEFT JOIN PRS_RESTRICTED_V.SLNG_LSTG_SUPER_FACT L
        ON  e.ITEMID = L.ITEM_ID
        AND L.AUCT_END_DT            >= DATE_SUB(CURRENT_DATE, 365)
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  CAST(L.SITE_CREATE_DATE AS DATE) = cal.CAL_DT
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE L.SITE_CREATE_DATE IS NOT NULL
),
cta_clicks AS (
    SELECT user_id, event_timestamp AS cta_ts
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTINGS_BASE_PT
    INNER JOIN ACCESS_VIEWS.DW_CAL_DT cal
        ON  cal.CAL_DT        = session_start_dt
        AND cal.AGE_FOR_RTL_WEEK_ID IN (0, -1)
    WHERE event_type = 'Create Listings - CTA Click'
),
matched AS (
    SELECT
        lb.event_id,
        lb.seller_id,
        lb.lstg_id,
        lb.creation_time,
        lb.is_express,
        MAX(c.cta_ts) AS last_cta_ts
    FROM listing_base lb
    LEFT JOIN cta_clicks c
        ON  c.user_id = lb.seller_id
        AND c.cta_ts  < lb.creation_time
    GROUP BY lb.event_id, lb.seller_id, lb.lstg_id, lb.creation_time, lb.is_express
)
SELECT
    CAST(creation_time AS DATE)                                                             AS dt,
    event_id                                                                                AS eventId,
    creation_time,
    last_cta_ts,
    seller_id,
    lstg_id,
    CASE
        WHEN last_cta_ts IS NULL THEN NULL
        ELSE ROUND((UNIX_TIMESTAMP(creation_time) - UNIX_TIMESTAMP(last_cta_ts)) / 60.0, 2)
    END AS diff_in_minutes,
    CASE
        WHEN last_cta_ts IS NULL THEN NULL
        ELSE (UNIX_TIMESTAMP(creation_time) - UNIX_TIMESTAMP(last_cta_ts))
    END AS diff_in_seconds,
    is_express
FROM matched;


-- ================================================================
-- FINAL TABLE A — COMPLETION_RATE_FINAL_T
--    UNION of Event Completion Rate + Express Listing Completion Rate.
--    Grain: (dt, seller_id, metric_name).
--    Joined with LIVE_SELLER_UNIFIED_ONBOARDING_DIM for seller dimensions.
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T;
CREATE TABLE P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T AS
WITH unioned AS (
    SELECT
        dt,
        seller_id,
        'Event Completion Rate'             AS metric_name,
        published_cnt                       AS numerator,
        click_cnt                           AS denominator
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_RATE_T

    UNION ALL

    SELECT
        dt,
        seller_id,
        'Express Listing Completion Rate'   AS metric_name,
        completed_cnt                       AS numerator,
        started_cnt                         AS denominator
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_RATE_T
)
SELECT
    u.dt,
    u.seller_id,
    u.metric_name,
    u.numerator,
    u.denominator,
    d.onboarding_method,
    d.seller_background,
    d.geography,
    d.category,
    d.expected_gmv_tier,
    d.gmv_tier,
    d.onboarded_flag,
    d.first_event_flag,
    d.seller_tenure,
    d.launch_phase,
    d.lead_source,
    d.seller_support_type
FROM unioned u
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(u.seller_id AS STRING) = d.seller_id;


-- ================================================================
-- FINAL TABLE B — COMPLETION_TIME_FINAL_T
--    UNION of Event Completion Time + Express Listing Completion Time.
--    Grain: one row per event (event side) or per listing (express side).
--    lstg_id and is_express are NULL for the event side.
--    Joined with LIVE_SELLER_UNIFIED_ONBOARDING_DIM for seller dimensions.
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T;
CREATE TABLE P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T AS
WITH unioned AS (
    SELECT
        dt,
        eventId,
        creation_time,
        last_cta_ts,
        seller_id,
        NULL                                AS lstg_id,
        diff_minutes                        AS diff_in_minutes,
        diff_seconds                        AS diff_in_seconds,
        NULL                                AS is_express,
        'Event Completion Time'             AS metric_name
    FROM P_LIVE_ANALYTICS_T.EVENT_COMPLETION_TIME_T

    UNION ALL

    SELECT
        dt,
        eventId,
        creation_time,
        last_cta_ts,
        seller_id,
        lstg_id,
        diff_in_minutes,
        diff_in_seconds,
        is_express,
        'Express Listing Completion Time'   AS metric_name
    FROM P_LIVE_ANALYTICS_T.EXPRESS_LISTING_COMPLETION_TIME_T
)
SELECT
    u.dt,
    u.eventId,
    u.creation_time,
    u.last_cta_ts,
    u.seller_id,
    u.lstg_id,
    u.diff_in_minutes,
    u.diff_in_seconds,
    u.is_express,
    u.metric_name,
    d.onboarding_method,
    d.seller_background,
    d.geography,
    d.category,
    d.expected_gmv_tier,
    d.gmv_tier,
    d.onboarded_flag,
    d.first_event_flag,
    d.seller_tenure,
    d.launch_phase,
    d.lead_source,
    d.seller_support_type
FROM unioned u
LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
    ON  CAST(u.seller_id AS STRING) = d.seller_id;


-- ================================================================
-- FINAL TABLE C — LISTING_ADOPTION_T  (already merged, no UNION needed)
--    Grain: (dt, event_id, seller_id).
--    Columns: total_listings, express_listings, case_break_listings.
-- ================================================================
-- See metric 4 above — LISTING_ADOPTION_T is the final table.


-- ================================================================
-- P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL
--    Grain: Seller ID
--    It shows Seller Setup to first stream funnel
-- ================================================================
DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL;
CREATE TABLE P_LIVE_ANALYTICS_T.SELLER_FIRST_SHOW_FUNNEL AS
WITH live_events_base AS (
    SELECT
        CAST(hostids[0] AS BIGINT)                  AS sellerid,
        eventId,
        creation_time
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT
    WHERE flag      = 'PROD'
      AND isDeleted = FALSE
	  AND dt        >= DATE_SUB(CURRENT_DATE(), 365)
	  AND visibilityState  = 'PUBLISHED'
),
sec4a_event AS (
    SELECT sellerid, MIN(creation_time) AS first_event_created_ts
    FROM live_events_base
    GROUP BY sellerid
),
sec4b_listing AS (
  SELECT
    e.sellerid,
    MIN(L.SITE_CREATE_DATE)              AS first_listing_created_ts
  FROM live_events_base e
  JOIN P_LIVE_ANALYTICS_V.LIVE_EVENT_LISTING elc ON e.eventId = elc.eventId
  JOIN PRS_RESTRICTED_V.SLNG_LSTG_SUPER_FACT L ON  elc.ITEMID = L.ITEM_ID AND L.AUCT_END_DT >= DATE_SUB(CURRENT_DATE, 365)
  WHERE elc.isDeleted = FALSE 
  AND elc.dt  >= DATE_SUB(CURRENT_DATE(), 365)
  GROUP BY e.sellerid
),
first_stream AS (
    SELECT
        slr_id                                      AS sellerid,
        MIN(cal_dt)                                 AS first_stream_dt,
        MIN(STARTTIME)                              AS first_stream_start
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind        = 0
      AND event_duration_min > 0
    GROUP BY slr_id
),
studio_activated AS (
    SELECT
        user_id_ubi                                 AS sellerid,
        activated_studio,
        studio_activated_ts
    FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2
    WHERE report_dt    = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
      AND is_test_user = 0
)
SELECT
    a.sellerid,
    1                                                                               AS published_event_created,
    a.first_event_created_ts                                                        AS first_event_publish_time,
    CASE WHEN b.sellerid IS NOT NULL THEN 1 ELSE 0 END                             AS published_event_with_listing_created,
    b.first_listing_created_ts                                                         AS first_lstg_created_time_in_published_event,
    fs.first_stream_dt,
    CASE
        WHEN fs.first_stream_start IS NOT NULL
         AND sa.studio_activated_ts IS NOT NULL
         AND DATEDIFF(
               CAST(fs.first_stream_start AS DATE),
               CAST(sa.studio_activated_ts AS DATE)
             ) <= 14
        THEN 1 ELSE 0
    END                                                                             AS streamed_within_14d_of_studio_activation
FROM sec4a_event       a
LEFT JOIN sec4b_listing           b  ON a.sellerid = b.sellerid
LEFT JOIN first_stream    fs ON a.sellerid = fs.sellerid
LEFT JOIN studio_activated sa ON a.sellerid = sa.sellerid;

-- ================================================================
-- SAMPLE QUERIES
-- ================================================================

-- ----------------------------------------------------------------
-- A. COMPLETION_RATE_FINAL_T
-- ----------------------------------------------------------------

-- A1. Daily completion rate per metric (sum num/denom — never average rates)
-- SELECT
--     dt,
--     metric_name,
--     SUM(numerator)                                                      AS total_numerator,
--     SUM(denominator)                                                    AS total_denominator,
--     ROUND(SUM(numerator) / NULLIF(SUM(denominator), 0) * 100, 2)       AS rate_pct
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
-- GROUP BY dt, metric_name
-- ORDER BY dt DESC, metric_name;

-- A2. Weekly completion rate (sum across days first, then divide)
-- SELECT
--     DATE_TRUNC('week', dt)                                              AS week_start,
--     metric_name,
--     SUM(numerator)                                                      AS total_numerator,
--     SUM(denominator)                                                    AS total_denominator,
--     ROUND(SUM(numerator) / NULLIF(SUM(denominator), 0) * 100, 2)       AS rate_pct
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
-- GROUP BY DATE_TRUNC('week', dt), metric_name
-- ORDER BY week_start DESC, metric_name;

-- A3. Completion rate by geography and gmv_tier (last 30 days)
-- SELECT
--     metric_name,
--     geography,
--     gmv_tier,
--     SUM(numerator)                                                      AS total_numerator,
--     SUM(denominator)                                                    AS total_denominator,
--     ROUND(SUM(numerator) / NULLIF(SUM(denominator), 0) * 100, 2)       AS rate_pct
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
-- WHERE dt >= DATE_SUB(CURRENT_DATE, 30)
-- GROUP BY metric_name, geography, gmv_tier
-- ORDER BY metric_name, rate_pct DESC;

-- A4. Side-by-side Event vs Express Listing rate per seller_tenure
-- SELECT
--     seller_tenure,
--     ROUND(SUM(CASE WHEN metric_name = 'Event Completion Rate'
--                    THEN numerator END) /
--           NULLIF(SUM(CASE WHEN metric_name = 'Event Completion Rate'
--                           THEN denominator END), 0) * 100, 2)          AS event_completion_rate_pct,
--     ROUND(SUM(CASE WHEN metric_name = 'Express Listing Completion Rate'
--                    THEN numerator END) /
--           NULLIF(SUM(CASE WHEN metric_name = 'Express Listing Completion Rate'
--                           THEN denominator END), 0) * 100, 2)          AS express_completion_rate_pct
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_RATE_FINAL_T
-- WHERE dt >= DATE_SUB(CURRENT_DATE, 30)
-- GROUP BY seller_tenure
-- ORDER BY seller_tenure;


-- ----------------------------------------------------------------
-- B. COMPLETION_TIME_FINAL_T
-- ----------------------------------------------------------------

-- B1. Daily P50 / P75 / P90 completion time per metric (excluding NULLs)
-- SELECT
--     dt,
--     metric_name,
--     COUNT(*)                                                            AS total_rows,
--     COUNT(diff_in_minutes)                                              AS matched_rows,
--     PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                    AS p50_minutes,
--     PERCENTILE_APPROX(diff_in_minutes, 0.75, 10000)                    AS p75_minutes,
--     PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                    AS p90_minutes,
--     ROUND(AVG(diff_in_minutes), 2)                                     AS avg_minutes
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
-- WHERE diff_in_minutes IS NOT NULL
-- GROUP BY dt, metric_name
-- ORDER BY dt DESC, metric_name;

-- B2. Express Listing Completion Time only — split by is_express flag
-- SELECT
--     dt,
--     is_express,
--     PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                    AS p50_minutes,
--     PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                    AS p90_minutes,
--     COUNT(*)                                                            AS listing_count
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
-- WHERE metric_name    = 'Express Listing Completion Time'
--   AND diff_in_minutes IS NOT NULL
-- GROUP BY dt, is_express
-- ORDER BY dt DESC, is_express;

-- B3. Completion time by seller_tenure and geography (last 30 days)
-- SELECT
--     metric_name,
--     seller_tenure,
--     geography,
--     PERCENTILE_APPROX(diff_in_minutes, 0.50, 10000)                    AS p50_minutes,
--     PERCENTILE_APPROX(diff_in_minutes, 0.90, 10000)                    AS p90_minutes,
--     COUNT(*)                                                            AS sample_count
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
-- WHERE dt              >= DATE_SUB(CURRENT_DATE, 30)
--   AND diff_in_minutes IS NOT NULL
-- GROUP BY metric_name, seller_tenure, geography
-- ORDER BY metric_name, p50_minutes;

-- B4. Match rate — what % of events/listings had a prior CTA click
-- SELECT
--     metric_name,
--     COUNT(*)                                                            AS total,
--     COUNT(last_cta_ts)                                                  AS matched,
--     ROUND(COUNT(last_cta_ts) / COUNT(*) * 100, 2)                      AS match_rate_pct
-- FROM P_LIVE_ANALYTICS_T.COMPLETION_TIME_FINAL_T
-- WHERE dt >= DATE_SUB(CURRENT_DATE, 30)
-- GROUP BY metric_name;


-- ----------------------------------------------------------------
-- C. LISTING_ADOPTION_T
-- ----------------------------------------------------------------

-- C1. Express Listing adoption rate per event
-- SELECT
--     dt,
--     event_id,
--     seller_id,
--     total_listings,
--     express_listings,
--     ROUND(express_listings / NULLIF(total_listings, 0) * 100, 2)       AS express_adoption_pct
-- FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
-- ORDER BY dt DESC, express_adoption_pct DESC;

-- C2. Case Break adoption rate per event
-- SELECT
--     dt,
--     event_id,
--     seller_id,
--     total_listings,
--     case_break_listings,
--     ROUND(case_break_listings / NULLIF(total_listings, 0) * 100, 2)    AS case_break_adoption_pct
-- FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
-- ORDER BY dt DESC, case_break_adoption_pct DESC;

-- C3. Daily aggregate — overall express and case break adoption rates
-- SELECT
--     dt,
--     SUM(total_listings)                                                 AS total_listings,
--     SUM(express_listings)                                               AS express_listings,
--     SUM(case_break_listings)                                            AS case_break_listings,
--     ROUND(SUM(express_listings)    / NULLIF(SUM(total_listings), 0) * 100, 2) AS express_adoption_pct,
--     ROUND(SUM(case_break_listings) / NULLIF(SUM(total_listings), 0) * 100, 2) AS case_break_adoption_pct
-- FROM P_LIVE_ANALYTICS_T.LISTING_ADOPTION_T
-- GROUP BY dt
-- ORDER BY dt DESC;


-- ================================================================
-- PRE-STREAM DASHBOARD AGGREGATE TABLES
-- Tableau-ready pre-aggregated datasets for the Pre-Stream tab.
-- Data scope: 2026-07-17 onward (eBay Live launch).
-- Grains: Daily / Weekly (complete retail weeks) / Monthly / Overall
-- AVG time metrics: computed at all 4 grains (additive)
-- PERCENTILE_APPROX: Overall grain only (non-re-aggregatable)
-- ================================================================


-- ================================================================
-- PRE_STREAM_EVENT_METRICS_AGG
-- Sources : COMPLETION_RATE_FINAL_T  (rate metrics — both metric_names)
--         + COMPLETION_TIME_FINAL_T  (event side, metric_name = 'Event Completion Time')
-- Grain   : event publication / activity dt  →  Daily / Weekly / Monthly / Overall
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

SELECT
    COALESCE(r.label,             t.label)             AS label,
    COALESCE(r.timeframe,         t.timeframe)         AS timeframe,
    COALESCE(r.geography,         t.geography)         AS geography,
    COALESCE(r.launch_phase,      t.launch_phase)      AS launch_phase,
    COALESCE(r.category,          t.category)          AS category,
    COALESCE(r.gmv_tier,          t.gmv_tier)          AS gmv_tier,
    COALESCE(r.onboarding_method, t.onboarding_method) AS onboarding_method,
    COALESCE(r.seller_background, t.seller_background) AS seller_background,
    COALESCE(r.published_events,  0) AS published_events,
    COALESCE(r.cta_clicks,        0) AS cta_clicks,
    COALESCE(r.seller_setup_started, 0) AS seller_setup_started,
    COALESCE(r.seller_setup_success, 0) AS seller_setup_success,
    COALESCE(r.listings_completed, 0) AS listings_completed,
    COALESCE(r.listings_started,  0) AS listings_started,
    t.event_time_total_rows, t.event_time_matched_rows, t.event_completion_avg,
    NULL AS event_completion_p50, NULL AS event_completion_p75, NULL AS event_completion_p90
FROM rate_daily r
FULL OUTER JOIN event_time_daily t
    ON r.label=t.label AND r.timeframe=t.timeframe AND r.geography=t.geography AND r.launch_phase=t.launch_phase
    AND r.category=t.category AND r.gmv_tier=t.gmv_tier AND r.onboarding_method=t.onboarding_method AND r.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(r.label, t.label), COALESCE(r.timeframe, t.timeframe),
    COALESCE(r.geography, t.geography), COALESCE(r.launch_phase, t.launch_phase),
    COALESCE(r.category, t.category), COALESCE(r.gmv_tier, t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method), COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events, 0), COALESCE(r.cta_clicks, 0),
    COALESCE(r.seller_setup_started, 0), COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0), COALESCE(r.listings_started, 0),
    t.event_time_total_rows, t.event_time_matched_rows, t.event_completion_avg,
    NULL, NULL, NULL
FROM rate_weekly r
FULL OUTER JOIN event_time_weekly t
    ON r.label=t.label AND r.timeframe=t.timeframe AND r.geography=t.geography AND r.launch_phase=t.launch_phase
    AND r.category=t.category AND r.gmv_tier=t.gmv_tier AND r.onboarding_method=t.onboarding_method AND r.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(r.label, t.label), COALESCE(r.timeframe, t.timeframe),
    COALESCE(r.geography, t.geography), COALESCE(r.launch_phase, t.launch_phase),
    COALESCE(r.category, t.category), COALESCE(r.gmv_tier, t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method), COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events, 0), COALESCE(r.cta_clicks, 0),
    COALESCE(r.seller_setup_started, 0), COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0), COALESCE(r.listings_started, 0),
    t.event_time_total_rows, t.event_time_matched_rows, t.event_completion_avg,
    NULL, NULL, NULL
FROM rate_monthly r
FULL OUTER JOIN event_time_monthly t
    ON r.label=t.label AND r.timeframe=t.timeframe AND r.geography=t.geography AND r.launch_phase=t.launch_phase
    AND r.category=t.category AND r.gmv_tier=t.gmv_tier AND r.onboarding_method=t.onboarding_method AND r.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(r.label, t.label), COALESCE(r.timeframe, t.timeframe),
    COALESCE(r.geography, t.geography), COALESCE(r.launch_phase, t.launch_phase),
    COALESCE(r.category, t.category), COALESCE(r.gmv_tier, t.gmv_tier),
    COALESCE(r.onboarding_method, t.onboarding_method), COALESCE(r.seller_background, t.seller_background),
    COALESCE(r.published_events, 0), COALESCE(r.cta_clicks, 0),
    COALESCE(r.seller_setup_started, 0), COALESCE(r.seller_setup_success, 0),
    COALESCE(r.listings_completed, 0), COALESCE(r.listings_started, 0),
    t.event_time_total_rows, t.event_time_matched_rows, t.event_completion_avg,
    t.event_completion_p50, t.event_completion_p75, t.event_completion_p90
FROM rate_overall r
FULL OUTER JOIN event_time_overall t
    ON r.geography=t.geography AND r.launch_phase=t.launch_phase AND r.category=t.category
    AND r.gmv_tier=t.gmv_tier AND r.onboarding_method=t.onboarding_method AND r.seller_background=t.seller_background;


-- ================================================================
-- PRE_STREAM_LISTING_METRICS_AGG
-- Sources : LISTING_ADOPTION_T  (listing counts per event/seller)
--         + COMPLETION_TIME_FINAL_T (listing side, metric_name = 'Express Listing Completion Time')
-- Grain   : listing creation dt (SLNG_LSTG_SUPER_FACT.SITE_CREATE_DATE)
--           → Daily / Weekly / Monthly / Overall
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

adoption_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(total_listings) AS total_listings, SUM(express_listings) AS express_listings,
           SUM(case_break_listings) AS case_break_listings, COUNT(DISTINCT event_id) AS event_count
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
        SUM(total_listings) AS total_listings, SUM(express_listings) AS express_listings,
        SUM(case_break_listings) AS case_break_listings, COUNT(DISTINCT event_id) AS event_count
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
           SUM(total_listings) AS total_listings, SUM(express_listings) AS express_listings,
           SUM(case_break_listings) AS case_break_listings, COUNT(DISTINCT event_id) AS event_count
    FROM adoption_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),
adoption_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           SUM(total_listings) AS total_listings, SUM(express_listings) AS express_listings,
           SUM(case_break_listings) AS case_break_listings, COUNT(DISTINCT event_id) AS event_count
    FROM adoption_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),
listing_time_daily AS (
    SELECT DATE_FORMAT(dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*) AS listing_time_total_rows, COUNT(diff_in_minutes) AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2) AS express_listing_avg,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2) AS standard_listing_avg
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
        COUNT(*) AS listing_time_total_rows, COUNT(diff_in_minutes) AS listing_time_matched_rows,
        ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2) AS express_listing_avg,
        ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2) AS standard_listing_avg
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
           COUNT(*) AS listing_time_total_rows, COUNT(diff_in_minutes) AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2) AS express_listing_avg,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2) AS standard_listing_avg
    FROM listing_time_base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),
listing_time_overall AS (
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
           geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
           COUNT(*) AS listing_time_total_rows, COUNT(diff_in_minutes) AS listing_time_matched_rows,
           ROUND(AVG(CASE WHEN is_express = 1 THEN diff_in_minutes END), 2)                  AS express_listing_avg,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.50, 10000) AS express_listing_p50,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.75, 10000) AS express_listing_p75,
           PERCENTILE_APPROX(CASE WHEN is_express = 1 THEN diff_in_minutes END, 0.90, 10000) AS express_listing_p90,
           ROUND(AVG(CASE WHEN is_express = 0 THEN diff_in_minutes END), 2)                  AS standard_listing_avg,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.50, 10000) AS standard_listing_p50,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.75, 10000) AS standard_listing_p75,
           PERCENTILE_APPROX(CASE WHEN is_express = 0 THEN diff_in_minutes END, 0.90, 10000) AS standard_listing_p90
    FROM listing_time_base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

SELECT
    COALESCE(a.label, t.label) AS label, COALESCE(a.timeframe, t.timeframe) AS timeframe,
    COALESCE(a.geography, t.geography) AS geography, COALESCE(a.launch_phase, t.launch_phase) AS launch_phase,
    COALESCE(a.category, t.category) AS category, COALESCE(a.gmv_tier, t.gmv_tier) AS gmv_tier,
    COALESCE(a.onboarding_method, t.onboarding_method) AS onboarding_method,
    COALESCE(a.seller_background, t.seller_background) AS seller_background,
    COALESCE(a.total_listings, 0) AS total_listings, COALESCE(a.express_listings, 0) AS express_listings,
    COALESCE(a.case_break_listings, 0) AS case_break_listings, COALESCE(a.event_count, 0) AS event_count,
    t.listing_time_total_rows, t.listing_time_matched_rows,
    t.express_listing_avg, NULL AS express_listing_p50, NULL AS express_listing_p75, NULL AS express_listing_p90,
    t.standard_listing_avg, NULL AS standard_listing_p50, NULL AS standard_listing_p75, NULL AS standard_listing_p90
FROM adoption_daily a
FULL OUTER JOIN listing_time_daily t
    ON a.label=t.label AND a.timeframe=t.timeframe AND a.geography=t.geography AND a.launch_phase=t.launch_phase
    AND a.category=t.category AND a.gmv_tier=t.gmv_tier AND a.onboarding_method=t.onboarding_method AND a.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(a.label, t.label), COALESCE(a.timeframe, t.timeframe),
    COALESCE(a.geography, t.geography), COALESCE(a.launch_phase, t.launch_phase),
    COALESCE(a.category, t.category), COALESCE(a.gmv_tier, t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method), COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings, 0), COALESCE(a.express_listings, 0),
    COALESCE(a.case_break_listings, 0), COALESCE(a.event_count, 0),
    t.listing_time_total_rows, t.listing_time_matched_rows,
    t.express_listing_avg, NULL, NULL, NULL, t.standard_listing_avg, NULL, NULL, NULL
FROM adoption_weekly a
FULL OUTER JOIN listing_time_weekly t
    ON a.label=t.label AND a.timeframe=t.timeframe AND a.geography=t.geography AND a.launch_phase=t.launch_phase
    AND a.category=t.category AND a.gmv_tier=t.gmv_tier AND a.onboarding_method=t.onboarding_method AND a.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(a.label, t.label), COALESCE(a.timeframe, t.timeframe),
    COALESCE(a.geography, t.geography), COALESCE(a.launch_phase, t.launch_phase),
    COALESCE(a.category, t.category), COALESCE(a.gmv_tier, t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method), COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings, 0), COALESCE(a.express_listings, 0),
    COALESCE(a.case_break_listings, 0), COALESCE(a.event_count, 0),
    t.listing_time_total_rows, t.listing_time_matched_rows,
    t.express_listing_avg, NULL, NULL, NULL, t.standard_listing_avg, NULL, NULL, NULL
FROM adoption_monthly a
FULL OUTER JOIN listing_time_monthly t
    ON a.label=t.label AND a.timeframe=t.timeframe AND a.geography=t.geography AND a.launch_phase=t.launch_phase
    AND a.category=t.category AND a.gmv_tier=t.gmv_tier AND a.onboarding_method=t.onboarding_method AND a.seller_background=t.seller_background

UNION ALL

SELECT
    COALESCE(a.label, t.label), COALESCE(a.timeframe, t.timeframe),
    COALESCE(a.geography, t.geography), COALESCE(a.launch_phase, t.launch_phase),
    COALESCE(a.category, t.category), COALESCE(a.gmv_tier, t.gmv_tier),
    COALESCE(a.onboarding_method, t.onboarding_method), COALESCE(a.seller_background, t.seller_background),
    COALESCE(a.total_listings, 0), COALESCE(a.express_listings, 0),
    COALESCE(a.case_break_listings, 0), COALESCE(a.event_count, 0),
    t.listing_time_total_rows, t.listing_time_matched_rows,
    t.express_listing_avg, t.express_listing_p50, t.express_listing_p75, t.express_listing_p90,
    t.standard_listing_avg, t.standard_listing_p50, t.standard_listing_p75, t.standard_listing_p90
FROM adoption_overall a
FULL OUTER JOIN listing_time_overall t
    ON a.geography=t.geography AND a.launch_phase=t.launch_phase AND a.category=t.category
    AND a.gmv_tier=t.gmv_tier AND a.onboarding_method=t.onboarding_method AND a.seller_background=t.seller_background;


-- ================================================================
-- PRE_STREAM_FUNNEL_AGG
-- Funnel rebuilt from source tables (SELLER_FIRST_SHOW_FUNNEL
-- excluded — it has no dt column and cannot be cohorted by date).
-- Cohort base  : LIVE_SELLER_MASTER_V2  (studio_activated_ts)
-- Grain        : seller's studio activation date
--                → Daily / Weekly / Monthly / Overall
-- ================================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.PRE_STREAM_FUNNEL_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
    WHERE CAL_DT >= '2026-07-17'
),

published_event AS (
    SELECT DISTINCT CAST(hostids[0] AS BIGINT) AS sellerid
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT
    WHERE flag = 'PROD' AND isDeleted = FALSE AND visibilityState = 'PUBLISHED'
      AND dt >= '2026-07-17'
),

event_with_listing AS (
    SELECT DISTINCT CAST(e.hostids[0] AS BIGINT) AS sellerid
    FROM P_LIVE_ANALYTICS_V.LIVE_EVENT e
    JOIN P_LIVE_ANALYTICS_V.LIVE_EVENT_LISTING elc
        ON e.eventId = elc.eventId AND elc.isDeleted = FALSE AND elc.dt >= '2026-07-17'
    JOIN PRS_RESTRICTED_V.SLNG_LSTG_SUPER_FACT l
        ON elc.ITEMID = l.ITEM_ID AND l.AUCT_END_DT >= DATE_SUB(CURRENT_DATE(), 365)
    WHERE e.flag = 'PROD' AND e.isDeleted = FALSE AND e.visibilityState = 'PUBLISHED'
      AND e.dt >= '2026-07-17'
),

first_stream AS (
    SELECT slr_id AS sellerid, MIN(STARTTIME) AS first_stream_start
    FROM P_AMER_VERTICALS_T.LIVE_COMMERCE_DAILY_DEMAND_INDICATORS
    WHERE deleted_ind = 0 AND event_duration_min > 0
    GROUP BY slr_id
),

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
        CASE WHEN pe.sellerid  IS NOT NULL THEN 1 ELSE 0 END AS step1_event_created,
        CASE WHEN ewl.sellerid IS NOT NULL THEN 1 ELSE 0 END AS step2_listing_ready,
        CASE WHEN ewl.sellerid IS NOT NULL THEN 1 ELSE 0 END AS step3_first_show_ready,
        CASE
            WHEN fs.first_stream_start IS NOT NULL
             AND DATEDIFF(CAST(fs.first_stream_start AS DATE), CAST(m.studio_activated_ts AS DATE)) <= 14
            THEN 1 ELSE 0
        END AS step4_14d_first_show
    FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2 m
    INNER JOIN cal_ref cal ON CAST(m.studio_activated_ts AS DATE) = cal.CAL_DT
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(m.user_id_ubi AS STRING) = d.seller_id
    LEFT JOIN published_event    pe  ON m.user_id_ubi = pe.sellerid
    LEFT JOIN event_with_listing ewl ON m.user_id_ubi = ewl.sellerid
    LEFT JOIN first_stream       fs  ON m.user_id_ubi = fs.sellerid
    WHERE m.report_dt = (SELECT MAX(report_dt) FROM P_LIVE_ANALYTICS_T.LIVE_SELLER_MASTER_V2)
      AND m.is_test_user = 0 AND m.activated_studio = 1 AND m.studio_activated_ts IS NOT NULL
),

DAILY AS (
    SELECT DATE_FORMAT(activated_dt, 'yyyy-MM-dd') AS label, 'Daily' AS timeframe,
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
    SELECT CAST(MONTH_ID AS STRING) AS label, 'Monthly' AS timeframe,
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
    SELECT 'Overall' AS label, 'Overall' AS timeframe,
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
UNION ALL SELECT * FROM WEEKLY
UNION ALL SELECT * FROM MONTHLY
UNION ALL SELECT * FROM OVERALL;
