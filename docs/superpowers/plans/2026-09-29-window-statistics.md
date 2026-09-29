# Visible chart window statistics

Approved: amount and percentage change follow the currently visible observations during pan, resize, pinch, date selection and reset. Add maximum/minimum visible prices directly on the chart.

Implemented a linear-time chronological endpoint/extrema calculation using finite positive raw prices, independent of logarithmic display. Fewer than two observations has no change/percentage; flat/single-point extrema share one badge. Summary sits above the chart (red up, green down, neutral flat) and moves onto its own row when the caption plus summary cannot fit. Extrema markers and 26pt badges stay within the plot, separate at edges, and yield to the inspection tooltip during single-finger lookup. Labels do not intercept gestures.

Validation: 106 simulator tests passed (`sumly_ios/build/window-stats-final.log`). Includes unordered observations, out-of-window exclusion through model, empty/single/flat/invalid data, drag/resize/reset, logarithmic invariance and edge label separation. Existing performance workload remained 0.030 seconds. Independent review found no remaining blockers.

Native Simulator: full month displayed -73.13 CNY/g (-7.62%); resize displayed -39.59 (-4.27%); translation displayed -22.82 (-2.38%) and minimum changed to 930.32. Both summary and markers followed the visible range. Snapshot prices are from the test session and are not fixed references.

Release target 0.1.1 (9). Client-only; backend unchanged.
