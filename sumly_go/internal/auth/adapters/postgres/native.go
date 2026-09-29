package postgres

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"time"

	q "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NativeStore struct{ pool *pgxpool.Pool }

func NewNativeStore(p *pgxpool.Pool) *NativeStore { return &NativeStore{p} }
func ts(t time.Time) pgtype.Timestamptz           { return pgtype.Timestamptz{Time: t, Valid: true} }
func appleNotificationDigest(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}
func (s *NativeStore) transaction(ctx context.Context, f func(*q.Queries) error) error {
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return e
	}
	defer tx.Rollback(ctx)
	e = f(q.New(tx))
	if e != nil && !errors.Is(e, domain.ErrCredentials) && !errors.Is(e, domain.ErrConflict) {
		return e
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return e
}
func (s *NativeStore) TakeQuota(ctx context.Context, quotas []domain.Quota) error {
	quotas = append([]domain.Quota(nil), quotas...)
	sort.Slice(quotas, func(i, j int) bool { return quotas[i].Key < quotas[j].Key })
	return s.transaction(ctx, func(db *q.Queries) error {
		for _, quota := range quotas {
			n, e := db.NativeQuota(ctx, q.NativeQuotaParams{Key: quota.Key, ExpiresAt: ts(time.Now().Add(quota.Window))})
			if e != nil {
				return e
			}
			if n > int32(quota.Limit) {
				return domain.ErrLimited
			}
		}
		return nil
	})
}
func (s *NativeStore) PutCode(ctx context.Context, key, hash string, expires time.Time) error {
	return q.New(s.pool).NativePutCode(ctx, q.NativePutCodeParams{Key: key, Hash: hash, ExpiresAt: ts(expires)})
}
func (s *NativeStore) ActivateCode(ctx context.Context, key, hash string) error {
	n, e := q.New(s.pool).NativeActivateCode(ctx, q.NativeActivateCodeParams{Key: key, Hash: hash})
	if e == nil && n != 1 {
		return domain.ErrCredentials
	}
	return e
}
func consume(ctx context.Context, db *q.Queries, key, hash string) error {
	got, e := db.NativeAttemptCode(ctx, key)
	if errors.Is(e, pgx.ErrNoRows) {
		return domain.ErrCredentials
	}
	if e != nil {
		return e
	}
	if subtle.ConstantTimeCompare([]byte(hash), []byte(got)) != 1 {
		return domain.ErrCredentials
	}
	return db.NativeDeleteCode(ctx, key)
}
func (s *NativeStore) ConsumeCode(ctx context.Context, key, hash string) error {
	return s.transaction(ctx, func(db *q.Queries) error { return consume(ctx, db, key, hash) })
}
func user(id int64, provider, subject, nickname, avatar, status string) domain.User {
	u := domain.User{ID: id, Provider: provider, Nickname: nickname, AvatarURL: avatar, Status: status}
	if provider == "email" {
		u.Email = &subject
	}
	if provider == "phone" {
		u.PhoneNumber = &subject
	}
	return u
}
func identity(ctx context.Context, db *q.Queries, provider, subject string) (domain.Identity, error) {
	r, e := db.NativeIdentity(ctx, q.NativeIdentityParams{Provider: provider, Subject: subject})
	if errors.Is(e, pgx.ErrNoRows) {
		return domain.Identity{}, domain.ErrCredentials
	}
	return domain.Identity{User: user(r.UserID, r.Provider, r.Subject, r.Nickname, r.AvatarUrl, r.Status), Subject: r.Subject, PasswordHash: r.PasswordHash, AppleRefresh: r.AppleRefresh}, e
}
func (s *NativeStore) FindIdentity(ctx context.Context, p, sub string) (domain.Identity, error) {
	return identity(ctx, q.New(s.pool), p, sub)
}
func userLock(ctx context.Context, db *q.Queries, id int64) error {
	return db.NativeLock(ctx, fmt.Sprintf("user:%d", id))
}
func insertSession(ctx context.Context, db *q.Queries, s domain.Session) error {
	if s.FamilyID == "" {
		s.FamilyID = s.ID
	}
	if e := db.NativeInsertSession(ctx, q.NativeInsertSessionParams{ID: s.ID, UserID: s.UserID, Provider: s.Provider, RefreshHash: s.RefreshHash, AuthenticatedAt: ts(s.AuthenticatedAt), ExpiresAt: ts(s.ExpiresAt), FamilyID: s.FamilyID}); e != nil {
		return e
	}
	return db.NativeRememberRefresh(ctx, q.NativeRememberRefreshParams{RefreshHash: s.RefreshHash, UserID: s.UserID, FamilyID: s.FamilyID, ExpiresAt: ts(s.ExpiresAt)})
}

func (s *NativeStore) Login(ctx context.Context, m ports.LoginMutation) (u domain.User, err error) {
	err = s.transaction(ctx, func(db *q.Queries) error {
		if e := db.NativeLock(ctx, m.Provider+":"+m.Subject); e != nil {
			return e
		}
		if m.Provider == "apple" {
			latest, e := db.NativeLatestAppleAccountEvent(ctx, appleNotificationDigest(m.Subject))
			if e != nil && !errors.Is(e, pgx.ErrNoRows) {
				return e
			}
			if e == nil && (m.ProviderIssuedAt.IsZero() || !m.ProviderIssuedAt.After(latest.Time)) {
				return domain.ErrCredentials
			}
		}
		i, e := identity(ctx, db, m.Provider, m.Subject)
		exists := e == nil
		if e != nil && !errors.Is(e, domain.ErrCredentials) {
			return e
		}
		if exists {
			if e = userLock(ctx, db, i.User.ID); e != nil {
				return e
			}
			i, e = identity(ctx, db, m.Provider, m.Subject)
			if e != nil {
				return e
			}
			if i.User.Status != "active" {
				return domain.ErrCredentials
			}
		}
		if m.CodeKey != "" {
			if e = consume(ctx, db, m.CodeKey, m.CodeHash); e != nil {
				return e
			}
		}
		if exists && m.Register {
			return domain.ErrConflict
		}
		if m.Provider == "email" && !m.Register && (!exists || i.PasswordHash != m.ExpectedPassword) {
			return domain.ErrCredentials
		}
		if !exists {
			r, e := db.CreateUser(ctx, q.CreateUserParams{Openid: m.OpenID, Nickname: m.Nickname})
			if e != nil {
				return e
			}
			if e = db.NativeInsertIdentity(ctx, q.NativeInsertIdentityParams{UserID: r.ID, Provider: m.Provider, Subject: m.Subject, PasswordHash: m.PasswordHash, AppleRefresh: m.AppleRefresh}); e != nil {
				return e
			}
			u = user(r.ID, m.Provider, m.Subject, r.Nickname, "", r.Status)
		} else {
			u = i.User
			if len(m.AppleRefresh) > 0 {
				if e = db.NativeUpdateApple(ctx, q.NativeUpdateAppleParams{Provider: m.Provider, Subject: m.Subject, AppleRefresh: m.AppleRefresh}); e != nil {
					return e
				}
			}
		}
		if m.Provider == "apple" && !m.ProviderIssuedAt.IsZero() {
			if e = db.NativeRememberAppleAuthentication(ctx, q.NativeRememberAppleAuthenticationParams{Subject: m.Subject, Column2: ts(m.ProviderIssuedAt)}); e != nil {
				return e
			}
		}
		m.Session.UserID = u.ID
		m.Session.Provider = m.Provider
		return insertSession(ctx, db, m.Session)
	})
	return
}
func (s *NativeStore) ResetPassword(ctx context.Context, email, hash, password string) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		if e := db.NativeLock(ctx, "email:"+email); e != nil {
			return e
		}
		i, e := identity(ctx, db, "email", email)
		if e != nil {
			return e
		}
		if e = userLock(ctx, db, i.User.ID); e != nil {
			return e
		}
		if e = consume(ctx, db, "email:reset_password:"+email, hash); e != nil {
			return e
		}
		if i.User.Status != "active" {
			return domain.ErrCredentials
		}
		if e = db.NativeUpdatePassword(ctx, q.NativeUpdatePasswordParams{Subject: email, PasswordHash: password}); e != nil {
			return e
		}
		return db.NativeRevokeUser(ctx, i.User.ID)
	})
}
func (s *NativeStore) NewChallenge(ctx context.Context, id, hash string, expires time.Time) error {
	return q.New(s.pool).NativeNewChallenge(ctx, q.NativeNewChallengeParams{ID: id, NonceHash: hash, ExpiresAt: ts(expires)})
}
func (s *NativeStore) ConsumeChallenge(ctx context.Context, id string) (string, error) {
	v, e := q.New(s.pool).NativeConsumeChallenge(ctx, id)
	if errors.Is(e, pgx.ErrNoRows) {
		e = domain.ErrCredentials
	}
	return v, e
}
func session(ctx context.Context, db *q.Queries, id string) (domain.Session, domain.User, error) {
	r, e := db.NativeSession(ctx, id)
	if errors.Is(e, pgx.ErrNoRows) {
		e = domain.ErrCredentials
	}
	return domain.Session{ID: r.ID, FamilyID: r.FamilyID, UserID: r.UserID, Provider: r.Provider, RefreshHash: r.RefreshHash, AuthenticatedAt: r.AuthenticatedAt.Time, ExpiresAt: r.ExpiresAt.Time}, user(r.UserID, r.Provider, r.Subject, r.Nickname, r.AvatarUrl, r.Status), e
}
func (s *NativeStore) Session(ctx context.Context, id string) (domain.Session, domain.User, error) {
	return session(ctx, q.New(s.pool), id)
}
func (s *NativeStore) Rotate(ctx context.Context, oldHash, newHash, newID string) (ss domain.Session, u domain.User, err error) {
	err = s.transaction(ctx, func(db *q.Queries) error {
		r, e := db.NativeRefresh(ctx, oldHash)
		if errors.Is(e, pgx.ErrNoRows) {
			return domain.ErrCredentials
		}
		if e != nil {
			return e
		}
		if e = userLock(ctx, db, r.UserID); e != nil {
			return e
		}
		ss, u, e = session(ctx, db, r.ID)
		if e != nil {
			return e
		}
		if e = db.NativeDeleteSession(ctx, ss.ID); e != nil {
			return e
		}
		ss.ID = newID
		ss.RefreshHash = newHash
		return insertSession(ctx, db, ss)
	})
	return
}
func (s *NativeStore) Logout(ctx context.Context, hash string) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		r, e := db.NativeRefreshFamily(ctx, hash)
		if errors.Is(e, pgx.ErrNoRows) {
			return nil
		}
		if e != nil {
			return e
		}
		if e = userLock(ctx, db, r.UserID); e != nil {
			return e
		}
		return db.NativeRevokeFamily(ctx, r.FamilyID)
	})
}

func (s *NativeStore) Delete(ctx context.Context, id string, revoke func(context.Context, []byte) error) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		ss, _, e := session(ctx, db, id)
		if e != nil {
			return e
		}
		if e = userLock(ctx, db, ss.UserID); e != nil {
			return e
		}
		ss, u, e := session(ctx, db, id)
		if e != nil {
			return e
		}
		if time.Since(ss.AuthenticatedAt) > 5*time.Minute {
			return domain.ErrReauthenticate
		}
		if u.Provider == "apple" {
			sub, e := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: ss.UserID, Provider: "apple"})
			if e != nil {
				return e
			}
			i, e := identity(ctx, db, "apple", sub)
			if e != nil {
				return e
			}
			if revoke == nil {
				return domain.ErrUnavailable
			}
			if e = revoke(ctx, i.AppleRefresh); e != nil {
				return e
			}
		}
		var subject string
		if u.Email != nil {
			subject = *u.Email
		}
		if u.PhoneNumber != nil {
			subject = *u.PhoneNumber
		}
		for _, key := range []string{"email:register:" + subject, "email:reset_password:" + subject, "phone:login:" + subject} {
			if e = db.NativeDeleteCode(ctx, key); e != nil {
				return e
			}
		}
		return db.NativeDeleteUser(ctx, ss.UserID)
	})
}
func (s *NativeStore) Cleanup(ctx context.Context) error { return q.New(s.pool).NativeCleanup(ctx) }
func (s *NativeStore) FindIdentityByUser(ctx context.Context, id int64, provider string) (domain.Identity, error) {
	db := q.New(s.pool)
	sub, e := db.NativeSubjectByUser(ctx, q.NativeSubjectByUserParams{UserID: id, Provider: provider})
	if errors.Is(e, pgx.ErrNoRows) {
		e = domain.ErrCredentials
	}
	if e != nil {
		return domain.Identity{}, e
	}
	return identity(ctx, db, provider, sub)
}

func (s *NativeStore) ApplyAppleEvent(ctx context.Context, event domain.AppleNotification) error {
	return s.transaction(ctx, func(db *q.Queries) error {
		if event.ID == "" || event.Subject == "" || event.IssuedAt.IsZero() || (event.Type != "consent-revoked" && event.Type != "account-deleted") {
			return domain.ErrInvalid
		}
		if e := db.NativeLock(ctx, "apple:"+event.Subject); e != nil {
			return e
		}
		eventID := appleNotificationDigest(event.ID)
		subjectDigest := appleNotificationDigest(event.Subject)
		seen, e := db.NativeAppleNotificationExists(ctx, eventID)
		if e != nil {
			return e
		}
		if seen {
			return nil
		}
		if e = db.NativeInsertAppleNotification(ctx, q.NativeInsertAppleNotificationParams{
			ID: eventID, Subject: subjectDigest, EventType: event.Type, IssuedAt: ts(event.IssuedAt), EventTime: event.EventTime,
		}); e != nil {
			return e
		}
		appleIdentity, e := identity(ctx, db, "apple", event.Subject)
		if errors.Is(e, domain.ErrCredentials) {
			return nil
		}
		if e != nil {
			return e
		}
		if e = userLock(ctx, db, appleIdentity.User.ID); e != nil {
			return e
		}
		appleIdentity, e = identity(ctx, db, "apple", event.Subject)
		if errors.Is(e, domain.ErrCredentials) {
			return nil
		}
		if e != nil {
			return e
		}
		newerLogin, e := db.NativeAppleAuthenticationAfter(ctx, q.NativeAppleAuthenticationAfterParams{Subject: event.Subject, Column2: ts(event.IssuedAt)})
		if e != nil {
			return e
		}
		if newerLogin {
			return nil
		}
		if event.Type == "account-deleted" {
			return db.NativeDeleteUser(ctx, appleIdentity.User.ID)
		}
		if e = db.NativeRevokeUser(ctx, appleIdentity.User.ID); e != nil {
			return e
		}
		return db.NativeClearAppleRefresh(ctx, event.Subject)
	})
}
