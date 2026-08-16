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
