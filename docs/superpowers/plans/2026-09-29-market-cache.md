# Market cache and logarithmic chart implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement task by task.

**Goal:** Persist historical prices once, collect daily changes independently of reads, cache and incrementally synchronize iOS prices, offer cache clearing and logarithmic chart display.
**Architecture:** PostgreSQL keeps canonical annual/daily prices and a transactionally ordered projection of latest changes (including tombstones). Clients atomically persist records with a cursor; database epoch changes reset the cache. Real-time prices remain separate.
**Tech Stack:** Go 1.26.5, PostgreSQL/sqlc, Swift 6, SwiftUI/Charts iOS 17+.
**Spec:** User-approved design in this conversation: initial historical import, daily updates, cursor-based corrections, local cache clear preserving holdings/auth, linear/log switch default linear. User explicitly requested implementation after approval.

## Global constraints
- Retain 1900–2015 annual reference data and 2016+ daily history; never manufacture non-trading days.
- Queries must not fetch upstream daily history; scheduled daily job persists completion and retries failures.
- Upstream Sina currently exposes full history; local DB writes and app synchronization are incremental even when upstream payload cannot be narrowed.
- Cache only public market data, scoped by API origin and instrument; no changes to holdings/auth storage.
- Clear invalidates concurrent loads; malformed or cancelled sync cannot advance cursor.
- Linear/log changes only vertical plotting coordinates, preserves raw tooltip prices and horizontal gestures.

## Review focus
- Old-year corrections/deletions arrive after latest trading date.
- Concurrent database writes cannot create cursor gaps.
- Clearing while network response is pending cannot resurrect cache.
- Offline/corrupt local cache behavior does not erase valid data or holdings.
- Log axis handles empty, constant, non-positive and very wide prices.

### Task 1: Persistence and sync protocol
Files: migration 00006, db/queries/market.sql, market/{domain,ports,adapters/postgres,adapters/http}/sync.go, bootstrap.
Interface: GET /market/gold/sync?series=xauusd|au9999|comex-gold&cursor=epoch:revision returns series/unit/cursor/reset/points (date, granularity, OHLC, source, deleted).
- [x] Write/run failing DB tests for snapshot/delta/no-op/correction/deletion/reset and one-time annual import.
- [x] Add transactional counter, projection triggers, seed metadata, sync queries and handler validation.
- [x] Run DB/API tests; verify canonical annual history comes from DB.

### Task 2: Daily collection
Files: application/gold_market.go, application/history.go, postgres/sync.go and queries.
Interface: SyncDaily(ctx) scheduled once per UTC day after 08:00 UTC; persisted lease prevents duplicate collectors; failures retry after 15 minutes.
- [x] Write/run tests proving read-only daily queries and durable daily lease behavior.
- [x] Separate fetch from read; reject invalid bars, exclude current UTC trading date; persist only new/changed rows.
- [x] Verify restore, stale source, retry and recent-data corrections.

### Task 3: iOS cache
Files: GoldMarket/MarketHistoryCache.swift, MarketSyncService.swift, BackendGoldPriceService.swift; Home ViewModel and AccountView.
Interface: actor cache load/sync/clear; atomic JSON snapshots in app caches directory; shared generation invalidates pending responses and UI.
- [x] Write/run tests for persist/reopen, deltas/deletions, corruption, clear during fetch, origin isolation.
- [x] Show cached data before sync, coalesce sync calls; use incremental service for daily and history.
- [x] Add 清除行情缓存 to 我的 and invalidate in-memory chart data; preserve holdings and login.

### Task 4: Log display and verification
Files: Features/Home/ChartPriceScale.swift and HomeView.swift, Tests/ChartPriceScaleTests.swift, docs/openapi.yaml.
- [x] Write/run tests for equal ratio spacing and valid empty/constant domains.
- [x] Add 线性/对数 button, default linear, retain raw tooltip prices and gesture behavior.
- [x] Run full Go tests with explicit TEST_DATABASE_URL, vet/build; iOS simulator tests/build and visual QA.
- [x] Request independent review and fix substantive findings. No deploy/upload unless requested.

## Execution notes
- Continue in current checkout per established session preference; do not touch existing .build output.
- No additional design approval: user approved design and explicitly said 开始实现吧.

- Review fix: caller cancellation now cancels shared download synchronously; remaining callers retry, and cache clearing changes generation so it never retries a pre-clear operation. Regression failed with three assertions before fix.
- Real-source verification: 132 Sina historical bars have inconsistent OHLC bounds, but finite positive closes. Preserve source fields; reject invalid dates/nonfinite/nonpositive values instead of discarding usable closes or fabricating corrected highs/lows. Regressions failed in both Go and Swift before fix.

Verification: full Go suite with explicit isolated TEST_DATABASE_URL passed; go vet/build passed; iOS 90 tests passed. Native simulator QA verified 2,901 history points, linear/log switching, cache clear feedback + directory removal, re-download, and offline relaunch with cached quote/history. No deployment/upload or push performed.
