# Native auth coordinator review notes

Scope: final review of the implementation plan `2026-09-29-native-auth.md`. This is a checklist, not evidence that tests passed.

## Integration concerns identified while workers implement

- Existing API root is `BackendGoldPriceService.defaultBaseURL`, default `https://oryjk.cn/sumly/api/v1`; auth paths must append `app/auth/...`, not duplicate `/api/v1` or drop `/sumly`. Existing Info.plist override permits development HTTP. New authentication transport must require HTTPS in release; debug may permit loopback/local developer overrides intentionally, never silently send production passwords to a plain-HTTP remote host.
- Existing `PrivacyInfo.xcprivacy` has empty `NSPrivacyCollectedDataTypes`. Native auth sends identity information to backend; audit final implementation and add appropriate linked-to-user, nontracking, app-functionality declarations for name (only if sent), email, phone and user ID. Do not falsely claim financial holdings collection: holdings stay local. App Store Connect privacy disclosures and published privacy policy are operator setup, not automatically changed by source manifest.
- Existing user DB uses nullable avatar_url. New native `NativeUser` contract says avatar_url string: ensure DTO emits empty string if absent, not JSON null that crashes Swift decoding.
- Password length semantics must match across Go and Swift. Swift String.count counts extended grapheme clusters, whereas Go utf8.RuneCountInString counts Unicode scalars; use the same scalar convention, and enforce byte limit too. Do not trim passwords.
- `DELETE /auth/account` requires recent primary login, not just a freshly refreshed session. iOS reauthentication flow must return to the deletion context, not accidentally switch to a different account and delete it. Confirmation includes retained local guest holdings disclosure.
- Keychain failures (locked device/write failure) must be handled explicitly; a successful request must not be presented as a durable session unless persistence succeeds. Authentication callbacks after logout must not restore credentials.
- A failed SMS/email send must not leave an active OTP. Mark ready only after success, or clean up/revoke failures without weakening cooldown/abuse quotas. No actual delivery tests in this session.
- Apple account deletion must not forget encrypted provider token before successful revocation/retry handling. Never combine accounts on email equality.
- New JWT native marker/session check must not fall back to legacy validation after refresh/logout/reset revokes the native sid. All existing authenticated app routes need to enforce native revocation too.

## Early concrete review observations (recheck final code before fixing)
- `AuthSession.clearLocal()` currently clears memory but only reports a Keychain deletion failure. If deletion fails and remote logout is offline, a subsequent launch can restore the old Keychain credential. Add a regression for failed Keychain removal plus relaunch, and persist a nonsecret logout marker or equivalent fail-closed mechanism so local logout cannot resurrect.
- `AuthSession.currentUser()` currently retries `me` after refresh and returns that result without a post-await generation check (first request does check). Recheck final implementation and cover logout/account switch during the retry.
- Password scalar counting and HTTPS error are already present in AuthModels; verify them in actual networking and tests, not just declarations.
- Backend `NativeStore.Rotate` replaces session ID and refresh hash by deleting old row, while `Logout` looks up only the supplied refresh hash. A concurrent refresh that wins before logout can leave the newly rotated session active because logout with the previous refresh is a successful no-op. Recheck final implementation and add a race regression; consider a revocable session family or short-lived previous-token lookup rather than silently claiming server logout succeeded.

## Evidence still required
- [ ] Backend full test/race/vet/build with exact outcomes.
- [ ] PostgreSQL integration tests actually run using explicit test URL and isolated schemas; list skips if inaccessible.
- [ ] iOS full test/build, actual test count, simulator UI inspection.
- [ ] Exact cross-platform API contract comparison (all verbs, paths, DTO names/nullability and failure behavior).
- [ ] Independent review findings fixed or clearly recorded.
- [ ] Git diff --check, no secrets/unrelated changes, no manual generated project files.

## Sources
- Apple data categories: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
- Apple private relay email setup (only if sending email to Apple relay identities): https://developer.apple.com/help/account/capabilities/configure-private-email-relay-service

## External live prerequisites (not completed by code-only work)
- Apple App ID Sign in with Apple capability, matching bundle ID/client ID, Team ID, Key ID and securely configured .p8 private key; real-device consent/cancellation/hide-email/delete test.
- Approved Aliyun SMS signature and verification template, least-privilege credentials and budget/rate alarms. Initial phone region is +86 only.
- Authenticated TLS SMTP credentials/from address and deliverability setup; real mailbox registration/reset test.
- New migration applied during a separately authorized backend deployment; update client to matching backend. No production migration/deployment/push is authorized by this implementation request alone.
