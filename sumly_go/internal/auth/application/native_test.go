package application

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type failingStore struct {
	ports.NativeStore
	quotaErr  error
	put       bool
	activated bool
}

func (f *failingStore) TakeQuota(context.Context, []domain.Quota) error { return f.quotaErr }
func (f *failingStore) PutCode(context.Context, string, string, time.Time) error {
	f.put = true
	return nil
}
func (f *failingStore) ActivateCode(context.Context, string, string) error {
	f.activated = true
	return nil
}

type sender struct {
	enabled bool
	err     error
}

func (s sender) Enabled() bool                                      { return s.enabled }
func (s sender) Send(context.Context, string, string, string) error { return s.err }
func TestCodeDeliveryFailsClosed(t *testing.T) {
	c, _ := credentials.New(strings.Repeat("s", 32))
	ctx := context.Background()
	for _, tc := range []struct {
		name  string
		s     sender
		quota error
		want  error
		put   bool
	}{
		{"disabled", sender{}, nil, domain.ErrUnavailable, false},
		{"quota unavailable", sender{enabled: true}, domain.ErrUnavailable, domain.ErrUnavailable, false},
		{"delivery failed", sender{true, errors.New("provider failed")}, nil, domain.ErrUnavailable, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &failingStore{quotaErr: tc.quota}
			codes := Codes{Store: store, Crypto: c, Phone: tc.s}
			e := codes.Send(ctx, "phone", "13800138000", "login", "127.0.0.1")
			if !errors.Is(e, tc.want) || store.put != tc.put || store.activated {
				t.Fatalf("delivery not fail closed: %v", e)
			}
		})
	}
}

type deletionTokens struct{ ports.NativeTokens }

func (deletionTokens) ParseNative(context.Context, string) (string, error) { return "sid", nil }

type deletionStore struct {
	ports.NativeStore
	deleted bool
}

func (d *deletionStore) Session(context.Context, string) (domain.Session, domain.User, error) {
	return domain.Session{AuthenticatedAt: time.Now()}, domain.User{ID: 1, Provider: "apple"}, nil
}
func (d *deletionStore) FindIdentityByUser(context.Context, int64, string) (domain.Identity, error) {
	return domain.Identity{}, errors.New("identity must be read inside deletion transaction")
}
func (d *deletionStore) Delete(ctx context.Context, id string, revoke func(context.Context, []byte) error) error {
	if e := revoke(ctx, []byte("encrypted")); e != nil {
		return e
	}
	d.deleted = true
	return nil
}

type deletionCrypto struct{ ports.Cryptography }

func (deletionCrypto) Open([]byte) (string, error) { return "refresh", nil }

type deletionApple struct {
	ports.AppleGateway
	fail bool
}

func (deletionApple) Enabled() bool { return true }
func (a deletionApple) Revoke(context.Context, string) error {
	if a.fail {
		return domain.ErrUnavailable
	}
	return nil
}
func TestDeletionRevokesInsideTransactionAndFailsClosed(t *testing.T) {
	for _, fail := range []bool{false, true} {
		store := &deletionStore{}
		s := Sessions{Store: store, Tokens: deletionTokens{}, Crypto: deletionCrypto{}, Apple: deletionApple{fail: fail}}
		e := s.Delete(context.Background(), "token", "DELETE")
		if (e == nil) == fail || store.deleted == fail {
			t.Fatalf("atomic deletion: fail=%v err=%v deleted=%v", fail, e, store.deleted)
		}
	}
}

type challengeStore struct {
	ports.NativeStore
	counts map[string]int
}

func (s *challengeStore) TakeQuota(_ context.Context, qs []domain.Quota) error {
	for _, q := range qs {
		if s.counts[q.Key] >= q.Limit {
			return domain.ErrLimited
		}
	}
	for _, q := range qs {
		s.counts[q.Key]++
	}
	return nil
}
func (*challengeStore) NewChallenge(context.Context, string, string, time.Time) error { return nil }
func TestAppleChallengeLimitsDoNotShareIdentityBudgetAcrossUsers(t *testing.T) {
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	store := &challengeStore{counts: map[string]int{}}
	a := Accounts{Store: store, Crypto: crypto, Apple: deletionApple{}}
	for i := 0; i < 21; i++ {
		if _, e := a.Challenge(context.Background(), fmt.Sprintf("192.0.2.%d", i)); e != nil {
			t.Fatal("independent user denied", i, e)
		}
	}
}

type appleOutageStore struct{ ports.NativeStore }

func (appleOutageStore) TakeQuota(context.Context, []domain.Quota) error          { return nil }
func (appleOutageStore) ConsumeChallenge(context.Context, string) (string, error) { return "hash", nil }

type appleOutage struct{ ports.AppleGateway }

func (appleOutage) Enabled() bool { return true }
func (appleOutage) Verify(context.Context, string, string, string) (ports.AppleIdentity, error) {
	return ports.AppleIdentity{}, domain.ErrUnavailable
}
func TestAppleOutageDoesNotClaimInvalidCredentials(t *testing.T) {
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	a := Accounts{Store: appleOutageStore{}, Crypto: crypto, Apple: appleOutage{}}
	if _, e := a.AppleLogin(context.Background(), "id", "token", "code", "", "ip"); !errors.Is(e, domain.ErrUnavailable) {
		t.Fatal(e)
	}
}
