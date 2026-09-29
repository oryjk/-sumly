# Native Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver iOS + Go Apple, phone OTP, and email/password login/registration with secure session lifecycle.

**Architecture:** Extend Go hexagonal auth with provider/persistence ports, PostgreSQL transactions, OTP quotas and native session revocation. SwiftUI uses an injected authentication service, Keychain and a session state machine; the app keeps existing anonymous holdings/market behavior.

**Tech Stack:** Existing Go >=1.26.5, Gin, pgx/sqlc/PostgreSQL; Swift 6 / SwiftUI / AuthenticationServices / Keychain / XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-29-native-auth-design.md` (authoritative API contract and security values).

## Global Constraints
- Work in existing main checkout (user preference). Backend owns only sumly_go/**; iOS owns only sumly_ios/**. Coordinator owns docs/superpowers/** and integration review.
- Read applicable AGENTS.md. Preserve WeChat/dev routes, envelope and all existing tests; do not change sumly_mini or existing migration files.
- Exact shared API and DTOs are in the spec. Do not independently rename routes/fields or change password/OTP/session limits.
- No real SMS/email, production DB writes, real secrets, Apple portal changes, deployment, remote push, or automatic data migration.
- Tests first: record failing command/result, implement, run green suite. Do not claim tests ran without command evidence.
- No agent commits while working in shared checkout; coordinator reviews and commits scoped final files after verification.

## Review Focus
- Concurrent OTP consumption/registration/refresh: only one success, no duplicated identities or reusable refresh tokens.
- Session/logout/reset races: stale iOS requests cannot resurrect credentials; reset/logout invalidate backend native sessions.
- Disabled or failing providers: no fake delivery success, no plaintext debug code, no account creation from unverified identity.
- Backward compatibility: existing anonymous holdings remain intact and legacy mini authentication still works.
- App signing and data semantics: simulator entitlement works; account deletion never deletes unrelated local guest holdings.

### Task 1: Backend native auth vertical slice — COMPLETE

The checklist below preserves the original execution brief. Final evidence is recorded in the completion ledger and `sumly_go/docs/native-auth-verification.md`.
**Owner:** Backend implementer, scope sumly_go/**.
**Files:** New auth domain/ports/use cases/adapters/test files under internal/auth; new forward migration 00004; auth SQL/sqlc additions; bootstrap config/router/dependencies; user/auth compatibility as needed; docs/openapi.yaml, .env.example, README.md.
**Consumes:** Existing DB schema/user repository/JWT/middleware/envelope; exact HTTP contract from spec.
**Produces:** All specified auth routes, capability configuration, complete real provider adapters, integration/unit tests and deployment instructions.
- [ ] Read existing AGENTS and complete auth/user/bootstrap/persistence flow; design focused ports rather than giant service.
- [ ] Write failing behavioral tests for OTP normalization/attempts/expiry/consumption, email register/login/reset, Apple verification, refresh rotation/revocation and deletion. Run targeted tests to prove missing feature.
- [ ] Add migration and SQL; use `make generate`/sqlc for generated code. Implement transactions/unique constraints, code hashing and persistent quotas. Native user IDs must not derive authority from arbitrary client profile fields.
- [ ] Implement Go application use cases and real Apple/Aliyun/SMTP adapters. Fail closed on missing config and external failures. Provide complete env setup documentation. Preserve non-native routes.
- [ ] Implement handlers and middleware with bounded input and IP trust config; update OpenAPI for exact shared contract.
- [ ] Run gofmt only on changed Go files; `go test ./...`, `go test -race ./...`, `go vet ./...`, `go build -o /tmp/sumly-native-auth-api ./cmd/api`. Integration tests use TEST_DATABASE_URL only, unique schemas, no Docker or DATABASE_URL fallback. Report skips explicitly.
- [ ] Self-review race/rollback/resource bounds/security, document exact checks and unresolved provider prerequisites in response. Do not commit/push.

### Task 2: iOS native account UI and session vertical slice — IMPLEMENTED / AUTOMATED CHECKS PASS

Manual visual, accessibility and live-provider acceptance remain explicitly separate from implementation; see final ledger.
**Owner:** iOS implementer, scope sumly_ios/** (can run in parallel with Task 1 because API fixed).
**Files:** New Sources/Authentication or Features/Account service/session/models/Keychain; account/login/register/reset views and Apple bridge; App/SumlyApp.swift; project.yml/entitlement; tests and README.md.
**Consumes:** Exact routes/JSON/password policy/nonce semantics in spec; current GoldTheme and root tab bar.
**Produces:** Functional 我的 tab and all three login/registration methods with restored/revocable session and no holdings migration.
- [ ] Read AGENTS, GoldTheme, root app, backend price URL configuration and project.yml. Read advertised frontend-design skill for UI work.
- [ ] Write Swift Testing tests for DTO/envelope, validation, session persistence, restore/network errors, refresh single-flight and logout race. Run failing tests before implementations.
- [ ] Implement protocol-based native auth API service and secure Keychain persistence; bounded decoding/errors and generation-checked session state machine.
- [ ] Implement native Apple challenge/state flow and credential-state revocation; phone OTP with transparent +86 support; email login/register/reset with 12–128 chars/max512 bytes and confirmation.
- [ ] Implement account tab/guest and signed-in state, provider capabilities, resend countdown, visible errors, logout and confirm/re-auth deletion. Keep original home/holdings/add flows untouched.
- [ ] Add Sign in with Apple entitlement via project.yml and make generate; no Xcode project hand editing. Screenshot simulator UI and visually inspect layout.
- [ ] Run `make test` and `make build`, reporting exact test totals/failures; document real-device external setup and any unverified steps. Do not commit/push.

### Task 3: Integrated verification and security review — COMPLETE FOR LOCAL CODE
**Owner:** Coordinator plus independent reviewer (read-only review first).
**Files:** Review both diffs, spec/plan progress; targeted fixes owned by relevant implementer/coordinator only after workers stop.
**Consumes:** Backend+iOS implementation reports and actual diffs/tests.
**Produces:** Verified compatible code, documented remaining external setup and clean scoped commit if tests pass.
- [ ] Reconcile API contract by comparing backend handlers/OpenAPI with actual iOS request/response codecs; test capabilities and all auth payloads.
- [ ] Independent fresh review of auth trust boundaries, OTP abuse, Apple validation/revocation, SQL atomicity, keychain/session races and UI behavior. Fix important findings with regression tests.
- [ ] Run final backend full test/vet/build plus iOS test/build and existing mini type-check/build (compatibility only, no mini edits). Confirm explicit integration-test skips vs real execution.
- [ ] Inspect git diff/check/status; ensure no secrets/unrelated changes, no generated xcodeproj, no accidental build-number bump. Update this checklist and report implemented features separately from unconfigured provider live tests.

## Initial decisions / progress ledger
- Base commit: 8ecb630. Worktree initially clean on main, synced with origin/main.
- Ruling: Keep current main checkout rather than create a feature branch, following user's standing main preference; isolated write scopes prevent backend/iOS conflicts.
- Ruling: Phone provider defaults to mainland +86 Aliyun; other regions not silently accepted. SMS provider can be replaced at ports without changing use cases.
- Ruling: No automatic cross-provider account merging. Login does not imply holdings cloud sync.
- Pre-flight: Task 1 produces routes/DTOs in spec; Task 2 consumes exactly those. Only interface shared, file write scopes disjoint. Task 3 starts write fixes after implementers finish.
- Execution started. No production code has been changed at plan creation.
- Initial Codex workers agt_ac0d99f7 and agt_ccbaceea failed before edits. There are multiple Codex installations: the shell npm wrapper has ENOENT, but DevSpace actually used ~/.local/bin/codex 0.147.0. A direct read-only health check on that binary confirmed server HTTP 400: gpt-6-astra requires a newer Codex. This corrects the initial unverified attribution to the npm wrapper.
- Claude fallback workers agt_b912f227 and agt_b9736116 made no file edits while running and were stopped with this task's newly-created DevSpace daemon. No pre-existing active worker was affected; no global config or installed binary was edited.
- Verified the already-installed ChatGPT bundled Codex 0.158.0-alpha.2.1 with a read-only health check: READY, exit success. Restarted the task-owned DevSpace daemon with process-local CODEX_COMMAND pointing to this binary (no persistent config edits).
- Implementation workers: backend agt_e9276420 (completed) and iOS agt_94a879bd (initial implementation completed, scoped review fixes running), explicitly model gpt-6-astra/medium, disjoint scopes and fixed API contract. Do not redispatch these tasks without reading their actual results/diffs.
- Independent read-only review agt_12ddf09d completed; concrete findings and evidence are in `2026-09-29-native-auth-review-round-1.md`. Backend Apple quota was fixed by author regression before worker completion; iOS deletion identity/refresh cancellation/privacy/cooldown fixes are being applied in the existing worker.
- Parent workspace verification overcame child-only sandbox restrictions: iOS `make test` passed 60 tests before review fixes; Go full suite then race suite with explicitly selected test DB passed (100 pass events including subtests, zero failures/skips; all 9 database integration cases executed); go vet/build passed. Native/legacy WeChat socket tests now also pass. Mini unchanged type-check/build passed. Do not report child sandbox skips as remaining project failures after these successful parent runs.
- TEST_DATABASE_URL is absent from the tool process but an explicit assignment exists in project sumly_go/.env (value never displayed). Workers may load only that test variable for isolated-schema tests; never DATABASE_URL. Distinguish executed integration tests from skips.

## Final completion ledger

- Task 1: complete. All native backend routes/adapters/migration are implemented. Parent full/race runs passed with the explicit test DB: 100 passed test events including subtests, zero failure/skip, all nine PostgreSQL repository integration cases executed. Vet and API build passed. No production migration or real SMS/email/Apple requests were executed.
- Task 2: implementation complete. Parent final `make test` passed **73 tests** (44 existing, 26 auth/regressions, 3 UI rendering checks). Parent `make build` passed. Privacy manifest test checked the actual host app bundle; plist and entitlement validation passed. Local guest holdings behavior remains unchanged.
- UI rendering generated valid account/phone/email images through test-only fixtures, without real providers. The file-read tool denies access to the simulator container outside its allowed roots; that boundary was respected. Manual visual/large-text/VoiceOver/device interaction acceptance remains unverified, not claimed complete.
- Task 3: complete for local implementation. Reviewer agt_12ddf09d re-read final fixes and confirmed all four Important and three minor findings resolved, with no remaining Critical/Important defect identified in the scoped re-review. Parent independently verified runtime test/build results. Unchanged mini type-check/build passed.
- Changes to AGENTS/README document the new contract, secure session boundaries, local-only holdings, provider configuration and accurate verification status.
- External readiness is still pending: configure/confirm Apple capability/key, Aliyun approved SMS signature/template and SMTP, apply migration during an authorized backend deployment, update published privacy disclosures, and run authorized staging/device delivery/authorization checks. No deploy/push/portal mutation is part of this implementation.
- Do not redispatch completed implementation tasks merely because the original brief checkboxes above remain as historical instructions. Resume only actual remaining external/manual acceptance work when authorized.
