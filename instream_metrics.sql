-- ================================================================
-- IN-STREAM TAB — COMPLETE METRIC SQL
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: In-Stream
--
-- ⚠ SOURCE TABLE CHANGE (Jul 2026):
--   All in-stream metrics now sourced from HC_STREAM_METRICS,
--   NOT from LIVE_SELLER_MASTER_V2.
--   P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
--     Grain: one row per stream event (live_event_id) per report_dt
--     Data lag: DATE_SUB(CURRENT_DATE(), 2)  — data is 2 days behind
--     Geography: US-only at build time (EVENT_SITEID = 0)
--
-- Mandatory filter (ALL queries):
--   WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
--     AND is_test_user = 0
--
-- Aggregation rules:
--   GMV amounts      → SUM
--   Counts           → SUM (totals) or AVG (per-stream averages)
--   Derived rates    → AVG only — NEVER average of pre-computed rates
--   Stream count     → COUNT(DISTINCT live_event_id)
--   Percentiles      → PERCENTILE_APPROX(col, 0.5 | 0.9)
--
-- ⚠ CHATBC CAVEAT: *_global columns (chats_sent_global,
--   users_muted_global, chats_pinned_global, etc.) are seller-day
--   totals — if a seller ran multiple streams in one day all streams
--   get the same value. Use as directional only.
--
-- ⚠ VIEWER COUNT: Use total_unique_viewers / quality_viewers from
--   this table — NOT DDI VIEWERCOUNT which inflates 3–4×.
--
-- Run order: each section is independent.
-- ================================================================


-- ================================================================
-- SECTION 1 — L0 NORTH STAR: GMV PER STREAMING HOUR
--   Pre-computed: gmv_per_streaming_hour (SUM(gmv_during) /
--   SUM(event_duration_mins / 60)).
--   Recompute at rollup level — never AVG of per-stream rates.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,
    COUNT(DISTINCT seller_id)                                           AS n_streaming_sellers,

    -- GMV during stream
    ROUND(SUM(gmv_during), 2)                                           AS total_gmv_during,

    -- Stream duration (hours)
    ROUND(SUM(event_duration_mins) / 60.0, 1)                          AS total_streaming_hours,

    -- GMV / streaming hour — recompute at this rollup level
    ROUND(
        SUM(gmv_during) / NULLIF(SUM(event_duration_mins) / 60.0, 0),
    2)                                                                  AS gmv_per_streaming_hour,

    -- Stream duration distribution
    ROUND(PERCENTILE_APPROX(event_duration_mins, 0.5), 1)              AS p50_stream_duration_mins,
    ROUND(PERCENTILE_APPROX(event_duration_mins, 0.9), 1)              AS p90_stream_duration_mins

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 2 — GMV ATTRIBUTION WINDOWS (pre / during / post-stream)
--   gmv_pre  : 7-day pre-stream halo GMV
--   gmv_during: revenue during the live window
--   gmv_week : 7-day post-stream tail GMV
--   gmv_total: pre + during + week combined
--   Note: gmv_pre and gmv_week are not on the dashboard today
--         but are ready to add as viewer engagement grows.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,

    ROUND(SUM(gmv_pre), 2)                                              AS total_gmv_pre_7d,
    ROUND(SUM(gmv_during), 2)                                           AS total_gmv_during,
    ROUND(SUM(gmv_week), 2)                                             AS total_gmv_post_7d,
    ROUND(SUM(gmv_total), 2)                                            AS total_gmv_all_windows,

    -- Share breakdown
    ROUND(SUM(gmv_during) * 100.0 / NULLIF(SUM(gmv_total), 0), 1)     AS pct_gmv_during,
    ROUND(SUM(gmv_pre)    * 100.0 / NULLIF(SUM(gmv_total), 0), 1)     AS pct_gmv_pre,
    ROUND(SUM(gmv_week)   * 100.0 / NULLIF(SUM(gmv_total), 0), 1)     AS pct_gmv_post,

    -- Items sold by window
    SUM(items_sold_pre)                                                 AS items_sold_pre_7d,
    SUM(items_sold_during)                                              AS items_sold_during,
    SUM(items_sold_week)                                                AS items_sold_post_7d

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 3 — INVENTORY METRICS (dashboard: L1 Inventory tiles)
--   total_items_listed  : all items associated with stream
--   total_items_pinned  : items with pin=TRUE
--   bin_items_pinned    : BIN-format pinned items
--   auction_items_pinned: auction-format pinned items
--   sell_through_rate_all_pct: items_sold_during / total_items_listed
--
--   ⚠ Dashboard labels sell-through as "Pinned STR" but this column
--     is ALL-items STR. Pinned-specific STR is not pre-computed.
--     Align definition before GA.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,

    -- Inventory counts (avg per stream)
    ROUND(AVG(total_items_listed), 1)                                   AS avg_items_listed_per_stream,
    ROUND(AVG(total_items_pinned), 1)                                   AS avg_items_pinned_per_stream,
    ROUND(AVG(bin_items_pinned), 1)                                     AS avg_bin_pinned_per_stream,
    ROUND(AVG(auction_items_pinned), 1)                                 AS avg_auction_pinned_per_stream,
    ROUND(AVG(total_items_not_pinned), 1)                               AS avg_items_not_pinned,

    -- Totals
    SUM(total_items_listed)                                             AS total_items_listed,
    SUM(total_items_pinned)                                             AS total_items_pinned,
    SUM(bin_items_pinned)                                               AS total_bin_pinned,
    SUM(auction_items_pinned)                                           AS total_auction_pinned,

    -- Pin rate (pre-computed)
    ROUND(AVG(pin_rate_pct), 1)                                         AS avg_pin_rate_pct,

    -- Sell-through rate — all items (not pinned-only)
    -- Recompute at rollup level: SUM(sold) / SUM(listed)
    ROUND(
        SUM(items_sold_during) * 100.0
        / NULLIF(SUM(total_items_listed), 0), 1)                       AS sell_through_rate_all_pct,

    -- Pre-computed column for validation
    ROUND(AVG(sell_through_rate_all_pct), 1)                           AS avg_str_precomputed,

    -- Inventory health
    ROUND(AVG(pct_items_purchasable), 1)                               AS avg_pct_items_purchasable,
    ROUND(AVG(pct_items_visible), 1)                                    AS avg_pct_items_visible

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 4 — VIEWER ENGAGEMENT
--   NOT currently on dashboard — high-priority new metrics.
--   Use total_unique_viewers, NOT DDI VIEWERCOUNT (inflated 3–4×).
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,

    -- Viewer volume
    SUM(total_unique_viewers)                                           AS total_unique_viewers,
    ROUND(AVG(total_unique_viewers), 1)                                 AS avg_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(total_unique_viewers, 0.5), 0)             AS p50_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(total_unique_viewers, 0.9), 0)             AS p90_viewers_per_stream,

    -- Viewer quality
    SUM(quality_viewers)                                                AS total_quality_viewers,
    SUM(bounced_viewers)                                                AS total_bounced_viewers,
    SUM(engaged_viewers)                                                AS total_engaged_viewers,
    ROUND(AVG(quality_viewer_rate_pct), 1)                             AS avg_quality_viewer_rate_pct,

    -- Watch time
    ROUND(AVG(avg_watch_duration_secs), 0)                             AS avg_watch_duration_secs,
    ROUND(AVG(avg_time_in_stream_mins), 1)                             AS avg_time_in_stream_mins,

    -- Total watch minutes
    ROUND(SUM(total_watch_mins), 0)                                    AS total_watch_mins

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 5 — AUCTION / BID METRICS
--   NOT currently on dashboard — high-priority new metrics.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,
    COUNT(DISTINCT CASE WHEN total_bids > 0 THEN live_event_id END)    AS n_streams_with_bids,

    -- Bid volume
    SUM(total_bids)                                                     AS total_bids,
    ROUND(AVG(CASE WHEN total_bids > 0 THEN total_bids END), 1)        AS avg_bids_per_stream_w_bids,
    SUM(unique_bidders)                                                 AS total_unique_bidders,
    SUM(auction_items_with_bids)                                        AS total_auction_items_w_bids,

    -- Bid pricing
    ROUND(AVG(avg_starting_bid_amt), 2)                                AS avg_starting_bid_amt,
    ROUND(AVG(avg_final_bid_amt), 2)                                    AS avg_final_bid_amt,
    ROUND(AVG(avg_bid_price_realization_pct), 1)                       AS avg_bid_price_realization_pct,

    -- Auction sell-through (auction items sold / total auction items)
    ROUND(AVG(auction_sell_through_rate_pct), 1)                       AS avg_auction_str_pct

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 6 — PIN TIMING & ENGAGEMENT TOOLS
--   (dashboard: Avg Pin Duration P50, Engagement Tools/Stream)
--   ⚠ avg_pin_duration_proxy_mins is a PROXY — exact pin duration
--     blocked because listing_unpinned event not instrumented.
--   ⚠ Time to First Pin is NOT in HC_STREAM_METRICS (blocked).
--   UBI columns available from Jul 16 2026.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,

    -- Pin duration (proxy)
    ROUND(PERCENTILE_APPROX(avg_pin_duration_proxy_mins, 0.5), 1)      AS p50_pin_duration_proxy_mins,
    ROUND(PERCENTILE_APPROX(avg_pin_duration_proxy_mins, 0.9), 1)      AS p90_pin_duration_proxy_mins,
    ROUND(AVG(avg_pin_duration_proxy_mins), 1)                          AS avg_pin_duration_proxy_mins,

    -- In-stream listing edits
    ROUND(AVG(listing_edit_count), 1)                                   AS avg_listing_edits_per_stream,
    SUM(listing_edit_count)                                             AS total_listing_edits,

    -- Engagement tools (UBI — available from Jul 16 2026)
    -- Engagement Tools / Stream = quiz_launch_count + notice_toggle_count (no poll column)
    ROUND(AVG(quiz_launch_count + notice_toggle_count), 1)             AS avg_engagement_tools_per_stream,
    SUM(quiz_launch_count)                                              AS total_quiz_launches,
    SUM(quiz_create_count)                                              AS total_quiz_creates,
    SUM(quiz_start_count)                                               AS total_quiz_starts,
    SUM(notice_toggle_count)                                            AS total_notice_toggles

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 7 — CHAT METRICS (CHATBC)
--   (dashboard: Chat Messages / Stream)
--   ⚠ All *_global columns are seller-day totals — if a seller
--     ran 2 streams in one day, all rows get same count.
--     Results are directional only in multi-stream-per-day cases.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,
    COUNT(DISTINCT seller_id)                                           AS n_sellers,

    -- Chat volume (directional — seller-day totals)
    SUM(chats_sent_global)                                              AS total_chats_sent,
    ROUND(AVG(chats_sent_global), 1)                                    AS avg_chats_sent_per_stream,
    SUM(chats_pinned_global)                                            AS total_chats_pinned,
    SUM(preset_chats_saved_global)                                      AS total_preset_chats_saved,
    SUM(tab_switches_global)                                            AS total_tab_switches

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 8 — GUARDRAILS
--   (dashboard: Stream Activation Failures, Listings Added In-Stream,
--    Auction Resets, Users Muted)
--
--   stream_proxy_fired : 1 = UBI proxy fired (stream started OK),
--                        0 = proxy did not fire (potential failure)
--   add_listing_in_stream_count: new listings added mid-stream (0=ideal)
--   auction_reset_count: auction resets during stream (0=ideal)
--   users_muted_global : seller-day total (directional only)
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                       AS n_streams,

    -- Stream activation (proxy-based)
    SUM(CASE WHEN stream_proxy_fired = 1 THEN 1 ELSE 0 END)            AS n_streams_proxy_fired,
    SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END)            AS n_streams_proxy_not_fired,
    ROUND(
        SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(DISTINCT live_event_id), 0), 1)                 AS stream_proxy_failure_rate_pct,

    -- Listings added mid-stream (dead air signal — lower is better)
    SUM(add_listing_in_stream_count)                                    AS total_listings_added_in_stream,
    ROUND(AVG(add_listing_in_stream_count), 2)                          AS avg_listings_added_per_stream,
    ROUND(PERCENTILE_APPROX(add_listing_in_stream_count, 0.9), 0)      AS p90_listings_added,

    -- Auction resets (lower is better)
    SUM(auction_reset_count)                                            AS total_auction_resets,
    ROUND(AVG(auction_reset_count), 2)                                  AS avg_auction_resets_per_stream,
    ROUND(PERCENTILE_APPROX(auction_reset_count, 0.9), 0)              AS p90_auction_resets,

    -- Users muted (seller-day total — directional)
    SUM(users_muted_global)                                             AS total_users_muted,
    ROUND(AVG(users_muted_global), 2)                                   AS avg_users_muted_per_stream

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0;


-- ================================================================
-- SECTION 9 — DAILY TREND (all key in-stream metrics by stream date)
--   For trend charts on the In-Stream tab.
--   Ordered by stream_date ascending for time-series rendering.
-- ================================================================

SELECT
    report_dt                                                           AS stream_date,
    COUNT(DISTINCT live_event_id)                                       AS n_streams,
    COUNT(DISTINCT seller_id)                                           AS n_streaming_sellers,

    -- GMV
    ROUND(SUM(gmv_during), 2)                                           AS total_gmv_during,
    ROUND(
        SUM(gmv_during) / NULLIF(SUM(event_duration_mins) / 60.0, 0),
    2)                                                                  AS gmv_per_streaming_hour,

    -- Duration
    ROUND(PERCENTILE_APPROX(event_duration_mins, 0.5), 1)              AS p50_duration_mins,

    -- Inventory
    ROUND(AVG(total_items_listed), 1)                                   AS avg_items_listed,
    ROUND(AVG(total_items_pinned), 1)                                   AS avg_items_pinned,
    ROUND(AVG(pin_rate_pct), 1)                                         AS avg_pin_rate_pct,
    ROUND(
        SUM(items_sold_during) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                  AS sell_through_rate_pct,

    -- Viewers (canonical — not DDI)
    ROUND(AVG(total_unique_viewers), 0)                                 AS avg_viewers_per_stream,
    ROUND(AVG(quality_viewer_rate_pct), 1)                              AS avg_quality_viewer_rate_pct,

    -- Engagement
    ROUND(AVG(quiz_launch_count + notice_toggle_count), 1)             AS avg_engagement_tools,

    -- Guardrails
    SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END)            AS n_activation_failures,
    SUM(add_listing_in_stream_count)                                    AS total_listings_added_instream,
    SUM(auction_reset_count)                                            AS total_auction_resets

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt >= DATE_SUB(CURRENT_DATE(), 32)   -- trailing ~30 days of data
  AND report_dt <= DATE_SUB(CURRENT_DATE(), 2)    -- exclude incomplete days
  AND is_test_user = 0
GROUP BY report_dt
ORDER BY stream_date;


-- ================================================================
-- SECTION 10 — STREAM-LEVEL DETAIL (per-stream snapshot)
--   One row per stream. Use for seller-level drilldown.
--   Useful for: top/bottom performers, QA, seller coaching.
-- ================================================================

SELECT
    report_dt                                                           AS stream_date,
    live_event_id,
    seller_id,
    BSNS_VRTCL_NM                                                       AS category,
    seller_country_id,

    -- Duration and GMV
    ROUND(event_duration_mins, 0)                                       AS stream_duration_mins,
    ROUND(gmv_during, 2)                                                AS gmv_during,
    ROUND(gmv_per_streaming_hour, 2)                                    AS gmv_per_hr,

    -- Inventory
    total_items_listed,
    total_items_pinned,
    bin_items_pinned,
    auction_items_pinned,
    ROUND(sell_through_rate_all_pct, 1)                                 AS str_all_pct,

    -- Viewers
    total_unique_viewers,
    quality_viewers,
    ROUND(quality_viewer_rate_pct, 1)                                   AS quality_viewer_rate_pct,
    ROUND(avg_watch_duration_secs, 0)                                   AS avg_watch_secs,

    -- Bids
    total_bids,
    unique_bidders,
    ROUND(avg_bid_price_realization_pct, 1)                             AS bid_price_realization_pct,

    -- Guardrails
    stream_proxy_fired,
    add_listing_in_stream_count,
    auction_reset_count,
    users_muted_global                                                  AS users_muted_day_total

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE report_dt = DATE_SUB(CURRENT_DATE(), 2)
  AND is_test_user = 0
ORDER BY gmv_during DESC NULLS LAST;
