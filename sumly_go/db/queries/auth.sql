-- name: GetUserByOpenID :one
SELECT id, openid, nickname, avatar_url, real_name, phone_number, status, created_at, updated_at
FROM users
WHERE openid = $1;

-- name: GetUserByID :one
SELECT id, openid, nickname, avatar_url, real_name, phone_number, status, created_at, updated_at
FROM users
WHERE id = $1;

-- name: CreateUser :one
INSERT INTO users (openid, nickname, avatar_url)
VALUES ($1, $2, $3)
RETURNING id, openid, nickname, avatar_url, real_name, phone_number, status, created_at, updated_at;

-- name: UpdateUserAppProfile :one
UPDATE users
SET nickname = $2,
    real_name = $3,
    updated_at = NOW()
WHERE id = $1
RETURNING id, openid, nickname, avatar_url, real_name, phone_number, status, created_at, updated_at;

-- name: NativeLock :exec
SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0));

-- name: NativeQuota :one
INSERT INTO auth_quotas(key,count,expires_at) VALUES($1,1,$2)
ON CONFLICT(key) DO UPDATE SET count=CASE WHEN auth_quotas.expires_at<=now() THEN 1 ELSE auth_quotas.count+1 END,
expires_at=CASE WHEN auth_quotas.expires_at<=now() THEN EXCLUDED.expires_at ELSE auth_quotas.expires_at END
RETURNING count;

-- name: NativePutCode :exec
INSERT INTO auth_codes(key,hash,expires_at) VALUES($1,$2,$3)
ON CONFLICT(key) DO UPDATE SET hash=EXCLUDED.hash,expires_at=EXCLUDED.expires_at,attempts=0,active=false;

-- name: NativeActivateCode :execrows
UPDATE auth_codes SET active=true WHERE key=$1 AND hash=$2;

-- name: NativeAttemptCode :one
UPDATE auth_codes SET attempts=attempts+1 WHERE key=$1 AND active AND expires_at>now() AND attempts<5
RETURNING hash;

-- name: NativeDeleteCode :exec
DELETE FROM auth_codes WHERE key=$1;

-- name: NativeIdentity :one
SELECT i.*,u.nickname,COALESCE(u.avatar_url,'')::text AS avatar_url,u.status FROM auth_identities i JOIN users u ON u.id=i.user_id WHERE provider=$1 AND subject=$2;

-- name: NativeInsertIdentity :exec
INSERT INTO auth_identities(user_id,provider,subject,password_hash,apple_refresh) VALUES($1,$2,$3,$4,$5);

-- name: NativeUpdateApple :exec
UPDATE auth_identities SET apple_refresh=$3 WHERE provider=$1 AND subject=$2;

-- name: NativeUpdatePassword :exec
UPDATE auth_identities SET password_hash=$2 WHERE provider='email' AND subject=$1;

-- name: NativeInsertSession :exec
INSERT INTO auth_sessions(id,user_id,provider,refresh_hash,authenticated_at,expires_at,family_id) VALUES($1,$2,$3,$4,$5,$6,$7);

-- name: NativeSession :one
SELECT s.*,u.nickname,COALESCE(u.avatar_url,'')::text AS avatar_url,u.status,i.subject
FROM auth_sessions s JOIN users u ON u.id=s.user_id JOIN auth_identities i ON i.user_id=s.user_id AND i.provider=s.provider
WHERE s.id=$1 AND s.expires_at>now() AND u.status='active';

-- name: NativeRefresh :one
SELECT id,user_id FROM auth_sessions WHERE refresh_hash=$1;

-- name: NativeDeleteSession :exec
DELETE FROM auth_sessions WHERE id=$1;

-- name: NativeRevokeUser :exec
DELETE FROM auth_sessions WHERE user_id=$1;

-- name: NativeDeleteUser :exec
DELETE FROM users WHERE id=$1;

-- name: NativeNewChallenge :exec
INSERT INTO auth_challenges(id,nonce_hash,expires_at) VALUES($1,$2,$3);

-- name: NativeConsumeChallenge :one
DELETE FROM auth_challenges WHERE id=$1 AND expires_at>now() RETURNING nonce_hash;

-- name: NativeCleanup :exec
WITH q AS (DELETE FROM auth_quotas WHERE expires_at<now()-interval '1 day'),
c AS (DELETE FROM auth_codes WHERE expires_at<now()-interval '1 day'),
a AS (DELETE FROM auth_challenges WHERE expires_at<now()),
h AS (DELETE FROM auth_refresh_history WHERE expires_at<now()),
s AS (DELETE FROM auth_sessions WHERE expires_at<now()) SELECT 1;

-- name: NativeSubjectByUser :one
SELECT subject FROM auth_identities WHERE user_id=$1 AND provider=$2;

-- name: NativeRememberRefresh :exec
INSERT INTO auth_refresh_history(refresh_hash,user_id,family_id,expires_at) VALUES($1,$2,$3,$4);

-- name: NativeRefreshFamily :one
SELECT user_id,family_id FROM auth_refresh_history WHERE refresh_hash=$1 AND expires_at>now();

-- name: NativeRevokeFamily :exec
DELETE FROM auth_sessions WHERE family_id=$1;
