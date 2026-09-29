# Bounded chart ranges

User-approved design: each selected period is a hard limit for chart points, pinch, navigation handles/window and exact date selection. Add YTD and trailing 1/2/3/5/10 years alongside realtime, month, quarter and full history. Replace horizontal range buttons with a full-width native menu picker; retain clear linear/log and reset controls.

Implemented calendar ranges ending yesterday, reusable normalized data plus cached per-range slices, shared bounded chart/navigator/date domains, single-day clamps, and January 1 YTD empty state with no chart/date controls. Reset restores the entire selected range and preserves the price scale.

Validation: 102 simulator tests passed, including all historical ranges under extreme zoom/drag/date requests, leap-year/YTD dates, and singleton domains. Performance workload remained 0.030 seconds for 20 repeated viewport reads. Logs: `sumly_ios/build/range-bounds-final.log`.

Native Simulator: all 10 menu options displayed with selected checkmark; month overview limited to 2026-08-28…2026-09-28. After resizing then a large leftward drag, the window stopped at 2026-08-28. YTD displayed 2026-01-01…2026-09-28 and 191 points. Independent review identified January 1 fallback; fixed with empty UI and an inert current-year domain.

Release target: 0.1.1 (8). Client-only change; backend unchanged.

Release complete: implementation `8c137f8` pushed to origin/main. App Store Connect upload of 0.1.1 (8), com.oryjk.sumly, succeeded at 2026-09-29 18:48:30 +0800 (`build/upload-b8.log`, EXPORT SUCCEEDED). Apple processing pending. UI screenshot: `sumly_ios/build/range-bounds-ytd.png`.
