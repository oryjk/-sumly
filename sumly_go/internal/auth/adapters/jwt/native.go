package jwt

import (
	"context"
	"errors"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	lib "github.com/golang-jwt/jwt/v5"
)

func (s *Service) IssueNative(_ context.Context, ss domain.Session) (string, error) {
	now := s.now()
	return lib.NewWithClaims(lib.SigningMethodHS256, actorClaims{SessionID: ss.ID, Native: true, ActorKind: sharedauth.ActorUser, ActorID: ss.UserID, RegisteredClaims: lib.RegisteredClaims{Issuer: "sumly-native", Audience: lib.ClaimStrings{"sumly-app"}, IssuedAt: lib.NewNumericDate(now), ExpiresAt: lib.NewNumericDate(now.Add(15 * time.Minute))}}).SignedString(s.secret)
}
func (s *Service) ParseNative(_ context.Context, raw string) (string, error) {
	if len(raw) > 8192 {
		return "", domain.ErrCredentials
	}
	c := &actorClaims{}
	t, e := lib.ParseWithClaims(raw, c, func(t *lib.Token) (any, error) { return s.secret, nil }, lib.WithValidMethods([]string{"HS256"}), lib.WithExpirationRequired(), lib.WithIssuer("sumly-native"), lib.WithAudience("sumly-app"), lib.WithIssuedAt(), lib.WithTimeFunc(s.now))
	if e != nil || !t.Valid || !c.Native || c.SessionID == "" || c.ActorID <= 0 || c.ActorKind != sharedauth.ActorUser || c.IssuedAt == nil {
		return "", domain.ErrCredentials
	}
	return c.SessionID, nil
}

// LiveTokens makes revocation apply to existing authenticated app routes too.
type LiveTokens struct {
	*Service
	Store ports.NativeStore
}

func (s LiveTokens) Parse(ctx context.Context, raw string) (sharedauth.Actor, error) {
	id, e := s.ParseNative(ctx, raw)
	if e == nil {
		ss, _, e := s.Store.Session(ctx, id)
		if e != nil {
			return sharedauth.Actor{}, e
		}
		return sharedauth.Actor{Kind: sharedauth.ActorUser, ID: ss.UserID}, nil
	}
	actor, e := s.Service.Parse(ctx, raw)
	if e != nil {
		return sharedauth.Actor{}, errors.New("unauthorized")
	}
	return actor, nil
}
