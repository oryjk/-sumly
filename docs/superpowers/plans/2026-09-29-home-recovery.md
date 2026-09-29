# Homepage foreground recovery

## Report and investigation

The user reported an empty realtime chart stuck on “正在加载走势…” after leaving and returning to the app, while a quote remained visible.

Production probes returned a valid quote, 246 realtime points, and 5308 sync records. A simulator cold launch and foreground transition showed normal task cancellation/restart; instrumentation did not establish a SwiftUI conditional-view lifecycle failure and was removed. The precise network conditions on the user's phone were not captured.

Two deterministic failures were reproduced in the existing model:

- A pending daily sync kept the shared loading state active after realtime failed and prevented the five-second realtime retry loop from starting.
- A successful but empty realtime response erased an already visible curve without exposing a refresh failure.

## Changes

- Quote, realtime and daily/history polling run in separate structured child tasks, all cancelled when the scene task stops.
- Loading state follows the relevant stream, and background refreshes with usable data do not replace the current status with an initial-loading message.
- Per-request identifiers reject late results from superseded requests and prevent an old cancellation from clearing the new request's loading state.
- Empty or unusable realtime responses preserve the last curve and expose the existing retry message.
- The chart's loading placeholder depends on chart requests rather than an unrelated quote/history request.

## Verification

Regression coverage: slow daily sync plus transient realtime failure and automatic recovery; empty realtime refresh preserving the curve; out-of-order refresh responses; cancelled scene task completing after a new foreground task starts.

Delivery target: iOS 0.1.1 (12). No backend or database change.

Validation completed: 110 Swift Testing tests passed (`sumly_ios/build/home-recovery-b12-tests.log`); device Release archive succeeded with CFBundleVersion 12. Simulator foreground recovery retained 241 points and resumed quote/chart updates. Independent code review reported no actionable issues. Existing history-only in-flight cancellation guard remains unchanged and does not gate realtime recovery.
