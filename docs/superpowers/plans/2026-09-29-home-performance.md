# Home chart switching performance

Problem: changing to monthly history blocked the main actor while computed view properties repeatedly normalized, converted and sorted every historical record. `points` was traversed indirectly through bounds, viewport, labels, counts and axes on every render.

Reproduction: 5,308 synthetic history records; 20 repetitions of visible points, window count, axis dates, full domain and reset availability. Before: 8.4795 seconds, failing 500ms regression budget. After: 0.0498 seconds in the same simulator test (about 170x faster for this calculation workload, not an end-to-end frame-rate claim).

Fix: memoize prepared history by observable source revision, FX, closed-day cutoff and timezone. Clear derived storage with cache clearing. Identical fetched data does not advance the revision. Source price corrections and FX changes invalidate the prepared result. A cache fill is not itself an observable mutation.

Validation: all 99 simulator tests passed (`sumly_ios/build/home-performance-final.log`). Includes source corrections, FX changes and clearing cached values. Native Simulator exercised realtime → month → quarter → month; selected buttons and displayed date ranges/point counts matched. Physical-device latency still requires testing on the uploaded build.

Independent review caught a fallback-daily observation dependency and a same-current-offset timezone cache collision; fixed using observable revision and timezone identity in the key.

Release target: 0.1.1 (7). Backend unchanged; no deployment/migration needed for this client calculation fix.
