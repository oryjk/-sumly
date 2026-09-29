package ports

import (
	"context"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
)

// NativeStore operations are atomic; credentials and sessions never depend on process memory.
type NativeStore interface {
	TakeQuota(context.Context, []domain.Quota) error
	PutCode(context.Context, string, string, time.Time) error
	ActivateCode(context.Context, string, string) error
	ConsumeCode(context.Context, string, string) error
	FindIdentityByUser(context.Context, int64, string) (domain.Identity, error)
	FindIdentity(context.Context, string, string) (domain.Identity, error)
	Login(context.Context, LoginMutation) (domain.User, error)
	ResetPassword(context.Context, string, string, string) error
	NewChallenge(context.Context, string, string, time.Time) error
	ConsumeChallenge(context.Context, string) (string, error)
	Rotate(context.Context, string, string, string) (domain.Session, domain.User, error)
	Session(context.Context, string) (domain.Session, domain.User, error)
	Logout(context.Context, string) error
	Delete(context.Context, string, func(context.Context, []byte) error) error
}
type LoginMutation struct {
	Provider, Subject, Nickname, PasswordHash, ExpectedPassword, CodeKey, CodeHash, OpenID string
	AppleRefresh                                                                           []byte
	Session                                                                                domain.Session
	Register                                                                               bool
}
type Cryptography interface {
	Random() string
	Digest(string, string) string
	HashPassword(string) (string, error)
	CheckPassword(string, string) bool
	Seal(string) ([]byte, error)
	Open([]byte) (string, error)
}
type NativeTokens interface {
	IssueNative(context.Context, domain.Session) (string, error)
	ParseNative(context.Context, string) (string, error)
}
type CodeSender interface {
	Enabled() bool
	Send(context.Context, string, string, string) error
}
type AppleIdentity struct{ Subject, RefreshToken string }
type AppleGateway interface {
	Enabled() bool
	Verify(context.Context, string, string, string) (AppleIdentity, error)
	Revoke(context.Context, string) error
}
