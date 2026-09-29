# Native account authentication design

## Goal and scope
The user requested implementation now: Apple sign-in, phone verification-code sign-in, email/password sign-in, and corresponding registration. Implement on existing iOS SwiftUI app and Go backend. Leave sumly_mini unchanged and preserve its WeChat/dev auth compatibility. Work on the current main checkout (user's standing preference); do not deploy, push, send real SMS/email, or modify real secrets/database contents as part of implementation.

The existing app permits anonymous market viewing and keeps holdings in SwiftData. Preserve that behavior and storage. Add a functional 我的 account tab. Clearly state that logging in does not currently upload or synchronize local holdings; never silently reassign, delete, or upload existing holdings.

## Chosen approach
Extend the existing hexagonal Go authentication module and PostgreSQL persistence rather than introduce a hosted identity provider or a second backend. iOS uses native AuthenticationServices, secure Keychain storage, and a protocol-based service/session layer. SMS delivery uses a concrete Alibaba Cloud SMS adapter; email uses authenticated TLS SMTP. External credentials are environment configuration, not source code. Missing credentials fail closed and are reported as disabled capabilities rather than simulated success.

## Public API contract
All paths below are relative to `/api/v1/app`, use the existing `{code,message,data}` envelope, and use snake_case. Existing WeChat/dev endpoints remain unchanged.

- `GET /auth/capabilities` -> `{apple: bool, phone: bool, email: bool}`. If new auth is globally disabled, all false (or a well-handled 404 during older-server compatibility). No secrets.
- `POST /auth/apple/challenge` `{}` -> `{challenge_id: string, nonce: string, expires_in: 300}`. The nonce returned is already the exact nonce to set on Apple's request; iOS must NOT hash it again. Server issues cryptographically random, expiring, single-use values.
- `POST /auth/apple/login` `{challenge_id, identity_token, authorization_code, nickname?: string}` -> LoginResult. Verify RS256 signature from trusted Apple JWKS, exact issuer, configured client ID audience, expiration, issued-at, subject and expected nonce; exchange authorization code server-side with Apple and verify returned identity belongs to same subject/client/nonce. Never trust client email or user ID. First successful verified subject creates account; subsequent logins reuse it. No automatic linking on email equality. Store Apple's refresh token encrypted for revocation. Native client must validate its random state and handle cancellation cleanly.
- `POST /auth/phone/code` `{phone_number}` -> `{retry_after: 60, expires_in: 300}`. Normalize mainland China mobile numbers to +86 E.164 for the initial SMS adapter. UI accepts country code default +86 and transparently states the currently supported region; do not claim global delivery.
- `POST /auth/phone/login` `{phone_number, code}` -> LoginResult; first verified phone auto-registers, otherwise signs in. No password for phone login.
- `POST /auth/email/code` `{email, purpose: "register" | "reset_password"}` -> `{retry_after: 60, expires_in: 300}` with non-enumerating response.
- `POST /auth/email/register` `{email, password, code}` -> LoginResult. Email possession must be verified before creation. Duplicate email must never overwrite password or merge accounts. Normalize whitespace and case without provider-specific dot/plus rewriting. Password policy: 12–128 Unicode characters, max 512 bytes, no trimming or silent truncation; UI and backend agree.
- `POST /auth/email/login` `{email, password}` -> LoginResult. Generic invalid-credentials failure and comparable unknown-user hashing work.
- `POST /auth/email/reset-password` `{email, code, new_password}` -> `{}`; single-use code, reset only an existing email identity, revoke existing native sessions; do not auto-create or return a new login session. UI returns to login with success notice.
- `POST /auth/refresh` `{refresh_token}` -> LoginResult. Opaque 32-byte+ random refresh token, hashed at rest, single-use rotation with atomic consumption, absolute lifetime 30 days (do not extend on rotation). Reuse does not yield another token; old sessions invalidated on reset/delete.
- `POST /auth/logout` `{refresh_token}` -> `{}`; idempotent revoke, never trust supplied user ID. Logout clears local credentials even if network unavailable, but communicate server-side limitation where applicable.
- `GET /auth/me` with Bearer -> NativeUser. This endpoint enforces live native-session revocation and user state.
- `DELETE /auth/account` with Bearer and `{confirmation: "DELETE"}` -> `{}`; authenticated active native session and recent primary login <=5 minutes required (a refresh does not reset that timestamp). Otherwise 401/403 instructs reauthentication. Revoke Apple credentials when linked; delete account identity/profile/session/challenge records transactionally, never run destructive operations against real accounts during tests. Transient Apple failure should fail explicitly/retry without silently claiming full deletion. iOS confirmation clearly says local guest holdings remain on this device and are not cloud account data.

`LoginResult` = `{token: string, refresh_token: string, expires_in: 900, user: NativeUser}`.
`NativeUser` = `{id: int64, nickname: string, avatar_url: string, email: string|null, phone_number: string|null, status: string, provider: "apple"|"phone"|"email"}`. Server may include existing fields; client decoding ignores them. Native access tokens expire after 15 minutes. Enforce server-side native sid/session check for authenticated requests; preserve legacy WeChat/dev JWT handling without accepting a revoked native token as legacy.

## Persistence and security
Add a new forward migration only; preserve existing migrations and data. Separate verified login identities from editable user-profile fields. Unique database constraint on (provider, subject); create native account+identity transactionally so concurrent first login cannot create duplicates. Existing non-null openid constraint may be handled using a reserved cryptographically random `native-` internal ID, never used for identity verification. Do not link by unverified phone profile/email or Apple relay email.

Persist OTP/challenge hashes and rate-limits in PostgreSQL, not a process-local-only store. OTP is random six digits, HMAC-protected at rest, valid 5 minutes, max 5 failed guesses, 60-second resend cooldown, max 5 per destination/hour and 20 per destination/day; IP hourly and global send quotas bound delivery-cost abuse. Password/IP throttles apply before Argon2 work; fail closed on unavailable quota storage. Trust forwarded client IP only for explicitly configured proxy networks. Wrong-code attempt counters and valid-code consumption must be atomic; resends invalidate prior code, cannot reset long-lived abuse counters; no plaintext codes/tokens/passwords in API responses or logs. Delivery errors must not mint usable OTPs; disabled providers return service-unavailable. Test providers exist only as test fakes, never a production console-code fallback.

Password hashing: Argon2id with random 16-byte salt, at least 19 MiB, t=2, p=1, 32-byte output, constant-time verification and bounded PHC parsing. Derive distinct pepper/encryption purposes securely from existing >=32-byte JWT secret or use explicitly configured independent keys; never hard-code keys. Protect Apple refresh tokens with AES-GCM authenticated encryption and random nonces. Bound network requests, JSON bodies, JWKS cache refresh and external responses; require TLS for providers. Fail closed on Apple JWT/code/signature/nonce/audience errors.

Email register/reset sender responses must not enumerate accounts. Tests must cover disabled/failing providers, wrong/expired/replayed OTPs, rate limits, duplicate registration, concurrent credential consumption, frozen/deleted users, incorrect Apple issuer/audience/nonce/signature/expired token, refresh replay, reset/logout revocation, and self-delete authorization.

## iOS experience
Use existing GoldTheme tokens and dark/gold design; no gradients. 我的 tab has guest call to action or signed-in account card, login provider, masked identifier, logout and account deletion with confirmation. A sheet presents Apple native SignInWithAppleButton, phone code flow, and email login/register/reset forms. Include clear first-login auto-registration copy, resend countdown, password confirmation on registration/reset, correct keyboard/content types, validation, loading/disabled states, accessible labels and errors. Native Apple button only becomes available after server challenge is ready. Recover from expiration by preparing a new challenge, do not reuse state/nonce. A user-cancelled Apple flow is not an error banner.

Keychain uses a dedicated service and when-unlocked-this-device-only accessibility. Do not store password/OTP in Keychain or UserDefaults. Store session/Apple user identifier only when necessary. Restore on launch, refresh once on authorization failure, avoid parallel refresh rotation with a single-flight mechanism, and prevent an in-flight login/refresh from resurrecting a logged-out account with session generation checks. Network errors must not erase a valid stored session; actual unauthorized/revoked sessions clear it. Observe Apple credential-revocation and verify credential state where supported without logging out on a transient check error. Tests use fakes and no real messages/accounts.

Declare Sign in with Apple entitlement through project.yml / generated plist mechanism; no manual xcodeproj edits. Do not activate or alter Apple Developer portal configuration or signing credentials. `make generate`, `make test`, `make build` must succeed for simulator without requiring new portal provisioning.

## Delivery and boundaries
Document exact env variables, migration commands, Aliyun signature/template setup, SMTP configuration, Apple App ID capability/key setup and a real-device test checklist. Missing production credentials block live end-to-end validation, not implementation. No existing holdings cloud sync or cross-provider account linking in this scope. No deployment, real-message tests, remote push or App Store upload unless separately requested.

## Sources verified 2026-09-29
- Apple authentication: https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple
- Apple token revocation/account deletion: https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple
- Apple account deletion requirement: https://developer.apple.com/support/offering-account-deletion-in-your-app
- OWASP password storage: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
- OWASP email verification: https://cheatsheetseries.owasp.org/cheatsheets/Email_Validation_and_Verification_Cheat_Sheet.html
- Official Aliyun SMS Go SDK: https://github.com/alibabacloud-go/dysmsapi-20170525 (v5 module advertised by upstream)
