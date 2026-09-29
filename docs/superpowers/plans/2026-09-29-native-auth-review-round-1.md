# Native auth independent review — round 1

Reviewer: agt_12ddf09d, read-only review of tracked/untracked working files against base 8ecb630. No critical issue confirmed; important items below require fixes/regression evidence. Findings were recorded while workers finished, so recheck actual current code for already addressed items.

## Backend: shared Apple throttle (Important)
`sumly_go/internal/auth/application/native_accounts.go` applies an account/subject 20-per-hour quota using constant identifiers `apple-challenge` and `apple-login`. A single caller can exhaust an application-wide allowance and prevent unrelated users signing in. Use per-caller/IP throttles before identity verification, plus an independently sized/configured global abuse quota, never a constant pretending to be one user's subject. Add regression: exhausting one caller does not block a second caller's Apple challenge/login; retain per-caller and genuine global abuse protection.

## iOS: account deletion must bind the intended identity (Important)
`AccountView` opens the normal login sheet for deletion reauthentication; `AuthSession.login` replaces the account without checking expected user ID. Starting deletion of A then signing in as B silently changes the account whose next confirmation will delete. Preserve intended account ID/provider, restrict or validate reauth, reject a different returned ID BEFORE replacing stored credentials, revoke the unused new B session if needed, and identify the intended masked account in the confirmation. No automatic delete after reauth; a fresh explicit confirmation remains required. Tests: A→B fails and retains A, A→A succeeds, identity switch cannot carry pending deletion intent.

## iOS: login cancellation must not invalidate established refresh (Important)
`AuthFormModel.cancel` calls `cancelPendingLogin`, which increments the shared generation/cancels refresh; login startup also invalidates established refresh before its authentication outcome is known. If server commits a refresh rotation then sheet closes or reauth fails, valid replacement credentials are discarded but the consumed old refresh remains persisted. Separate pending login-attempt cancellation from established session generation/refresh lifetime. Tests: delayed committed refresh arriving after sheet dismissal or failed login is saved; actual logout still wins; successful account replacement invalidates stale old-account operations. Maintain single-flight behavior.

## iOS: privacy manifest contradicts authentication collection (Important)
Current `Sumly/Resources/PrivacyInfo.xcprivacy` declares empty NSPrivacyCollectedDataTypes. Actual authentication sends/retains Apple full name as nickname, email address, phone number and user identifier. Declare these exact types with linked=true, tracking=false, purpose=NSPrivacyCollectedDataTypePurposeAppFunctionality:
- NSPrivacyCollectedDataTypeName
- NSPrivacyCollectedDataTypeEmailAddress
- NSPrivacyCollectedDataTypePhoneNumber
- NSPrivacyCollectedDataTypeUserID
Retain existing UserDefaults CA92.1 declaration and no-tracking. Do NOT declare remote holdings collection; holdings stay local. Verify actual bundled manifest and add regression if practical. Document that operator must separately update published privacy policy and App Store Connect privacy disclosures; do not change portal in this task.
Official source verified: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
Purpose: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes
Linked: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypelinked

## Minor/recheck
- Model `submit` needs active and modeEnabled guard; worker reports it was fixed after review snapshot. Recheck, retain test.
- iOS register/reset cooldown keys are separate while backend email destination cooldown is shared; share normalized destination cooldown and test purpose switch.
- Failed Keychain clear test should cover actual new session/relaunch using durable nonsecret logout marker, not only repeated restore of same instance.

## Previously addressed, do not redo blindly
Reviewer found latest backend refresh-history/session-family logout, generation guard after retried /me, logout tombstone, matching scalar password counts and nonnullable avatar_url. All 13 endpoint verbs/paths/DTOs align. No additional concrete bypass found in Apple verification, OTP activation/consumption, identity linking, Argon2 or reset/session/native-vs-legacy validation. Retain tests proving these.

## Coordinator independent verification so far
- `go test -count=1 ./internal/auth/domain ./internal/auth/adapters/credentials`: PASS (2 packages), not full backend evidence.
- `bun run type-check && bun run build:mp-weixin` in unchanged mini: PASS.
- Parent macbook-air `make test` in sumly_ios (not restricted child): PASS, **60 Swift tests**, zero failures; TEST SUCCEEDED at 2026-09-29 10:29:55 local. Child's sandbox/CoreSimulator limitation does not apply to parent tool. These tests must be rerun after fixes.
- Full `make build`, UI screenshot inspection, backend final tests/database integration still need fresh verification.
