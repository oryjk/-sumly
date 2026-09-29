# Gold history and interactive home chart — 2026-09-29

## Scope

The home chart supports two-finger pinch zoom and two-finger panning in the selected time range. One-finger tap/drag inspects prices. Double tap or Reset restores the range. The new range is 1900 to the latest available quote. Existing realtime, monthly and quarterly presets remain.

The backend adds public `GET /api/v1/app/market/gold/history`; existing daily/realtime contracts are unchanged. It returns nominal USD/troy-ounce observations with date, price, granularity and source. 1900–2015 has exactly 116 annual USGS DS140 references. 2016 onward uses existing stored/upstream daily closes without synthesizing weekends or missing days. The source adapter README contains the workbook URL, SHA-256, extraction column, conversion and methodology. Historical points are deliberately not inserted into the daily OHLC tables. No database migration is needed for this feature.

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
