# Visible chart window statistics

Approved: amount and percentage change follow the currently visible observations during pan, resize, pinch, date selection and reset. Add maximum/minimum visible prices directly on the chart.

Implemented a linear-time chronological endpoint/extrema calculation using finite positive raw prices, independent of logarithmic display. Fewer than two observations has no change/percentage; flat/single-point extrema share one badge. Summary sits above the chart (red up, green down, neutral flat) and moves onto its own row when the caption plus summary cannot fit. Extrema markers and 26pt badges stay within the plot, separate at edges, and yield to the inspection tooltip during single-finger lookup. Labels do not intercept gestures.

Validation: 106 simulator tests passed (`sumly_ios/build/window-stats-final.log`). Includes unordered observations, out-of-window exclusion through model, empty/single/flat/invalid data, drag/resize/reset, logarithmic invariance and edge label separation. Existing performance workload remained 0.030 seconds. Independent review found no remaining blockers.

Native Simulator: full month displayed -73.13 CNY/g (-7.62%); resize displayed -39.59 (-4.27%); translation displayed -22.82 (-2.38%) and minimum changed to 930.32. Both summary and markers followed the visible range. Snapshot prices are from the test session and are not fixed references.

Release target 0.1.1 (9). Client-only; backend unchanged.

Released: implementation `28f0d6a` pushed to origin/main. Production archive 0.1.1 (9), com.oryjk.sumly. App Store Connect upload succeeded at 2026-09-29 19:12:17 +0800 (`build/upload-b9.log`, EXPORT SUCCEEDED), package processing pending. Screenshot: `sumly_ios/build/window-stats-pan.png`.

Follow-ups: fixed the summary to a separate row for every range (commit `7099703`); 0.1.1 (10) upload succeeded at 2026-09-29 19:21:22 +0800. Added dates beneath high/low prices using the same `pointLabel` formatting as chart inspection; enlarged badges to 40pt and separation to 46pt. Updated collision test first (red), then all 106 tests passed (`build/extrema-date-green.log`). Native Simulator verified readable price/date badges at both chart edges. Included in build 11 with the fixed summary row.

Build 11 release: implementation `825e5c6` pushed. Initial upload stopped progressing during analysis transmission and was interrupted; retry succeeded at 2026-09-29 19:28:39 +0800 (`build/upload-b11-retry.log`, EXPORT SUCCEEDED). 0.1.1 (11) is processing in App Store Connect.
