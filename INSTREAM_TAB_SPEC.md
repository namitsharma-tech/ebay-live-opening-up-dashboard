# In-Stream Tab — Replacement Spec

**Purpose:** This document tells the builder of a new `instream.html` exactly what to
implement, what JSON to provide, and which 5 lines in `index.html` to change so the
iframe drops in without touching any other tab.

---

## 1. Integration Approach

The in-stream tab content lives in one `<div>` in `index.html`. The tab-switching
mechanism (`showTab()`) only toggles the visibility of that div — it does not care what
is inside it. Replacing the content with an `<iframe>` is a one-div change.

### 1a. Change in `index.html` — only 5 edits

#### Edit 1 — Tab div content (lines 1023–1345)

Replace the entire inner content of the div with a single iframe:

```html
<div id="tab-instream" class="section" style="padding:0">
  <iframe
    src="instream.html"
    id="iframe-instream"
    style="width:100%;border:none;min-height:960px;display:block"
    scrolling="no">
  </iframe>
</div><!-- /in-stream -->
```

Optional: auto-resize the iframe height from the child page by adding this to
`instream.html` after all content renders:

```js
// inside instream.html — fires once after render
window.parent.document.getElementById('iframe-instream').style.height =
  document.body.scrollHeight + 'px';
```

#### Edit 2 — Remove `renderInStream()` call in `showTab()` (line 1585)

```js
// DELETE this line:
if (tab === 'instream') renderInStream();
```

#### Edit 3 — Remove `renderInStream()` call in grain-change handler (line 1598)

```js
// DELETE this line:
if (activeTab === 'instream') renderInStream();
```

#### Edit 4 — Remove `renderInStream()` call in filter-change handler (line 3057)

```js
// DELETE this line:
if (activeTab === 'instream') renderInStream();
```

#### Edit 5 — Remove `renderInStream()` call in second filter handler (line 3074)

```js
// DELETE this line:
if (activeTab === 'instream') renderInStream();
```

After these 5 edits, `index.html` no longer references anything inside the in-stream
tab. The `IS_DATA_*` arrays (lines 1901–2373), `IS_TREND` array (lines 2374–2537), and
`renderInStream()` function (lines 2854–3135) become dead code — they can be deleted for
a cleaner file but are not required for the iframe to work.

---

## 2. What `instream.html` Must Be

A **complete, standalone HTML page** — `<html>`, `<head>`, `<body>`. It loads its own
copy of ECharts from CDN, embeds its own JSON data in a `<script>` block, and renders
everything itself. Nothing from the parent page (CSS variables, JS globals, ECharts
instance) bleeds into it.

Minimum boilerplate:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <!-- copy relevant CSS from index.html or write fresh styles -->
  <script src="https://cdn.jsdelivr.net/npm/echarts@5/dist/echarts.min.js"></script>
</head>
<body>
  <!-- your sections here -->
  <script>
    // your JSON data + render logic here
  </script>
</body>
</html>
```

---

## 3. Tab Sections to Re-Implement

The current tab has five visual sections. The new HTML should implement all of them (or
redesign freely — the parent doesn't care about interior structure).

| Section | Current header text | KPI tile count |
|---------|--------------------|----|
| S1 | In-Stream — North Star & Volume | 8 tiles (2 rows × 4) |
| S2 | Inventory & Auction Activity | 11 tiles (3 rows: 4+4+3) |
| S3 | Viewer & Seller Engagement | 8 tiles (2 rows × 4) |
| S4 | Guardrail Metrics | 4 tiles |
| S5 | Trend Charts | 4 line charts |
| S6 | Metric Definitions | collapsible table |

---

## 4. KPI Tile IDs (element IDs the current render writes into)

The new HTML defines its own IDs — these are provided for reference in case you want
a compatible DOM for any shared tooling. Each tile has a value element and a note element
(`{id}-note` suffix for the sub-line).

### S1 — North Star & Volume

| Metric | Value ID | Note ID | Formula |
|--------|----------|---------|---------|
| GMV / Streaming Hour (North Star) | `is-gmv-hr` | `is-gmv-hr-note` | `SUM(gmv) / SUM(hrs)` |
| Total GMV During Stream | `is-gmv` | `is-gmv-note` | `SUM(gmv)` |
| # Streams | `is-streams` | `is-streams-note` | `SUM(streams)` |
| # Active Sellers | `is-sellers` | `is-sellers-note` | `SUM(sellers)` |
| Items Sold During Stream | `is-items-sold` | `is-items-sold-note` | `SUM(items_sold)` |
| Total Streaming Hours | `is-hrs` | `is-hrs-note` | `SUM(hrs)` |
| Avg Items Listed / Stream | `is-avg-items` | `is-avg-items-note` | `SUM(total_items) / SUM(streams)` |
| Sell-Through Rate (All Items) | `is-str` | `is-str-note` | `SUM(items_sold) / SUM(total_items) × 100` |

### S2 — Inventory & Auction Activity

| Metric | Value ID | Formula |
|--------|----------|---------|
| Avg Auction Items / Stream | `is-avg-auction-items` | `SUM(auction_items) / SUM(streams)` |
| % Auction Items of Listed | `is-auction-mix` | `SUM(auction_items) / SUM(total_items) × 100` |
| Auction Sell-Through Rate | `is-auction-str` | `SUM(auction_sold) / SUM(auction_items) × 100` |
| Avg BIN Items / Stream | `is-avg-bin-items` | `SUM(bin_items) / SUM(streams)` |
| BIN Sell-Through Rate | `is-bin-str` | `(SUM(items_sold) − SUM(auction_sold)) / SUM(bin_items) × 100` |
| % Streams with Bids | `is-pct-bids` | `SUM(streams_w_bids) / SUM(streams) × 100` |
| Total Unique Bidders | `is-bidders` | `SUM(bidders)` |
| Total Bids Placed | `is-total-bids` | `SUM(total_bids)` |
| Avg Bids / Bidding Item | `is-avg-bids` | `SUM(total_bids) / SUM(items_w_bids)` |
| Avg Bids / Stream-with-Bids | `is-avg-bids-stream` | `SUM(total_bids) / SUM(streams_w_bids)` |
| Bid Price Realization % | `is-bid-real` | `weighted avg of bid_price_real_pct by items_w_bids` |

### S3 — Viewer & Seller Engagement

| Metric | Value ID | Formula |
|--------|----------|---------|
| Avg Viewers / Stream | `is-viewers` | `SUM(total_viewers) / SUM(streams)` |
| Quality Viewer Rate | `is-qvr` | `SUM(quality_viewers) / SUM(total_viewers) × 100` |
| Bounce Rate | `is-bounce` | `SUM(bounced_viewers) / SUM(total_viewers) × 100` |
| Avg Watch Duration | `is-watch` | `SUM(watch_vw) / SUM(total_viewers)` — in seconds |
| % Sellers Sending Chat | `is-pct-chat` | `SUM(s_chat) / SUM(sellers) × 100` |
| % Sellers Pinning Chat | `is-pct-chat-pin` | `SUM(s_chatpin) / SUM(sellers) × 100` |
| % Sellers Using Notice | `is-pct-notice` | `SUM(s_notice) / SUM(sellers) × 100` |
| % Sellers Any Tool | `is-pct-any-tool` | `SUM(s_anytool) / SUM(sellers) × 100` |

### S4 — Guardrails

| Metric | Value ID | Formula |
|--------|----------|---------|
| % Zero-Sale Streams | `is-zero-sale` | `SUM(zero_sale) / SUM(streams) × 100` |
| Avg Listings Added In-Stream | `is-instream-list` | `SUM(sum_instream) / SUM(streams)` |
| Avg Auction Resets | `is-resets` | `SUM(sum_resets) / SUM(streams)` |
| Avg Users Muted | `is-muted` | `SUM(sum_muted) / SUM(streams)` |

### S5 — Trend Charts (ECharts div IDs)

| Chart | Div ID | Series |
|-------|--------|--------|
| GMV / Streaming Hour trend | `ch-is-gmv-hr` | `gmv_per_hr` from IS_TREND |
| Daily Streams & Active Sellers | `ch-is-volume` | `streams`, `sellers` from IS_TREND |
| Avg Viewers & Quality Viewer Rate | `ch-is-viewers` | `viewers`, `qvr` from IS_TREND |
| Sell-Through Rate % | `ch-is-str` | `str_pct` from IS_TREND |

---

## 5. JSON Data Formats

### 5a. IS_DATA (filter-reactive KPI data)

One array per grain: **Overall, Monthly, Weekly, Daily**. Each row is one
`(geo × phase × cat × tier × method × bg)` combination — i.e. all metrics are
pre-aggregated to that dimension intersection. KPI tiles compute aggregates by
`SUM`-ing over filtered rows (never `AVG` of rates).

```jsonc
// One row example:
{
  // Dimension keys (used by filter dropdowns)
  "geo":    "US",                        // Geography: "US" | "UK" | "DE" | "CA"
  "phase":  "Rest",                      // Launch phase string
  "cat":    "Coins & Bullion",           // Category name
  "tier":   "T2",                        // Seller tier: "T1" | "T2" | "T3"
  "method": "BD_Onboarded",             // Onboarding method string
  "bg":     "Existing_Live",            // Seller background string

  // Volume
  "streams":   90,          // COUNT(DISTINCT live_event_id)
  "sellers":   29,          // COUNT(DISTINCT seller_id)
  "gmv":       834105.0,    // SUM(gmv_during) — USD
  "items_sold":12269.0,     // SUM(items_sold_during) — DDI source
  "hrs":       369.8,       // SUM(event_duration_mins) / 60

  // Inventory
  "total_items":   12391,   // SUM(total_items_listed)
  "auction_items": 12387,   // SUM(total_auction_items)
  "bin_items":     4,       // SUM(total_bin_items)
  "pinned":        0,       // SUM(total_items_pinned) — CDC unreliable, excluded

  // Sell-through
  "auction_sold":  13270,   // SUM(auction_items_sold)
  "pinned_sold":   0,       // SUM(pinned_items_sold_during) — CDC proxy, excluded

  // Viewer engagement
  "total_viewers":   90944, // SUM(total_unique_viewers) — HC_STREAM_METRICS (not DDI)
  "quality_viewers": 31785, // SUM(quality_viewers)
  "bounced_viewers": 47258, // SUM(bounced_viewers)
  "watch_vw":        37334, // SUM(avg_watch_duration_secs × total_unique_viewers)
                             // — denominator for watch-per-viewer calc

  // Seller tool adoption (UBI-derived, 3–5 day lag)
  "s_chat":    7,   // COUNT(DISTINCT sellers) where chats_sent_global > 0
  "s_chatpin": 9,   // COUNT(DISTINCT sellers) where chats_pinned_global > 0
  "s_notice":  6,   // COUNT(DISTINCT sellers) where notice_toggle_count > 0
  "s_anytool": 10,  // COUNT(DISTINCT sellers) where any tool > 0

  // Guardrails
  "zero_sale":    0,    // COUNT(DISTINCT live_event_id) where items_sold = 0
  "sum_instream": 0,    // SUM(add_listing_in_stream_count) — UBI lag
  "sum_resets":   0,    // SUM(auction_reset_count) — UBI lag
  "sum_muted":    2,    // SUM(users_muted_global) — directional

  // Bid engagement
  "total_bids":     102444, // SUM(total_bids)
  "bidders":        9583,   // SUM(unique_bidders)
  "items_w_bids":   13270,  // SUM(auction_items_with_bids)
  "streams_w_bids": 90,     // COUNT(DISTINCT live_event_id) where total_bids > 0

  // Bid price realization — weighted avg requires special handling:
  // compute as SUM(bid_price_real_pct × items_w_bids) / SUM(items_w_bids)
  "bid_price_real_pct": 7735.3
}
```

#### Aggregation rules (critical)

| Metric | Correct rollup |
|--------|---------------|
| GMV / Streaming Hour | `SUM(gmv) / SUM(hrs)` — never `AVG(gmv/hrs)` |
| Sell-Through Rate | `SUM(items_sold) / SUM(total_items) × 100` |
| Quality Viewer Rate | `SUM(quality_viewers) / SUM(total_viewers) × 100` |
| Bounce Rate | `SUM(bounced_viewers) / SUM(total_viewers) × 100` |
| Avg Watch Duration | `SUM(watch_vw) / SUM(total_viewers)` |
| % Sellers Chat/Notice/Tool | `SUM(s_chat) / SUM(sellers) × 100` |
| Auction STR | `SUM(auction_sold) / SUM(auction_items) × 100` |
| BIN STR | `(SUM(items_sold) − SUM(auction_sold)) / SUM(bin_items) × 100` |
| Bid Price Realization | `SUM(bid_price_real_pct × items_w_bids) / SUM(items_w_bids)` |

### 5b. IS_TREND (30-day daily trend for line charts)

One entry per calendar day, ordered ascending. Used only by the 4 trend charts — not
affected by filter dropdowns.

```jsonc
// One row example:
{
  "dt":         "Jul-19",  // display label (x-axis)
  "streams":    831,        // total streams that day
  "sellers":    633,        // distinct sellers that day
  "gmv":        3687459,    // total GMV during streams
  "gmv_per_hr": 1211.67,   // SUM(gmv) / SUM(hrs) recomputed
  "str_pct":    46.1,       // SUM(items_sold) / SUM(total_items) × 100 — DDI-based
  "viewers":    1083,       // avg viewers per stream (SUM(viewers) / streams)
  "qvr":        26.4,       // quality viewer rate %
  "watch_secs": 390         // avg watch duration in seconds
}
```

Current IS_TREND covers **Jun 19 – Jul 19 2026** (31 days). The new HTML should embed a
fresh IS_TREND array covering the latest available date range (2-day lag from
HC_STREAM_METRICS for stream metrics; DDI for STR and GMV).

---

## 6. Filter Dimensions

The parent page has global filter dropdowns (Geo, Phase, Category, Tier, Method,
Background) that currently call `renderInStream()` on change. After the iframe swap,
those dropdowns no longer affect the in-stream tab.

**Options:**
- **Ignore parent filters** — the iframe implements its own filter UI internally.
  Simplest. Recommended.
- **Receive filter via postMessage** — parent sends `{type:'filter', geo:'US', ...}` and
  iframe listens with `window.addEventListener('message', ...)`. More complex but keeps
  consistent filter state across tabs.

If implementing internal filters, the dimension values present in IS_DATA are:

| Dimension | Key | Example values |
|-----------|-----|---------------|
| Geography | `geo` | `US`, `UK`, `DE`, `CA` |
| Launch phase | `phase` | `Rest` (others may appear as data grows) |
| Category | `cat` | `Coins & Bullion`, `Apparel`, `Comic Books & Memorabilia`, … |
| Seller tier | `tier` | `T1`, `T2`, `T3` |
| Onboarding method | `method` | `BD_Onboarded`, `ExistingSellers - UnknownSource`, … |
| Seller background | `bg` | `Existing_Live`, `Core_to_Live` |

---

## 7. Grain System

The parent has a grain toggle: **Overall / Monthly / Weekly / Daily**. Each maps to a
different pre-aggregated IS_DATA array. The labels for each grain:

| Grain | Label (shown in note sub-line) |
|-------|-------------------------------|
| Overall | All-time · Apr 20 – Jul 18 2026 |
| Monthly | Jul 2026 MTD · Jul 1–18 |
| Weekly | Week of Jul 12–18 2026 |
| Daily | Jul 18 2026 · latest available (4-day lag) |

> Note: UBI-derived tool metrics (`s_chat`, `s_chatpin`, `s_notice`, `s_anytool`,
> `sum_instream`, `sum_resets`, `sum_muted`) show "—" in Daily grain because
> HC_UBI_BASE has a 3–5 day lag. Set these to `null` in IS_DATA_DAILY rows.

---

## 8. Source Tables & Data Caveats

| Metric group | Source table | Notes |
|---|---|---|
| GMV, items sold, STR, streams, sellers, hrs | `LIVE_COMMERCE_DAILY_DEMAND_INDICATORS` (DDI) | Gold standard for these fields |
| Viewers, watch duration, auction/bid metrics | `P_LIVE_ANALYTICS_T.HC_STREAM_METRICS` | Do NOT use DDI VIEWERCOUNT — inflated 3–4× |
| Tool adoption (chat, notice, quiz, poll) | `HC_STREAM_METRICS` via CHATBC / LIVECOMM joins | 3–5 day UBI lag; show "—" for Daily grain |
| Trend line (IS_TREND) | DDI for gmv/str/streams/sellers; HC_STREAM_METRICS for viewers/watch_secs | 2-day lag on HC table |

**Known exclusions (do not display):**
- **Pin Rate** — `total_items_pinned` = 0 for all rows (column not populated in HC_STREAM_METRICS as of Jul 2026). CDC LEL also overwrites pin=TRUE after stream ends — unreliable.
- **Stream Proxy / Activation Failure** — `stream_proxy_fired` = 0 for all rows (not implemented).
- **Auction STR > 100%** — happens when same item is relisted within a stream; treat as "high sell-activity" signal only, not a true rate.
- **Insights page metrics** — no UBI page-event source; not in scope for in-stream tab.

---

## 9. Files in This Repo

| File | Purpose |
|------|---------|
| `index.html` | Main dashboard — 5 lines to edit per Section 1a above |
| `instream.html` | **New file to create** — full standalone page |
| `instream_metrics.sql` | Source SQL for HC_STREAM_METRICS (v2) — reference for column names |
| `INSTREAM_TAB_SPEC.md` | This document |

---

## 10. Checklist for the New `instream.html`

- [ ] Standalone HTML page with own `<head>`, ECharts CDN, and CSS
- [ ] IS_DATA_ALL, IS_DATA_MONTHLY, IS_DATA_WEEKLY, IS_DATA_DAILY arrays embedded as JSON
- [ ] IS_TREND array (Jun 19 – latest date) embedded as JSON
- [ ] Filter UI (internal dropdowns or postMessage from parent)
- [ ] Grain toggle (Overall / Monthly / Weekly / Daily)
- [ ] S1: 8 KPI tiles — GMV/hr, GMV, streams, sellers, items_sold, hrs, avg_items, STR
- [ ] S2: 11 KPI tiles — auction/BIN inventory + bid engagement
- [ ] S3: 8 KPI tiles — viewer engagement + seller tool adoption
- [ ] S4: 4 guardrail tiles — zero-sale %, instream listings, resets, muted
- [ ] S5: 4 ECharts line charts from IS_TREND
- [ ] S6: metric definitions table (collapsible)
- [ ] Post-render height message to parent (optional): `window.parent.document.getElementById('iframe-instream').style.height = document.body.scrollHeight + 'px'`
- [ ] No "—" hardcoded — show "—" only when computed value is null/zero-denominator
