# Backend native authentication verification — 2026-09-29

## Final coordinator verification

The implementation worker had a restricted sandbox. The coordinator subsequently ran the following commands through the authorized macbook-air workspace against the actual checkout, overcoming the worker-only socket/database restrictions without changing production configuration.

| Check | Observed result |
| --- | --- |
| `go test -count=1 ./...` with explicit test database | Passed across all packages. |
| `go test -race -count=1 -json ./...` with explicit test database | **100 passed test events including subtests, 0 failed, 0 skipped; no race reports.** |
| PostgreSQL integration | All 9 repository integration tests passed, including 3 new native authentication tests. |
| `go vet ./...` | Passed. |
| `go build -o /tmp/sumly-native-auth-api ./cmd/api` | Passed. |
| Installed `sqlc generate`, OpenAPI validation | Passed during implementation; OpenAPI tests also passed in the full coordinator suites. |
| `git diff --check` | Passed at coordinator review. |

Only `TEST_DATABASE_URL` was read from the local `.env` and supplied to these test processes. Its value was not displayed; `DATABASE_URL` was not loaded or used. Integration tests created randomly named schemas inside the explicitly configured test database and automatically removed their own schemas. No production migrations, real accounts, SMS/email delivery, deployment, remote push or `.env` modifications were performed.

The worker's initial test attempts had 9 database skips and a WeChat localhost-socket failure because of its sandbox. Those were environment limitations, not passing evidence. The later coordinator runs above executed those tests successfully, including the previously blocked WeChat adapter package.

## Implemented scope

- All 13 native routes and snake_case DTOs: capabilities, Apple challenge/sign-in, phone verification/sign-in, email verification/register/password sign-in/reset, refresh, logout, current user and account deletion.
- Apple RS256/JWKS checks on client and code-exchanged identity tokens, exact issuer/audience/nonce/expiry, single-use challenge, ES256 client secret, encrypted retained refresh token and revocation.
- Signed Aliyun mainland SMS and authenticated TLS/STARTTLS SMTP. Missing configuration disables capabilities; no production mock delivery or plaintext code fallback.
- Migration 00004 and sqlc queries: verified identities, persistent quotas/OTP hashes, atomic consumption and login creation, rotating session families/history and account deletion. Expired records are cleaned hourly while enabled.
- Argon2id email credentials, dummy hashing for unknown addresses, 15-minute native JWTs checked against live sessions, absolute 30-day refresh lifetime, logout/reset revocation and recent-primary-login deletion.
- Existing WeChat/development authentication remains compatible. Native tokens cannot bypass revocation through legacy JWT parsing.
- Proxy trust configuration, bounded JSON/provider requests, OpenAPI and setup documentation. `golang.org/x/crypto` is now declared as a direct dependency; no dependency version changed.

## Security regressions and review

Tests cover OTP activation, expiry/guess limits/replay, persistent destination quotas, concurrent code/registration/refresh consumption, duplicate identities, email/phone lifecycle, password reset and logout revocation, frozen/deleted users and refresh lifetime preservation.

RED→GREEN regressions corrected a shared Apple identity quota that rejected unrelated callers after 20 challenges, and Apple transport outages incorrectly reported as bad credentials. Current Apple limits are per-caller/IP plus a separate global quota. Previously rotated refresh hashes remain associated with their session family until absolute expiry so logout can revoke an already-rotated session. Apple provider revocation runs under the account deletion transaction's lock; a failure retains the account.

A separate read-only reviewer inspected backend and iOS contracts and trust boundaries. The first-round Apple quota finding was also resolved by the backend author's regression before completion. Cross-platform deletion/session/privacy findings are tracked in the native-auth review documents.

## Remaining live prerequisites

Code and local automated tests do not prove interoperability with configured live providers. Before live acceptance, apply migration 00004 during an authorized deployment, configure the Apple App ID/capability/key, approved Aliyun SMS signature/template and authenticated TLS SMTP sender. Then use explicitly authorized staging accounts/messages for real-device Apple consent/cancellation/revocation and SMS/email delivery tests. No real provider calls or portal changes were made in this implementation session.
