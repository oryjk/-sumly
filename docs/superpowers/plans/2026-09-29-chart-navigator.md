# Chart navigator and day-level viewport

Approved in conversation: visible linear/log control and fixed reset, overview with draggable selected range/endpoints, exact date selection, presets as initial windows across historical domain. New constraint: every non-realtime viewport and axis is day-aligned; realtime retains seconds. Annual records keep their provenance and no daily values are fabricated.

- [x] Add calendar-based day alignment and navigation math; verify DST, endpoint clamp, fixed-span translation.
- [x] Share all historical data across non-realtime presets, separate preset domain from global bounds, exclude today and realtime quotes from historical series; snap window endpoints to noon, provide daily axis values.
- [x] Build responsive toolbar, overview with enlarged narrow selection touch target, date picker and point count. Preserve gestures and use GoldTheme.
- [x] Run full simulator tests, visual QA and independent review, fix regressions.
- [ ] Increment build to 6, commit/push, archive/upload. No backend code change anticipated; verify deployed endpoints and redeploy only if changed.

Tests initially fail on missing dayAligned/navigate and navigator model methods. Existing monthly point-count assertions will use points within the visible window, since points now deliberately retain off-screen history.

User refinement: every non-realtime mode ends yesterday; show only existing closed observations, no today quote and no synthetic weekend bars. The header quote and realtime chart retain live updates.

Review fixes: a single yesterday point pads bounds backward rather than into today (regression red); realtime navigator limits its minimum span to available bounds (regression red). Navigator uses GestureState reset + scene lifecycle to release cancelled gestures even when onEnded is not called.

Validation (2026-09-29): 97 simulator tests passed (`build/navigator-final-test.log`). Native Simulator verified endpoint resizing (241 → 122 realtime points), fixed-span translation, reset (241 points), monthly navigation to 2020-12-31…2021-01-31, and date-sheet presentation. Screenshot: `sumly_ios/build/navigator-month-pan.png`. Final gesture translation is applied in onEnded as well as onChanged; automated native drags may deliver their only nonzero translation at the end. Real-device two-finger handling still needs device QA.

Backend unchanged: public health and XAUUSD sync both HTTP 200; sync contains 5,308 records. Existing backend deployment retained. No database backup or migration in this change.
