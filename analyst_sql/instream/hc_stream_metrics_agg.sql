-- ============================================================
-- P_LIVE_ANALYTICS_T.HC_STREAM_METRICS_AGG
-- Pre-aggregated Tableau-ready table for the Instream tab of
-- the eBay Live Opening Up dashboard.
--
-- Source:  P_LIVE_ANALYTICS_T.HC_STREAM_METRICS (1 row / stream / day)
--          joined to LIVE_SELLER_UNIFIED_ONBOARDING_DIM by seller_id
-- Grains:  Daily | Weekly (retail, complete weeks) | Monthly | Overall
-- Scope:   event_dt >= '2026-07-17' (eBay Live launch date)
-- Lag:     Inherits HC_STREAM_METRICS 2-day lag automatically
-- Dims:    geography, launch_phase, category, gmv_tier, onboarding_method,
--          seller_background (matches pre_stream tables' dimension set)
--
-- Aggregation rules:
--   SUM-able columns: all volume/count/inventory/viewer totals
--   AVG()-across-streams: avg_watch_duration_secs, avg_*_bid_amt,
--     avg_bid_price_realization_pct, avg_pin_duration_proxy_mins,
--     avg_pct_items_purchasable/visible — these are per-stream averages
--     in the source; matches V2 SQL behavior
--   Rate columns: NOT stored — derive in Tableau from numerator/denominator SUMs
--   PERCENTILE_APPROX: Overall grain only (NULL at D/W/M)
-- ============================================================

DROP TABLE IF EXISTS P_LIVE_ANALYTICS_T.HC_STREAM_METRICS_AGG;
CREATE TABLE P_LIVE_ANALYTICS_T.HC_STREAM_METRICS_AGG AS

WITH cal_ref AS (
    SELECT DISTINCT CAL_DT, RETAIL_YEAR, RETAIL_WEEK, AGE_FOR_RTL_WEEK_ID, MONTH_ID
    FROM ACCESS_VIEWS.DW_CAL_DT
    WHERE CAL_DT >= '2026-07-17'
),

base AS (
    SELECT
        s.live_event_id,
        s.seller_id,
        s.event_dt,
        COALESCE(d.geography,         'Unknown') AS geography,
        COALESCE(d.launch_phase,      'Unknown') AS launch_phase,
        COALESCE(d.category,          'Unknown') AS category,
        COALESCE(d.gmv_tier,          'Unknown') AS gmv_tier,
        COALESCE(d.onboarding_method, 'Unknown') AS onboarding_method,
        COALESCE(d.seller_background, 'Unknown') AS seller_background,
        s.gmv_during,
        s.event_duration_mins,
        s.items_sold_during,
        s.total_items_listed,
        s.total_items_pinned,
        s.total_items_not_pinned,
        s.total_bin_items,
        s.total_auction_items,
        s.bin_items_pinned,
        s.auction_items_pinned,
        s.auction_items_sold,
        s.pinned_items_sold_during,
        s.featured_auction_items_sold,
        s.featured_bin_items_sold,
        s.auction_items_with_bids,
        s.total_bids,
        s.unique_bidders,
        s.avg_starting_bid_amt,
        s.avg_final_bid_amt,
        s.avg_bid_price_realization_pct,
        s.avg_pin_duration_proxy_mins,
        s.pct_items_purchasable,
        s.pct_items_visible,
        s.total_unique_viewers,
        s.quality_viewers,
        s.bounced_viewers,
        s.engaged_viewers,
        s.avg_watch_duration_secs,
        s.avg_time_in_stream_mins,
        s.chats_sent_global,
        s.chats_pinned_global,
        s.chats_bookmarked_global,
        s.preset_chats_saved_global,
        s.quiz_start_count,
        s.poll_start_count,
        s.notice_toggle_count,
        s.stream_proxy_fired,
        s.add_listing_in_stream_count,
        s.auction_reset_count,
        s.users_muted_global,
        cal.RETAIL_YEAR,
        cal.RETAIL_WEEK,
        cal.AGE_FOR_RTL_WEEK_ID,
        cal.MONTH_ID
    FROM P_LIVE_ANALYTICS_T.HC_STREAM_METRICS s
    INNER JOIN cal_ref cal ON s.event_dt = cal.CAL_DT
    LEFT JOIN P_LIVE_ANALYTICS_T.LIVE_SELLER_UNIFIED_ONBOARDING_DIM d
        ON CAST(s.seller_id AS BIGINT) = CAST(d.seller_id AS BIGINT)
),

daily AS (
    SELECT
        DATE_FORMAT(event_dt, 'yyyy-MM-dd')      AS label,
        'Daily'                                   AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        -- Volume
        COUNT(DISTINCT live_event_id)             AS n_streams,
        COUNT(DISTINCT seller_id)                 AS n_streaming_sellers,
        -- GMV & duration (components; Tableau derives gmv_per_streaming_hour)
        SUM(gmv_during)                           AS total_gmv_during,
        SUM(items_sold_during)                    AS total_items_sold_during,
        SUM(event_duration_mins)                  AS total_streaming_mins,
        -- Inventory
        SUM(total_items_listed)                   AS total_items_listed,
        SUM(total_items_pinned)                   AS total_items_pinned,
        SUM(total_items_not_pinned)               AS total_items_not_pinned,
        SUM(total_bin_items)                      AS total_bin_items,
        SUM(total_auction_items)                  AS total_auction_items,
        SUM(bin_items_pinned)                     AS bin_items_pinned,
        SUM(auction_items_pinned)                 AS auction_items_pinned,
        SUM(auction_items_sold)                   AS auction_items_sold,
        SUM(pinned_items_sold_during)             AS pinned_items_sold_during,
        SUM(featured_auction_items_sold)          AS featured_auction_items_sold,
        SUM(featured_bin_items_sold)              AS featured_bin_items_sold,
        -- Auction / bidding
        COUNT(DISTINCT CASE WHEN total_auction_items > 0 THEN live_event_id END) AS n_streams_with_auctions,
        COUNT(DISTINCT CASE WHEN total_bids > 0          THEN live_event_id END) AS n_streams_with_bids,
        SUM(auction_items_with_bids)              AS auction_items_with_bids,
        SUM(total_bids)                           AS total_bids,
        SUM(unique_bidders)                       AS total_unique_bidders,
        ROUND(AVG(avg_starting_bid_amt), 2)       AS avg_starting_bid_amt,
        ROUND(AVG(avg_final_bid_amt), 2)          AS avg_final_bid_amt,
        ROUND(AVG(avg_bid_price_realization_pct), 2) AS avg_bid_price_realization_pct,
        ROUND(AVG(avg_pin_duration_proxy_mins), 2)   AS avg_pin_duration_proxy_mins,
        ROUND(AVG(pct_items_purchasable), 2)      AS avg_pct_items_purchasable,
        ROUND(AVG(pct_items_visible), 2)          AS avg_pct_items_visible,
        -- Viewer engagement
        SUM(total_unique_viewers)                 AS total_unique_viewers,
        SUM(quality_viewers)                      AS total_quality_viewers,
        SUM(bounced_viewers)                      AS total_bounced_viewers,
        SUM(engaged_viewers)                      AS total_engaged_viewers,
        ROUND(AVG(avg_watch_duration_secs), 2)    AS avg_watch_duration_secs,
        ROUND(AVG(avg_time_in_stream_mins), 2)    AS avg_time_in_stream_mins,
        NULL                                      AS p50_viewers_per_stream,
        NULL                                      AS p90_viewers_per_stream,
        NULL                                      AS p50_duration_mins,
        NULL                                      AS p90_duration_mins,
        -- Chat tools adoption (COUNT DISTINCT safe even for multi-stream sellers;
        -- chats_*_global are seller-day totals but distinctness deduplicates)
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0         THEN seller_id END) AS n_sellers_sent_chats,
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0       THEN seller_id END) AS n_sellers_pinned_chats,
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0   THEN seller_id END) AS n_sellers_bookmarked_chats,
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN seller_id END) AS n_sellers_saved_presets,
        -- Engagement tools (stream-level events)
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0          THEN seller_id END) AS n_sellers_quiz,
        COUNT(DISTINCT CASE WHEN poll_start_count > 0          THEN seller_id END) AS n_sellers_poll,
        COUNT(DISTINCT CASE WHEN notice_toggle_count > 0       THEN seller_id END) AS n_sellers_notice,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0 OR poll_start_count > 0
                                OR notice_toggle_count > 0 THEN seller_id END)     AS n_sellers_any_tool,
        SUM(quiz_start_count)                     AS total_quiz_starts,
        SUM(poll_start_count)                     AS total_poll_starts,
        SUM(notice_toggle_count)                  AS total_notice_toggles,
        -- Guardrails
        SUM(stream_proxy_fired)                   AS n_streams_proxy_fired,
        COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)    AS n_streams_zero_pins,
        COUNT(DISTINCT CASE WHEN items_sold_during  = 0 THEN live_event_id END)    AS n_streams_zero_sales,
        SUM(add_listing_in_stream_count)          AS total_listings_added_in_stream,
        SUM(auction_reset_count)                  AS total_auction_resets,
        SUM(users_muted_global)                   AS total_users_muted
    FROM base
    GROUP BY DATE_FORMAT(event_dt, 'yyyy-MM-dd'), geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

weekly AS (
    SELECT
        CAST(RETAIL_YEAR AS STRING) || 'RW' ||
            CASE WHEN LENGTH(CAST(RETAIL_WEEK AS STRING)) = 1 THEN '0' ELSE '' END ||
            CAST(RETAIL_WEEK AS STRING)              AS label,
        'Weekly'                                     AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT live_event_id)                AS n_streams,
        COUNT(DISTINCT seller_id)                    AS n_streaming_sellers,
        SUM(gmv_during)                              AS total_gmv_during,
        SUM(items_sold_during)                       AS total_items_sold_during,
        SUM(event_duration_mins)                     AS total_streaming_mins,
        SUM(total_items_listed)                      AS total_items_listed,
        SUM(total_items_pinned)                      AS total_items_pinned,
        SUM(total_items_not_pinned)                  AS total_items_not_pinned,
        SUM(total_bin_items)                         AS total_bin_items,
        SUM(total_auction_items)                     AS total_auction_items,
        SUM(bin_items_pinned)                        AS bin_items_pinned,
        SUM(auction_items_pinned)                    AS auction_items_pinned,
        SUM(auction_items_sold)                      AS auction_items_sold,
        SUM(pinned_items_sold_during)                AS pinned_items_sold_during,
        SUM(featured_auction_items_sold)             AS featured_auction_items_sold,
        SUM(featured_bin_items_sold)                 AS featured_bin_items_sold,
        COUNT(DISTINCT CASE WHEN total_auction_items > 0 THEN live_event_id END)  AS n_streams_with_auctions,
        COUNT(DISTINCT CASE WHEN total_bids > 0          THEN live_event_id END)  AS n_streams_with_bids,
        SUM(auction_items_with_bids)                 AS auction_items_with_bids,
        SUM(total_bids)                              AS total_bids,
        SUM(unique_bidders)                          AS total_unique_bidders,
        ROUND(AVG(avg_starting_bid_amt), 2)          AS avg_starting_bid_amt,
        ROUND(AVG(avg_final_bid_amt), 2)             AS avg_final_bid_amt,
        ROUND(AVG(avg_bid_price_realization_pct), 2) AS avg_bid_price_realization_pct,
        ROUND(AVG(avg_pin_duration_proxy_mins), 2)   AS avg_pin_duration_proxy_mins,
        ROUND(AVG(pct_items_purchasable), 2)         AS avg_pct_items_purchasable,
        ROUND(AVG(pct_items_visible), 2)             AS avg_pct_items_visible,
        SUM(total_unique_viewers)                    AS total_unique_viewers,
        SUM(quality_viewers)                         AS total_quality_viewers,
        SUM(bounced_viewers)                         AS total_bounced_viewers,
        SUM(engaged_viewers)                         AS total_engaged_viewers,
        ROUND(AVG(avg_watch_duration_secs), 2)       AS avg_watch_duration_secs,
        ROUND(AVG(avg_time_in_stream_mins), 2)       AS avg_time_in_stream_mins,
        NULL                                         AS p50_viewers_per_stream,
        NULL                                         AS p90_viewers_per_stream,
        NULL                                         AS p50_duration_mins,
        NULL                                         AS p90_duration_mins,
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0         THEN seller_id END) AS n_sellers_sent_chats,
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0       THEN seller_id END) AS n_sellers_pinned_chats,
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0   THEN seller_id END) AS n_sellers_bookmarked_chats,
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN seller_id END) AS n_sellers_saved_presets,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0          THEN seller_id END) AS n_sellers_quiz,
        COUNT(DISTINCT CASE WHEN poll_start_count > 0          THEN seller_id END) AS n_sellers_poll,
        COUNT(DISTINCT CASE WHEN notice_toggle_count > 0       THEN seller_id END) AS n_sellers_notice,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0 OR poll_start_count > 0
                                OR notice_toggle_count > 0 THEN seller_id END)     AS n_sellers_any_tool,
        SUM(quiz_start_count)                        AS total_quiz_starts,
        SUM(poll_start_count)                        AS total_poll_starts,
        SUM(notice_toggle_count)                     AS total_notice_toggles,
        SUM(stream_proxy_fired)                      AS n_streams_proxy_fired,
        COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)    AS n_streams_zero_pins,
        COUNT(DISTINCT CASE WHEN items_sold_during  = 0 THEN live_event_id END)    AS n_streams_zero_sales,
        SUM(add_listing_in_stream_count)             AS total_listings_added_in_stream,
        SUM(auction_reset_count)                     AS total_auction_resets,
        SUM(users_muted_global)                      AS total_users_muted
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
        CAST(MONTH_ID AS STRING)                     AS label,
        'Monthly'                                    AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT live_event_id)                AS n_streams,
        COUNT(DISTINCT seller_id)                    AS n_streaming_sellers,
        SUM(gmv_during)                              AS total_gmv_during,
        SUM(items_sold_during)                       AS total_items_sold_during,
        SUM(event_duration_mins)                     AS total_streaming_mins,
        SUM(total_items_listed)                      AS total_items_listed,
        SUM(total_items_pinned)                      AS total_items_pinned,
        SUM(total_items_not_pinned)                  AS total_items_not_pinned,
        SUM(total_bin_items)                         AS total_bin_items,
        SUM(total_auction_items)                     AS total_auction_items,
        SUM(bin_items_pinned)                        AS bin_items_pinned,
        SUM(auction_items_pinned)                    AS auction_items_pinned,
        SUM(auction_items_sold)                      AS auction_items_sold,
        SUM(pinned_items_sold_during)                AS pinned_items_sold_during,
        SUM(featured_auction_items_sold)             AS featured_auction_items_sold,
        SUM(featured_bin_items_sold)                 AS featured_bin_items_sold,
        COUNT(DISTINCT CASE WHEN total_auction_items > 0 THEN live_event_id END)  AS n_streams_with_auctions,
        COUNT(DISTINCT CASE WHEN total_bids > 0          THEN live_event_id END)  AS n_streams_with_bids,
        SUM(auction_items_with_bids)                 AS auction_items_with_bids,
        SUM(total_bids)                              AS total_bids,
        SUM(unique_bidders)                          AS total_unique_bidders,
        ROUND(AVG(avg_starting_bid_amt), 2)          AS avg_starting_bid_amt,
        ROUND(AVG(avg_final_bid_amt), 2)             AS avg_final_bid_amt,
        ROUND(AVG(avg_bid_price_realization_pct), 2) AS avg_bid_price_realization_pct,
        ROUND(AVG(avg_pin_duration_proxy_mins), 2)   AS avg_pin_duration_proxy_mins,
        ROUND(AVG(pct_items_purchasable), 2)         AS avg_pct_items_purchasable,
        ROUND(AVG(pct_items_visible), 2)             AS avg_pct_items_visible,
        SUM(total_unique_viewers)                    AS total_unique_viewers,
        SUM(quality_viewers)                         AS total_quality_viewers,
        SUM(bounced_viewers)                         AS total_bounced_viewers,
        SUM(engaged_viewers)                         AS total_engaged_viewers,
        ROUND(AVG(avg_watch_duration_secs), 2)       AS avg_watch_duration_secs,
        ROUND(AVG(avg_time_in_stream_mins), 2)       AS avg_time_in_stream_mins,
        NULL                                         AS p50_viewers_per_stream,
        NULL                                         AS p90_viewers_per_stream,
        NULL                                         AS p50_duration_mins,
        NULL                                         AS p90_duration_mins,
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0         THEN seller_id END) AS n_sellers_sent_chats,
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0       THEN seller_id END) AS n_sellers_pinned_chats,
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0   THEN seller_id END) AS n_sellers_bookmarked_chats,
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN seller_id END) AS n_sellers_saved_presets,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0          THEN seller_id END) AS n_sellers_quiz,
        COUNT(DISTINCT CASE WHEN poll_start_count > 0          THEN seller_id END) AS n_sellers_poll,
        COUNT(DISTINCT CASE WHEN notice_toggle_count > 0       THEN seller_id END) AS n_sellers_notice,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0 OR poll_start_count > 0
                                OR notice_toggle_count > 0 THEN seller_id END)     AS n_sellers_any_tool,
        SUM(quiz_start_count)                        AS total_quiz_starts,
        SUM(poll_start_count)                        AS total_poll_starts,
        SUM(notice_toggle_count)                     AS total_notice_toggles,
        SUM(stream_proxy_fired)                      AS n_streams_proxy_fired,
        COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)    AS n_streams_zero_pins,
        COUNT(DISTINCT CASE WHEN items_sold_during  = 0 THEN live_event_id END)    AS n_streams_zero_sales,
        SUM(add_listing_in_stream_count)             AS total_listings_added_in_stream,
        SUM(auction_reset_count)                     AS total_auction_resets,
        SUM(users_muted_global)                      AS total_users_muted
    FROM base
    GROUP BY MONTH_ID, geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
),

overall AS (
    SELECT
        'Overall'                                    AS label,
        'Overall'                                    AS timeframe,
        geography, launch_phase, category, gmv_tier, onboarding_method, seller_background,
        COUNT(DISTINCT live_event_id)                AS n_streams,
        COUNT(DISTINCT seller_id)                    AS n_streaming_sellers,
        SUM(gmv_during)                              AS total_gmv_during,
        SUM(items_sold_during)                       AS total_items_sold_during,
        SUM(event_duration_mins)                     AS total_streaming_mins,
        SUM(total_items_listed)                      AS total_items_listed,
        SUM(total_items_pinned)                      AS total_items_pinned,
        SUM(total_items_not_pinned)                  AS total_items_not_pinned,
        SUM(total_bin_items)                         AS total_bin_items,
        SUM(total_auction_items)                     AS total_auction_items,
        SUM(bin_items_pinned)                        AS bin_items_pinned,
        SUM(auction_items_pinned)                    AS auction_items_pinned,
        SUM(auction_items_sold)                      AS auction_items_sold,
        SUM(pinned_items_sold_during)                AS pinned_items_sold_during,
        SUM(featured_auction_items_sold)             AS featured_auction_items_sold,
        SUM(featured_bin_items_sold)                 AS featured_bin_items_sold,
        COUNT(DISTINCT CASE WHEN total_auction_items > 0 THEN live_event_id END)  AS n_streams_with_auctions,
        COUNT(DISTINCT CASE WHEN total_bids > 0          THEN live_event_id END)  AS n_streams_with_bids,
        SUM(auction_items_with_bids)                 AS auction_items_with_bids,
        SUM(total_bids)                              AS total_bids,
        SUM(unique_bidders)                          AS total_unique_bidders,
        ROUND(AVG(avg_starting_bid_amt), 2)          AS avg_starting_bid_amt,
        ROUND(AVG(avg_final_bid_amt), 2)             AS avg_final_bid_amt,
        ROUND(AVG(avg_bid_price_realization_pct), 2) AS avg_bid_price_realization_pct,
        ROUND(AVG(avg_pin_duration_proxy_mins), 2)   AS avg_pin_duration_proxy_mins,
        ROUND(AVG(pct_items_purchasable), 2)         AS avg_pct_items_purchasable,
        ROUND(AVG(pct_items_visible), 2)             AS avg_pct_items_visible,
        SUM(total_unique_viewers)                    AS total_unique_viewers,
        SUM(quality_viewers)                         AS total_quality_viewers,
        SUM(bounced_viewers)                         AS total_bounced_viewers,
        SUM(engaged_viewers)                         AS total_engaged_viewers,
        ROUND(AVG(avg_watch_duration_secs), 2)       AS avg_watch_duration_secs,
        ROUND(AVG(avg_time_in_stream_mins), 2)       AS avg_time_in_stream_mins,
        PERCENTILE_APPROX(total_unique_viewers, 0.50, 10000) AS p50_viewers_per_stream,
        PERCENTILE_APPROX(total_unique_viewers, 0.90, 10000) AS p90_viewers_per_stream,
        PERCENTILE_APPROX(event_duration_mins,  0.50, 10000) AS p50_duration_mins,
        PERCENTILE_APPROX(event_duration_mins,  0.90, 10000) AS p90_duration_mins,
        COUNT(DISTINCT CASE WHEN chats_sent_global > 0         THEN seller_id END) AS n_sellers_sent_chats,
        COUNT(DISTINCT CASE WHEN chats_pinned_global > 0       THEN seller_id END) AS n_sellers_pinned_chats,
        COUNT(DISTINCT CASE WHEN chats_bookmarked_global > 0   THEN seller_id END) AS n_sellers_bookmarked_chats,
        COUNT(DISTINCT CASE WHEN preset_chats_saved_global > 0 THEN seller_id END) AS n_sellers_saved_presets,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0          THEN seller_id END) AS n_sellers_quiz,
        COUNT(DISTINCT CASE WHEN poll_start_count > 0          THEN seller_id END) AS n_sellers_poll,
        COUNT(DISTINCT CASE WHEN notice_toggle_count > 0       THEN seller_id END) AS n_sellers_notice,
        COUNT(DISTINCT CASE WHEN quiz_start_count > 0 OR poll_start_count > 0
                                OR notice_toggle_count > 0 THEN seller_id END)     AS n_sellers_any_tool,
        SUM(quiz_start_count)                        AS total_quiz_starts,
        SUM(poll_start_count)                        AS total_poll_starts,
        SUM(notice_toggle_count)                     AS total_notice_toggles,
        SUM(stream_proxy_fired)                      AS n_streams_proxy_fired,
        COUNT(DISTINCT CASE WHEN total_items_pinned = 0 THEN live_event_id END)    AS n_streams_zero_pins,
        COUNT(DISTINCT CASE WHEN items_sold_during  = 0 THEN live_event_id END)    AS n_streams_zero_sales,
        SUM(add_listing_in_stream_count)             AS total_listings_added_in_stream,
        SUM(auction_reset_count)                     AS total_auction_resets,
        SUM(users_muted_global)                      AS total_users_muted
    FROM base
    GROUP BY geography, launch_phase, category, gmv_tier, onboarding_method, seller_background
)

SELECT * FROM daily
UNION ALL SELECT * FROM weekly
UNION ALL SELECT * FROM monthly
UNION ALL SELECT * FROM overall;
