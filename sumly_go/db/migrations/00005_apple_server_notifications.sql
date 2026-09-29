-- +goose Up
ALTER TABLE auth_identities ADD COLUMN apple_authenticated_at TIMESTAMPTZ;
CREATE TABLE auth_apple_notifications (
    id TEXT PRIMARY KEY,
    subject TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('consent-revoked', 'account-deleted')),
    issued_at TIMESTAMPTZ NOT NULL,
    event_time BIGINT NOT NULL DEFAULT 0,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX auth_apple_notifications_subject_issued
    ON auth_apple_notifications(subject, issued_at DESC);

-- +goose Down
ALTER TABLE auth_identities DROP COLUMN apple_authenticated_at;
DROP TABLE IF EXISTS auth_apple_notifications;
