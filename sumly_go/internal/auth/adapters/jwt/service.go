package jwt

import (
	"context"
	"errors"
	"fmt"
	"time"

	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	jwtlib "github.com/golang-jwt/jwt/v5"
)

const minimumSecretLength = 32

type Service struct {
	secret []byte
	ttl    time.Duration
	now    func() time.Time
}

type actorClaims struct {
	ActorKind    sharedauth.ActorKind `json:"actor_kind"`
	ActorID      int64                `json:"actor_id"`
	IsSuperAdmin bool                 `json:"is_super_admin,omitempty"`
	jwtlib.RegisteredClaims
}

func NewService(secret string, ttl time.Duration) (*Service, error) {
	if len(secret) < minimumSecretLength {
		return nil, fmt.Errorf("JWT secret must contain at least %d bytes", minimumSecretLength)
	}
	if ttl <= 0 {
		return nil, errors.New("JWT TTL must be positive")
	}
	return &Service{secret: []byte(secret), ttl: ttl, now: time.Now}, nil
}

func (s *Service) IssueUser(ctx context.Context, userID int64) (string, error) {
	return s.issue(ctx, sharedauth.Actor{Kind: sharedauth.ActorUser, ID: userID})
}

func (s *Service) IssueAdmin(ctx context.Context, adminID int64, isSuperAdmin bool) (string, error) {
	return s.issue(ctx, sharedauth.Actor{Kind: sharedauth.ActorAdmin, ID: adminID, IsSuperAdmin: isSuperAdmin})
}

func (s *Service) Parse(_ context.Context, tokenString string) (sharedauth.Actor, error) {
	claims := &actorClaims{}
	token, err := jwtlib.ParseWithClaims(
		tokenString,
		claims,
		func(token *jwtlib.Token) (any, error) {
			if token.Method != jwtlib.SigningMethodHS256 {
				return nil, fmt.Errorf("unexpected JWT signing method %s", token.Method.Alg())
			}
			return s.secret, nil
		},
		jwtlib.WithValidMethods([]string{jwtlib.SigningMethodHS256.Alg()}),
		jwtlib.WithExpirationRequired(),
	)
	if err != nil {
		return sharedauth.Actor{}, fmt.Errorf("parse JWT: %w", err)
	}
	if !token.Valid || claims.ActorID <= 0 {
		return sharedauth.Actor{}, errors.New("invalid JWT actor")
	}
	if claims.ActorKind != sharedauth.ActorUser && claims.ActorKind != sharedauth.ActorAdmin {
		return sharedauth.Actor{}, errors.New("invalid JWT actor kind")
	}
	return sharedauth.Actor{
		Kind:         claims.ActorKind,
		ID:           claims.ActorID,
		IsSuperAdmin: claims.IsSuperAdmin,
	}, nil
}

func (s *Service) issue(_ context.Context, actor sharedauth.Actor) (string, error) {
	now := s.now()
	claims := actorClaims{
		ActorKind:    actor.Kind,
		ActorID:      actor.ID,
		IsSuperAdmin: actor.IsSuperAdmin,
		RegisteredClaims: jwtlib.RegisteredClaims{
			IssuedAt:  jwtlib.NewNumericDate(now),
			ExpiresAt: jwtlib.NewNumericDate(now.Add(s.ttl)),
		},
	}
	token, err := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims).SignedString(s.secret)
	if err != nil {
		return "", fmt.Errorf("sign JWT: %w", err)
	}
	return token, nil
}
