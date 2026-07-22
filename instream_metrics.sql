-- ================================================================
-- IN-STREAM TAB — COMPLETE METRIC SQL  v2
-- Dashboard: https://namitsharma-tech.github.io/ebay-live-opening-up-dashboard/
-- Tab: In-Stream
--
-- ⚠  SOURCE TABLE: P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
--   Grain : one row per (live_event_id, event_dt)
--   Lag   : data is 2 days behind — filter event_dt = DATE_SUB(CURRENT_DATE(), 2)
--   Scope : US-only (EVENT_SITEID = 0 applied at build time)
--
-- Changes from v1:
--   • Removed: GMV Attribution Windows section (S2) — not required
--   • Removed: standalone Pin Timing (S6) and Chat (S7) sections
--   • Restructured: Inventory section is now hierarchical (overall →
--       Featured/Non-featured → BIN/Auction within each)
--   • Auction/Bid metrics moved under Inventory as a sub-section
--   • Engagement section consolidated: viewer + seller chat + seller tools
--   • All 8 v1 bugs fixed (report_dt→event_dt, is_test_user removed,
--       3 wrong AVG aggregations, 2 wrong column names, total_watch_mins removed)
--   • New metrics: poll_start_count, pinned_items_sold_during,
--       featured_auction/bin_items_sold (requires table rebuild — see create.sql)
--
-- Mandatory filter (ALL queries):
--   WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2)
--   (No is_test_user filter — column does not exist in this table)
--
-- Aggregation rules:
--   GMV amounts      → SUM
--   Counts           → SUM (totals) or AVG (per-stream averages)
--   Derived rates    → NEVER AVG of pre-computed rates; always recompute
--                      at rollup level: SUM(num) / NULLIF(SUM(denom), 0)
--   Stream count     → COUNT(DISTINCT live_event_id)
--   Percentiles      → PERCENTILE_APPROX(col, 0.5 | 0.9)
--
-- ⚠  CHATBC CAVEAT: *_global columns (chats_sent_global, chats_pinned_global, etc.)
--   are seller-day totals — if a seller ran multiple streams in one day all streams
--   get the same value. Use as directional only.
--
-- ⚠  VIEWER COUNTS: Use total_unique_viewers / quality_viewers from this table —
--   NOT DDI VIEWERCOUNT which inflates 3–4×.
--
-- ⚠  PINNED STR CAVEAT: pinned_items_sold_during uses CDC pin flag from
--   LIVE_EVENT_LISTING — reflects pin state at last update, not exact time of sale.
--   Directional proxy; label clearly in dashboard tiles.
--
-- Section index:
--   S1 — L0 North Star: GMV per Streaming Hour
--   S2 — Inventory (hierarchical: Overall → Featured/Non-featured → BIN/Auction)
--   S2c— Auction & Bid Engagement (sub-section of Inventory)
--   S3 — Engagement Metrics
--        3a Viewer Engagement
--        3b Seller Chat Tools Adoption
--        3c Seller Engagement Tools Adoption
--   S4 — Guardrails
--   S5 — Daily Trend
--   S6 — Stream-Level Detail
-- ================================================================


-- ================================================================
-- SECTION 1 — L0 NORTH STAR: GMV PER STREAMING HOUR
--   North star metric: SUM(gmv_during) / SUM(event_duration_mins / 60)
--   Recomputed at rollup level — never AVG of per-stream gmv_per_streaming_hour.
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,
    COUNT(DISTINCT seller_id)                                            AS n_streaming_sellers,

    -- GMV during stream
    ROUND(SUM(gmv_during), 2)                                            AS total_gmv_during,

    -- Units sold alongside GMV (unit economics)
    SUM(items_sold_during)                                               AS total_items_sold_during,

    -- Stream duration
    ROUND(SUM(event_duration_mins) / 60.0, 1)                           AS total_streaming_hours,

    -- GMV / streaming hour — recomputed at this rollup level (L0 North Star)
    ROUND(
        SUM(gmv_during) / NULLIF(SUM(event_duration_mins) / 60.0, 0),
    2)                                                                   AS gmv_per_streaming_hour

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- ================================================================
-- SECTION 2 — INVENTORY METRICS (hierarchical)
--
-- Structure:
--   2a — Overall inventory summary (pin rate, STR)
--   2b — Featured (Pinned) vs Non-Featured breakdown
--         Within each: BIN vs Auction share
--
-- Sell-Through Rate (STR) notes:
--   Overall STR  : items_sold_during / total_items_listed (DDI gold standard)
--   Auction STR  : auction_items_sold / total_auction_items (bids table)
--   BIN STR      : (items_sold_during - auction_items_sold) / total_bin_items (approx)
--   Featured STR : pinned_items_sold_during / total_items_pinned (⚠ proxy — see header)
--   Non-feat STR : (items_sold_during - pinned_items_sold_during) / total_items_not_pinned
-- ================================================================

-- —— 2a — Overall Inventory Summary ————————————————————————————

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,

    -- Volume
    SUM(total_items_listed)                                              AS total_items_listed,
    ROUND(AVG(total_items_listed), 1)                                    AS avg_items_listed_per_stream,

    -- Pin rate (recomputed at rollup — Bug 6 fix)
    ROUND(
        SUM(total_items_pinned) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS pin_rate_pct,

    -- Format mix
    SUM(total_auction_items)                                             AS total_auction_items,
    SUM(total_bin_items)                                                 AS total_bin_items,
    ROUND(
        SUM(total_auction_items) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS pct_auction_items,
    ROUND(
        SUM(total_bin_items) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS pct_bin_items,

    -- Overall STR (all items, DDI gold standard)
    ROUND(
        SUM(items_sold_during) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS sell_through_rate_all_pct,

    -- Format-level STR
    ROUND(
        SUM(auction_items_sold) * 100.0 / NULLIF(SUM(total_auction_items), 0),
    1)                                                                   AS auction_sell_through_rate_pct,
    -- BIN STR: approx using items_sold_during - auction_items_sold as BIN sold proxy
    ROUND(
        (SUM(items_sold_during) - SUM(auction_items_sold)) * 100.0
        / NULLIF(SUM(total_bin_items), 0),
    1)                                                                   AS bin_sell_through_rate_pct,

    -- Inventory health
    ROUND(AVG(pct_items_purchasable), 1)                                 AS avg_pct_items_purchasable,
    ROUND(AVG(pct_items_visible), 1)                                     AS avg_pct_items_visible

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- —— 2b — Featured (Pinned) vs Non-Featured Breakdown ————————————
-- ⚠  STR proxy: pinned_items_sold_during uses CDC pin flag — directional only.

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,

    -- —— Featured (Pinned) ————————————————————————————————————
    SUM(total_items_pinned)                                              AS featured_items_total,
    ROUND(
        SUM(total_items_pinned) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS featured_share_pct,

    -- Within featured: BIN vs Auction
    SUM(bin_items_pinned)                                                AS featured_bin_count,
    SUM(auction_items_pinned)                                            AS featured_auction_count,
    ROUND(
        SUM(bin_items_pinned) * 100.0 / NULLIF(SUM(total_items_pinned), 0),
    1)                                                                   AS featured_bin_share_pct,
    ROUND(
        SUM(auction_items_pinned) * 100.0 / NULLIF(SUM(total_items_pinned), 0),
    1)                                                                   AS featured_auction_share_pct,

    -- Featured STR (⚠ proxy — see header caveat)
    ROUND(
        SUM(pinned_items_sold_during) * 100.0 / NULLIF(SUM(total_items_pinned), 0),
    1)                                                                   AS featured_str_pct,
    ROUND(
        SUM(featured_bin_items_sold) * 100.0 / NULLIF(SUM(bin_items_pinned), 0),
    1)                                                                   AS featured_bin_str_pct,
    ROUND(
        SUM(featured_auction_items_sold) * 100.0 / NULLIF(SUM(auction_items_pinned), 0),
    1)                                                                   AS featured_auction_str_pct,

    -- —— Non-Featured (Not Pinned) ————————————————————————————
    SUM(total_items_not_pinned)                                          AS non_featured_items_total,
    ROUND(
        SUM(total_items_not_pinned) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS non_featured_share_pct,

    -- Within non-featured: BIN vs Auction
    SUM(total_bin_items)   - SUM(bin_items_pinned)                       AS non_featured_bin_count,
    SUM(total_auction_items) - SUM(auction_items_pinned)                 AS non_featured_auction_count,
    ROUND(
        (SUM(total_bin_items) - SUM(bin_items_pinned)) * 100.0
        / NULLIF(SUM(total_items_not_pinned), 0),
    1)                                                                   AS non_featured_bin_share_pct,
    ROUND(
        (SUM(total_auction_items) - SUM(auction_items_pinned)) * 100.0
        / NULLIF(SUM(total_items_not_pinned), 0),
    1)                                                                   AS non_featured_auction_share_pct,

    -- Non-featured STR (⚠ numerator = DDI total sold minus pinned-proxy)
    ROUND(
        (SUM(items_sold_during) - SUM(pinned_items_sold_during)) * 100.0
        / NULLIF(SUM(total_items_not_pinned), 0),
    1)                                                                   AS non_featured_str_pct,
    ROUND(
        ((SUM(items_sold_during) - SUM(auction_items_sold)) - SUM(featured_bin_items_sold)) * 100.0
        / NULLIF(SUM(total_bin_items) - SUM(bin_items_pinned), 0),
    1)                                                                   AS non_featured_bin_str_pct,
    ROUND(
        (SUM(auction_items_sold) - SUM(featured_auction_items_sold)) * 100.0
        / NULLIF(SUM(total_auction_items) - SUM(auction_items_pinned), 0),
    1)                                                                   AS non_featured_auction_str_pct

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- —— 2c — Auction & Bid Engagement (sub-section of Inventory) ————

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,
    COUNT(DISTINCT CASE WHEN total_auction_items > 0 THEN live_event_id END)
                                                                         AS n_streams_with_auctions,
    COUNT(DISTINCT CASE WHEN total_bids > 0 THEN live_event_id END)      AS n_streams_with_bids,

    -- Auction inventory
    SUM(total_auction_items)                                             AS total_auction_items,
    SUM(auction_items_pinned)                                            AS total_auction_items_pinned,

    -- Bid volume
    SUM(total_bids)                                                      AS total_bids,
    ROUND(AVG(CASE WHEN total_bids > 0 THEN total_bids END), 1)         AS avg_bids_per_stream_w_bids,
    ROUND(SUM(total_bids) / NULLIF(SUM(auction_items_with_bids), 0), 1) AS avg_bids_per_auction_item,
    SUM(unique_bidders)                                                  AS total_unique_bidders,
    SUM(auction_items_with_bids)                                         AS total_auction_items_w_bids,
    SUM(auction_items_sold)                                              AS total_auction_items_sold,

    -- Bid pricing
    -- Weighted by auction_items_with_bids so high-volume streams dominate (not penny-start outliers)
    ROUND(
        SUM(avg_starting_bid_amt * auction_items_with_bids)
        / NULLIF(SUM(auction_items_with_bids), 0),
    2)                                                                   AS avg_starting_bid_amt,
    ROUND(
        SUM(avg_final_bid_amt * auction_items_with_bids)
        / NULLIF(SUM(auction_items_with_bids), 0),
    2)                                                                   AS avg_final_bid_amt,
    -- Bid price realization: weighted avg across streams (not simple AVG which is dominated by
    -- penny-start outliers where $0.01 start → $300 final = 2,999,900% per stream).
    ROUND(
        (SUM(avg_final_bid_amt * auction_items_with_bids) - SUM(avg_starting_bid_amt * auction_items_with_bids))
        / NULLIF(SUM(avg_starting_bid_amt * auction_items_with_bids), 0) * 100.0,
    1)                                                                   AS avg_bid_price_realization_pct,

    -- Auction STR (recomputed — Bug 7 fix)
    ROUND(
        SUM(auction_items_sold) * 100.0 / NULLIF(SUM(total_auction_items), 0),
    1)                                                                   AS auction_sell_through_rate_pct

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- ================================================================
-- SECTION 3 — ENGAGEMENT METRICS
--
-- 3a — Viewer Engagement
-- 3b — Seller Chat Tools Adoption (CHATBC — seller-day totals — directional)
-- 3c — Seller Engagement Tools Adoption (LIVECOMM — stream-attributed)
-- ================================================================

-- —— 3a — Viewer Engagement ——————————————————————————————————————
-- Viewer definitions (source: EBAYLIVE_QUALITY_VIEWERS):
--   quality_viewers : IS_QUALITY = 1  (DURATION_SECOND > threshold OR IS_ENGAGED = 1)
--   bounced_viewers : IS_BOUNCED = 1  (duration below quality threshold)
--   engaged_viewers : IS_ENGAGED = 1  (took at least one active action: bid, follow, etc.)

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,

    -- Viewer volume per stream
    ROUND(AVG(total_unique_viewers), 1)                                  AS avg_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(total_unique_viewers, 0.5), 0)              AS p50_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(total_unique_viewers, 0.9), 0)              AS p90_viewers_per_stream,
    SUM(total_unique_viewers)                                            AS total_unique_viewers,

    -- Quality viewers per stream
    ROUND(AVG(quality_viewers), 1)                                       AS avg_quality_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(quality_viewers, 0.5), 0)                   AS p50_quality_viewers_per_stream,
    ROUND(PERCENTILE_APPROX(quality_viewers, 0.9), 0)                   AS p90_quality_viewers_per_stream,

    -- Quality funnel rates (recomputed at rollup — Bug 8 fix)
    ROUND(
        SUM(quality_viewers) * 100.0 / NULLIF(SUM(total_unique_viewers), 0),
    1)                                                                   AS quality_viewer_rate_pct,
    ROUND(
        SUM(bounced_viewers) * 100.0 / NULLIF(SUM(total_unique_viewers), 0),
    1)                                                                   AS bounce_rate_pct,
    ROUND(
        SUM(engaged_viewers) * 100.0 / NULLIF(SUM(total_unique_viewers), 0),
    1)                                                                   AS engaged_viewer_rate_pct,

    -- Watch duration (avg_watch_duration_secs replaces broken total_watch_mins — Bug 3 fix)
    ROUND(AVG(avg_watch_duration_secs), 0)                              AS avg_watch_duration_secs,
    ROUND(AVG(avg_time_in_stream_mins), 1)                              AS avg_time_in_stream_mins

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- —— 3b — Seller Chat Tools Adoption (CHATBC) ————————————————————
-- Source: chats_sent_global / chats_pinned_global / chats_bookmarked_global /
--         preset_chats_saved_global from HC_UBI_BASE CHATBC family.
-- ⚠  *_global columns are seller-day totals — shared across all streams
--   run by the same seller on the same day. Results are directional only.

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,
    COUNT(DISTINCT seller_id)                                            AS n_sellers,

    -- Chat send
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0 THEN live_event_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_events_with_chats,
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_sending_chats,

    -- Pin chat
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0 THEN live_event_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_events_pinning_chats,
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_pinning_chats,

    -- Bookmark chat
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0 THEN live_event_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_events_bookmarking_chats,
    ROUND(
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_bookmarking_chats,

    -- Preset chat save
    ROUND(
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN live_event_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_events_saving_presets,
    ROUND(
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_saving_presets

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- —— 3c — Seller Engagement Tools Adoption (LIVECOMM) ————————————
-- Source: quiz_start_count / poll_start_count / notice_toggle_count
--         from HC_UBI_BASE LIVECOMM family — stream-attributed (event_id join).
-- Reported as %Sellers (unique sellers using each tool per stream).
-- Tool usage = at least one of (quiz_start OR poll_start OR notice_toggle).

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,
    COUNT(DISTINCT seller_id)                                            AS n_sellers,

    -- Individual tool adoption — %Sellers
    ROUND(
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_quiz,
    ROUND(
        COUNT(DISTINCT CASE WHEN poll_start_count > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_poll,
    ROUND(
        COUNT(DISTINCT CASE WHEN notice_toggle_count > 0 THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_notice,

    -- Any tool usage — %Sellers (at least 1 of quiz / poll / notice)
    ROUND(
        COUNT(DISTINCT CASE
            WHEN quiz_start_count > 0 OR poll_start_count > 0 OR notice_toggle_count > 0
            THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_any_tool,

    -- Raw event counts for volume context
    SUM(quiz_start_count)                                                AS total_quiz_starts,
    SUM(poll_start_count)                                                AS total_poll_starts,
    SUM(notice_toggle_count)                                             AS total_notice_toggles

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- ================================================================
-- SECTION 4 — GUARDRAILS
--   stream_proxy_fired  : 1 = UBI proxy fired (stream started OK)
--   add_listing_in_stream_count: new listings added mid-stream (lower is better)
--   auction_reset_count : ⚠ BLOCKED — returns 0 until auction_reset sid confirmed
--                         (see GAP_MATRIX.md before interpreting zeros)
--   users_muted_global  : seller-day total (⚠ directional only)
--   n_streams_zero_pins : streams where no item was ever pinned (dead-air signal)
--   n_streams_zero_sales: streams with 0 items sold (conversion failure signal)
-- ================================================================

SELECT
    COUNT(DISTINCT live_event_id)                                        AS n_streams,

    -- Stream activation (UBI proxy)
    SUM(CASE WHEN stream_proxy_fired = 1 THEN 1 ELSE 0 END)             AS n_streams_proxy_fired,
    SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END)             AS n_streams_proxy_not_fired,
    ROUND(
        SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS stream_proxy_failure_rate_pct,

    -- Zero-pin streams (dead-air guardrail)
    COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)
                                                                         AS n_streams_zero_pins,
    ROUND(
        COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END) * 100.0
        / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_streams_zero_pins,

    -- Zero-sale streams (conversion failure guardrail)
    COUNT(DISTINCT CASE WHEN items_sold_during = 0 THEN live_event_id END)
                                                                         AS n_streams_zero_sales,
    ROUND(
        COUNT(DISTINCT CASE WHEN items_sold_during = 0 THEN live_event_id END) * 100.0
        / NULLIF(COUNT(DISTINCT live_event_id), 0),
    1)                                                                   AS pct_streams_zero_sales,

    -- Listings added mid-stream (inventory not ready before stream — lower is better)
    SUM(add_listing_in_stream_count)                                     AS total_listings_added_in_stream,
    ROUND(AVG(add_listing_in_stream_count), 2)                          AS avg_listings_added_per_stream,
    ROUND(PERCENTILE_APPROX(add_listing_in_stream_count, 0.9), 0)       AS p90_listings_added,

    -- ⚠ BLOCKED: auction_reset_count returns 0 until auction_reset sid is confirmed.
    --    Do not interpret zeros as "no resets occurred". See GAP_MATRIX.md.
    SUM(auction_reset_count)                                             AS total_auction_resets,
    ROUND(AVG(auction_reset_count), 2)                                   AS avg_auction_resets_per_stream,

    -- Users muted (⚠ seller-day total — directional only)
    SUM(users_muted_global)                                              AS total_users_muted,
    ROUND(AVG(users_muted_global), 2)                                    AS avg_users_muted_per_stream

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2);


-- ================================================================
-- SECTION 5 — DAILY TREND (all key in-stream metrics by stream date)
--   Trailing ~30 days for time-series charts on the In-Stream tab.
--   Ordered ascending for time-series rendering.
--   Rates recomputed at rollup level — never AVG of per-stream rates.
-- ================================================================

SELECT
    event_dt                                                             AS stream_date,
    COUNT(DISTINCT live_event_id)                                        AS n_streams,
    COUNT(DISTINCT seller_id)                                            AS n_streaming_sellers,

    -- GMV
    ROUND(SUM(gmv_during), 2)                                            AS total_gmv_during,
    ROUND(
        SUM(gmv_during) / NULLIF(SUM(event_duration_mins) / 60.0, 0),
    2)                                                                   AS gmv_per_streaming_hour,
    ROUND(SUM(gmv_during) / NULLIF(COUNT(DISTINCT live_event_id), 0), 2) AS avg_gmv_per_stream,

    -- Duration
    ROUND(PERCENTILE_APPROX(event_duration_mins, 0.5), 1)               AS p50_duration_mins,

    -- Inventory
    ROUND(AVG(total_items_listed), 1)                                    AS avg_items_listed,
    ROUND(AVG(total_items_pinned), 1)                                    AS avg_items_pinned,
    -- Pin rate recomputed at rollup (Bug 6 fix)
    ROUND(
        SUM(total_items_pinned) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS pin_rate_pct,
    ROUND(
        SUM(items_sold_during) * 100.0 / NULLIF(SUM(total_items_listed), 0),
    1)                                                                   AS sell_through_rate_pct,

    -- Viewer engagement
    ROUND(AVG(total_unique_viewers), 0)                                  AS avg_viewers_per_stream,
    -- Quality viewer rate recomputed at rollup (Bug 8 fix)
    ROUND(
        SUM(quality_viewers) * 100.0 / NULLIF(SUM(total_unique_viewers), 0),
    1)                                                                   AS quality_viewer_rate_pct,
    ROUND(AVG(avg_watch_duration_secs), 0)                              AS avg_watch_duration_secs,

    -- Seller tool engagement
    ROUND(
        COUNT(DISTINCT CASE
            WHEN quiz_start_count > 0 OR poll_start_count > 0 OR notice_toggle_count > 0
            THEN seller_id END)
        * 100.0 / NULLIF(COUNT(DISTINCT seller_id), 0),
    1)                                                                   AS pct_sellers_any_tool,

    -- Guardrails
    SUM(CASE WHEN stream_proxy_fired = 0 THEN 1 ELSE 0 END)             AS n_activation_failures,
    COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)
                                                                         AS n_streams_zero_pins,
    SUM(add_listing_in_stream_count)                                     AS total_listings_added_instream,
    SUM(auction_reset_count)                                             AS total_auction_resets

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt >= DATE_SUB(CURRENT_DATE(), 32)
  AND event_dt <= DATE_SUB(CURRENT_DATE(), 2)
GROUP BY event_dt
ORDER BY stream_date;


-- ================================================================
-- SECTION 6 — STREAM-LEVEL DETAIL (per-stream snapshot)
--   One row per stream. Use for seller-level drilldown, QA,
--   and seller coaching. Ordered by GMV descending.
--
--   Bug fixes applied:
--     BSNS_VRTCL_NM  → BSNS_VRTCL_NAME  (Bug 4)
--     seller_country_id → SELLER_COUNTRY (Bug 5)
--     report_dt → event_dt              (Bug 1)
--     is_test_user filter removed       (Bug 2)
-- ================================================================

SELECT
    event_dt                                                             AS stream_date,
    live_event_id,
    seller_id,
    BSNS_VRTCL_NAME                                                      AS category,
    FCSD_VRTCL_GRP                                                       AS vertical_group,
    SELLER_COUNTRY                                                        AS seller_country,
    STARTTIME                                                             AS stream_start_time,
    ENDTIME                                                               AS stream_end_time,

    -- Duration and GMV
    ROUND(event_duration_mins, 0)                                        AS stream_duration_mins,
    ROUND(gmv_during, 2)                                                 AS gmv_during,
    ROUND(gmv_per_streaming_hour, 2)                                     AS gmv_per_hr,

    -- Inventory
    total_items_listed,
    total_items_pinned,
    bin_items_pinned,
    auction_items_pinned,
    ROUND(sell_through_rate_all_pct, 1)                                  AS str_all_pct,
    -- Featured STR (⚠ directional proxy — see header)
    ROUND(
        CASE WHEN total_items_pinned > 0
        THEN pinned_items_sold_during * 100.0 / total_items_pinned
        ELSE NULL END,
    1)                                                                   AS featured_str_pct,
    ROUND(avg_pin_duration_proxy_mins, 1)                                AS avg_pin_duration_proxy_mins,

    -- Viewers
    total_unique_viewers,
    quality_viewers,
    ROUND(quality_viewer_rate_pct, 1)                                    AS quality_viewer_rate_pct,
    ROUND(avg_watch_duration_secs, 0)                                    AS avg_watch_secs,

    -- Bids
    total_bids,
    unique_bidders,
    ROUND(avg_bid_price_realization_pct, 1)                              AS bid_price_realization_pct,

    -- Chat (⚠ seller-day total — directional)
    chats_sent_global,

    -- Guardrails
    stream_proxy_fired,
    add_listing_in_stream_count,
    auction_reset_count,
    users_muted_global                                                   AS users_muted_day_total

FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS
WHERE event_dt = DATE_SUB(CURRENT_DATE(), 2)
ORDER BY gmv_during DESC NULLS LAST;
