-- +goose Up
CREATE TABLE auth_identities (
 user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 provider TEXT NOT NULL CHECK(provider IN ('apple','phone','email')),
 subject TEXT NOT NULL,
 password_hash TEXT NOT NULL DEFAULT '',
 apple_refresh BYTEA,
 PRIMARY KEY(provider,subject),
 UNIQUE(user_id,provider)
);
CREATE TABLE auth_sessions (
 id TEXT PRIMARY KEY,
 user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 provider TEXT NOT NULL,
 family_id TEXT NOT NULL,
 refresh_hash TEXT NOT NULL UNIQUE,
 authenticated_at TIMESTAMPTZ NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX auth_sessions_user ON auth_sessions(user_id);
CREATE TABLE auth_refresh_history (
 refresh_hash TEXT PRIMARY KEY,
 user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 family_id TEXT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX auth_refresh_history_user ON auth_refresh_history(user_id);
CREATE TABLE auth_codes (
 key TEXT PRIMARY KEY,
 hash TEXT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL,
 attempts INT NOT NULL DEFAULT 0,
 active BOOLEAN NOT NULL DEFAULT false
);
CREATE TABLE auth_quotas (
 key TEXT PRIMARY KEY,
 count INT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX auth_quotas_expiry ON auth_quotas(expires_at);
CREATE TABLE auth_challenges (
 id TEXT PRIMARY KEY,
 nonce_hash TEXT NOT NULL,
 expires_at TIMESTAMPTZ NOT NULL
);
-- +goose Down
DROP TABLE auth_challenges,auth_quotas,auth_codes,auth_refresh_history,auth_sessions,auth_identities;
