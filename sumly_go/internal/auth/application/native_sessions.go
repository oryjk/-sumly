package application

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type Sessions struct {
	Store  ports.NativeStore
	Crypto ports.Cryptography
	Tokens ports.NativeTokens
	Apple  ports.AppleGateway
}

func (s Sessions) New() (domain.Session, string) {
	r := s.Crypto.Random()
	return domain.Session{ID: s.Crypto.Random(), RefreshHash: s.Crypto.Digest("refresh", r), AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(30 * 24 * time.Hour)}, r
}
func (s Sessions) Result(ctx context.Context, ss domain.Session, r string, u domain.User) (domain.LoginResult, error) {
	ss.UserID = u.ID
	ss.Provider = u.Provider
	t, e := s.Tokens.IssueNative(ctx, ss)
	return domain.LoginResult{Token: t, RefreshToken: r, ExpiresIn: 900, User: u}, e
}
func (s Sessions) Refresh(ctx context.Context, token string) (domain.LoginResult, error) {
	if len(token) < 43 || len(token) > 256 {
		return domain.LoginResult{}, domain.ErrCredentials
	}
	r := s.Crypto.Random()
	ss, u, e := s.Store.Rotate(ctx, s.Crypto.Digest("refresh", token), s.Crypto.Digest("refresh", r), s.Crypto.Random())
	if e != nil {
		return domain.LoginResult{}, e
	}
	return s.Result(ctx, ss, r, u)
}
func (s Sessions) Logout(ctx context.Context, token string) error {
	if len(token) > 256 {
		return domain.ErrInvalid
	}
	return s.Store.Logout(ctx, s.Crypto.Digest("refresh", token))
}
func (s Sessions) Me(ctx context.Context, token string) (domain.User, error) {
	id, e := s.Tokens.ParseNative(ctx, token)
	if e != nil {
		return domain.User{}, domain.ErrCredentials
	}
	_, u, e := s.Store.Session(ctx, id)
	return u, e
}
func (s Sessions) Delete(ctx context.Context, token, confirmation string) error {
	if confirmation != "DELETE" {
		return domain.ErrInvalid
	}
	id, e := s.Tokens.ParseNative(ctx, token)
	if e != nil {
		return domain.ErrCredentials
	}
	ss, _, e := s.Store.Session(ctx, id)
	if e != nil {
		return e
	}
	if time.Since(ss.AuthenticatedAt) > 5*time.Minute {
		return domain.ErrReauthenticate
	}
	return s.Store.Delete(ctx, id, func(ctx context.Context, encrypted []byte) error {
		if s.Apple == nil || !s.Apple.Enabled() {
			return domain.ErrUnavailable
		}
		r, e := s.Crypto.Open(encrypted)
		if e != nil {
			return domain.ErrUnavailable
		}
		if e = s.Apple.Revoke(ctx, r); e != nil {
			return domain.ErrUnavailable
		}
		return nil
	})
}
