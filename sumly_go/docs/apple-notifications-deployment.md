# Apple notifications deployment — 2026-09-29

Deployed over `ssh jd` to the existing Sumly Docker Compose service after explicit user authorization. Release image: `sumly-backend:20260929-apple-notifications`.

## Verification

- `go test -count=1 ./...` passed with the explicitly configured `TEST_DATABASE_URL`; PostgreSQL tests used isolated temporary schemas.
- The notification integration test initially failed because a delayed old event revoked a newer Apple login. Recording verified Apple credential issue times in migration 00005 fixed that regression; the full suite then passed.
- Notification processing now requires only the configured Apple Client ID and Apple's public signing keys. Tests cover notification verification without the developer private key while login remains disabled.
- `go vet ./...`, Linux amd64 API/migration builds, `git diff --check` passed.
- iOS `swift test`: 26 passed. Simulator `make build`: BUILD SUCCEEDED.
- Production migrations 00004 and 00005 applied successfully; previous database version was 3.
- Public `/sumly/health`: HTTP 200 using TLS 1.2.
- Public notification POST with invalid payload: HTTP 401, replacing the previous HTTP 404.
- jd can fetch Apple's public JWKS: HTTP 200.
- Public capabilities: apple=false, phone=false, email=false, as expected until provider keys are supplied.
- Existing public gold quote: HTTP 200.

## Deployment and rollback artifacts

Server release directory: `/root/docker_data/sumly/releases/20260929-apple-notifications`.
It contains the Linux API/migration executables, migrations, and a `backup` directory containing the previous Compose configuration, environment file and a PostgreSQL custom-format dump of the configured application schema. Secrets were not printed or committed. The old Docker image is retained.

The new image reuses the previous runtime layer and replaces the statically compiled API executable. The existing Compose service, network and localhost port are preserved. Nginx configuration validation and reload succeeded after the container replacement. Native auth is enabled with Client ID `com.oryjk.sumly`, Team ID `237PA3LEYJ`; the existing JWT secret is preserved. Only the current nginx address is trusted for forwarded client IPs.

## Remaining setup

Register `https://oryjk.cn/sumly/api/v1/app/auth/apple/notifications` on the primary App ID. Download the Sign in with Apple `.p8` key, then configure Key ID and a read-only mounted private-key file. No private key is present in this deployment, so Apple sign-in is deliberately unavailable. After credentials are configured, validate actual Apple login from the iOS “我的” page, returning-user login, logout and revocation. No real Apple user authorization or signed Apple notification was available for end-to-end verification in this run. No App Store build was uploaded.

## Key configuration completed — 2026-09-29

The user supplied Key ID `H3V56W2FT3` and placed the private key on jd. The existing file is now restricted to mode 0400, owned by the backend UID 10001, and mounted read-only at `/run/secrets/sumly-apple.p8`. `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY_FILE` are configured; the backend was recreated and nginx reloaded. Prior environment and Compose files are saved under `/root/docker_data/sumly/releases/apple-key-config-20260929-144526`.

Fresh public checks passed: health HTTP 200; capabilities `apple=true`, `phone=false`, `email=false`; Apple challenge HTTP 200 with valid challenge fields (nonce and challenge values were not logged); invalid notification HTTP 401. This supersedes the missing-private-key status above. Real Apple authorization and successful code exchange still require a device login; these checks do not establish that the developer-portal key association is correct. No source changes or new binary were needed for this configuration step; code tests/builds were not repeated.
