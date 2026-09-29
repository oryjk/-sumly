# Gold history and interactive home chart — 2026-09-29

## Scope

The home chart supports two-finger pinch zoom and two-finger panning in the selected time range. One-finger tap/drag inspects prices. Double tap or Reset restores the range. The new range is 1900 to the latest available quote. Existing realtime, monthly and quarterly presets remain.

The backend adds public `GET /api/v1/app/market/gold/history`; existing daily/realtime contracts are unchanged. It returns nominal USD/troy-ounce observations with date, price, granularity and source. 1900–2015 has exactly 116 annual USGS DS140 references. 2016 onward uses database-backed daily closes without synthesizing weekends or missing days. The source adapter README contains the workbook URL, SHA-256, extraction column, conversion and methodology. Annual references live in the canonical market history table, separately from daily bars. Migration 00006 adds the revisioned sync projection, tombstones, import marker and durable daily collection schedule. Annual seed OHLC fields are equal to the annual reference solely for the shared transport format; they do not represent a daily trading range.

The app converts nominal prices using current FX and labels this explicitly. An annual point is represented at July 1 for chart placement, and its callout shows only its year and annual meaning. The source explanation distinguishes USGS world/Engelhard averages from Sina London daily closes. Today's live quote is labeled separately.

## Verification

- Full Go suite passed with explicit TEST_DATABASE_URL and isolated temporary schemas, including earlier authentication regressions.
- `go vet ./...`, API build, OpenAPI validation and `git diff --check` passed.
- iOS simulator suite: 81 tests passed. New regressions first reproduced annual single-point selection dead zones and stale realtime viewport drift, then passed after fixes.
- Final simulator build passed after adjusting axis endpoints to avoid clipped year labels.
- Simulator visual inspection used an isolated, read-only local preview of actual public daily/realtime data and the checked-in USGS annual data. Only a copied simulator artifact had a localhost URL override; project configuration and production base URL were unchanged.
- Verified historical range renders 2,901 observations in the preview, single-touch annual price callout works, and the source explanation is readable. Actual two-finger physical-device gesture testing remains for device acceptance; viewport math is covered by automated tests.

## Release status

These changes have not yet been deployed to jd or uploaded to TestFlight. The previously uploaded 0.1.1 (4) contains Apple login but does not contain this chart change. Release the backend history endpoint before distributing the new iOS build. Existing Apple key configuration and database migrations from the earlier deployment are unchanged.

## Incremental caching update

- `GET /api/v1/app/market/gold/sync?series=xauusd&cursor=...` returns a full snapshot initially, then only changed records. Supported series are xauusd, au9999 and comex-gold; each cursor is bound to series and database epoch. `reset` tells the client when to replace rather than merge. Keys are `(granularity,date)`; tombstones remove records.
- PostgreSQL uses a transactional counter and repeatable-read snapshots, rather than a bare sequence, so concurrent commits cannot skip an earlier update. Only the most recent version of each record is retained; that is sufficient for every older cursor to catch up.
- Annual CSV is an initial import artifact. A transactional seed marker prevents re-import on restart and preserves manual database corrections. Update annual rows (or mark `deleted=true`) in `market_history_points`; update/delete daily rows in `gold_daily_bars` so its trigger publishes changes. Do not physically delete annual projection records; clients need tombstones.
- Daily query handlers only read the database. Collectors share a per-symbol persistent lease; collection runs once per schedule day (boundary 08:00 UTC), retries failures after 15 minutes, and resumes after a restart. The scheduler checks every minute. Current UTC-date bars are excluded as provisional; live quotes provide today's value. Existing provisional bars are discarded once by migration 00006.
- Sina provides a full-history endpoint, so the backend still downloads its source response once per day. It compares actual OHLC values, writes only new/corrected rows, preserves unavailable old dates and publishes only changes. Other providers retain their existing source coverage.
- iOS caches original currency values in `Caches/SumlyMarketHistory`, isolated by API URL and series. One atomic JSON file contains records and cursor. It displays disk data before syncing, coalesces concurrent calls and checks deltas at most once every 15 minutes. OS cache eviction/corruption results in a new snapshot. Last quote/FX is cached separately with its original timestamp for offline viewing; realtime polling remains live.
- 我的 → 清除行情缓存 deletes this dedicated directory and invalidates pending cache writes and chart buffers. It never opens or deletes the SwiftData holdings store or Keychain. Subsequent viewing downloads a fresh snapshot.
- The chart's 线性/对数 button defaults to linear and transforms only vertical plotting coordinates. Tooltips retain original CNY/gram prices and annual/daily meaning, and horizontal gestures are unchanged.

Release requires migration 00006 and deployment of `/market/gold/sync` before the next iOS build. No new deployment or TestFlight upload was performed for this update.

Verification for incremental update: complete Go suite (explicit test database), vet and API build passed. iOS 90 tests passed, including cancellation and real-source OHLC regressions. Simulator QA verified clear removes the dedicated cache directory, subsequent viewing re-downloads, and an offline relaunch still displays the 2,901-point history and last quote with an explicit refresh-failure message.
