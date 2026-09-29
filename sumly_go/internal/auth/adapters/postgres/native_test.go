package postgres_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	nativejwt "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
)

func TestPersistentCodesQuotasAndSessions(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	s := postgres.NewNativeStore(p)
	ctx := context.Background()
	if e := s.PutCode(ctx, "phone:a", "good", time.Now().Add(time.Minute)); e != nil {
		t.Fatal(e)
	}
	if e := s.ConsumeCode(ctx, "phone:a", "good"); !errors.Is(e, domain.ErrCredentials) {
		t.Fatal("pending code usable", e)
	}
	if e := s.ActivateCode(ctx, "phone:a", "good"); e != nil {
		t.Fatal(e)
	}
	for i := 0; i < 5; i++ {
		if e := s.ConsumeCode(ctx, "phone:a", "bad"); !errors.Is(e, domain.ErrCredentials) {
			t.Fatal(e)
		}
	}
	if e := s.ConsumeCode(ctx, "phone:a", "good"); !errors.Is(e, domain.ErrCredentials) {
		t.Fatal("guess limit", e)
	}
	if e := s.PutCode(ctx, "phone:a", "new", time.Now().Add(time.Minute)); e != nil {
		t.Fatal(e)
	}
	_ = s.ActivateCode(ctx, "phone:a", "new")
	var wins atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			if s.ConsumeCode(ctx, "phone:a", "new") == nil {
				wins.Add(1)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Fatal("code winners", wins.Load())
	}
	q := []domain.Quota{{Key: "destination", Limit: 5, Window: time.Hour}}
	for i := 0; i < 5; i++ {
		if e := s.TakeQuota(ctx, q); e != nil {
			t.Fatal(e)
		}
	}
	if !errors.Is(s.TakeQuota(ctx, q), domain.ErrLimited) {
		t.Fatal("quota bypass")
	}
	session := domain.Session{ID: "sid", RefreshHash: "r1", AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(30 * 24 * time.Hour)}
	u, e := s.Login(ctx, ports.LoginMutation{Provider: "email", Subject: "a@example.com", PasswordHash: "hash", Register: true, OpenID: "native-random", Session: session})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.Login(ctx, ports.LoginMutation{Provider: "email", Subject: "a@example.com", PasswordHash: "overwrite", Register: true, OpenID: "native-other", Session: session}); !errors.Is(e, domain.ErrConflict) {
		t.Fatal("duplicate", e)
	}
	wins.Store(0)
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			if _, _, e := s.Rotate(ctx, "r1", "r2", "sid2"); e == nil {
				wins.Add(1)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Fatal("refresh winners", wins.Load())
	}
	if _, _, e = s.Session(ctx, "sid"); e == nil {
		t.Fatal("rotated session alive")
	}
	ss, got, e := s.Session(ctx, "sid2")
	if e != nil || got.ID != u.ID || !ss.ExpiresAt.Equal(session.ExpiresAt.Truncate(time.Microsecond)) {
		t.Fatal("rotation lifetime", e)
	}
	if e = s.Logout(ctx, "r1"); e != nil {
		t.Fatal(e)
	}
	if _, _, e = s.Session(ctx, "sid2"); e == nil {
		t.Fatal("logout not revoked")
	}
}

func TestEmailLifecycleAtomicityAndDeletion(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	s := postgres.NewNativeStore(p)
	ctx := context.Background()
	put := func(key, hash string, expiry time.Time) {
		t.Helper()
		if e := s.PutCode(ctx, key, hash, expiry); e != nil {
			t.Fatal(e)
		}
		if e := s.ActivateCode(ctx, key, hash); e != nil {
			t.Fatal(e)
		}
	}
	put("expired", "code", time.Now().Add(-time.Second))
	if s.ConsumeCode(ctx, "expired", "code") == nil {
		t.Fatal("expired OTP accepted")
	}
	put("email:register:a@example.com", "register", time.Now().Add(time.Minute))
	var wins atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Go(func() {
			_, e := s.Login(ctx, ports.LoginMutation{Provider: "email", Subject: "a@example.com", CodeKey: "email:register:a@example.com", CodeHash: "register", Register: true, PasswordHash: "old", OpenID: "native-a", Session: domain.Session{ID: "one", RefreshHash: "refresh", AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}})
			if e == nil {
				wins.Add(1)
			}
		})
	}
	wg.Wait()
	if wins.Load() != 1 {
		t.Fatal("registration winners", wins.Load())
	}
	put("email:reset_password:a@example.com", "reset", time.Now().Add(time.Minute))
	if e := s.ResetPassword(ctx, "a@example.com", "reset", "new"); e != nil {
		t.Fatal(e)
	}
	if _, _, e := s.Session(ctx, "one"); e == nil {
		t.Fatal("reset did not revoke")
	}
	if e := s.ResetPassword(ctx, "a@example.com", "reset", "hijack"); e == nil {
		t.Fatal("reset replay")
	}
	mutation := ports.LoginMutation{Provider: "email", Subject: "a@example.com", ExpectedPassword: "old", Session: domain.Session{ID: "new", RefreshHash: "newrefresh", AuthenticatedAt: time.Now().Add(-6 * time.Minute), ExpiresAt: time.Now().Add(time.Hour)}}
	if _, e := s.Login(ctx, mutation); e == nil {
		t.Fatal("stale password accepted")
	}
	mutation.ExpectedPassword = "new"
	u, e := s.Login(ctx, mutation)
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Delete(ctx, "new", nil); !errors.Is(e, domain.ErrReauthenticate) {
		t.Fatal("delete stale primary auth", e)
	}
	if _, e = p.Exec(ctx, "UPDATE users SET status='frozen' WHERE id=$1", u.ID); e != nil {
		t.Fatal(e)
	}
	if _, _, e = s.Session(ctx, "new"); e == nil {
		t.Fatal("frozen session")
	}
	if _, e = s.Login(ctx, mutation); e == nil {
		t.Fatal("frozen login")
	}
	if _, e = p.Exec(ctx, "UPDATE users SET status='active' WHERE id=$1", u.ID); e != nil {
		t.Fatal(e)
	}
	mutation.Session.ID = "fresh"
	mutation.Session.RefreshHash = "freshrefresh"
	mutation.Session.AuthenticatedAt = time.Now()
	if _, e = s.Login(ctx, mutation); e != nil {
		t.Fatal(e)
	}
	if e = s.Delete(ctx, "fresh", nil); e != nil {
		t.Fatal(e)
	}
	if _, _, e = s.Session(ctx, "fresh"); e == nil {
		t.Fatal("deleted session")
	}
	if _, e = s.FindIdentity(ctx, "email", "a@example.com"); e == nil {
		t.Fatal("deleted identity")
	}
}

func TestNativeUseCaseLifecycle(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	store := postgres.NewNativeStore(p)
	crypto, _ := credentials.New(strings.Repeat("s", 32))
	tokens, _ := nativejwt.NewService(strings.Repeat("s", 32), time.Hour)
	delivery := &fakeDelivery{}
	codes := application.Codes{Store: store, Crypto: crypto, Email: delivery, Phone: delivery}
	sessions := application.Sessions{Store: store, Crypto: crypto, Tokens: tokens}
	dummy, _ := crypto.HashPassword("dummy-password-long")
	accounts := application.Accounts{Store: store, Crypto: crypto, Codes: codes, Sessions: sessions, DummyHash: dummy}
	ctx := context.Background()
	if e := codes.Send(ctx, "email", " A@EXAMPLE.COM ", "register", "127.0.0.1"); e != nil {
		t.Fatal(e)
	}
	if e := codes.Send(ctx, "email", "a@example.com", "register", "127.0.0.1"); !errors.Is(e, domain.ErrLimited) {
		t.Fatal("cooldown", e)
	}
	if _, e := accounts.Register(ctx, "a@example.com", "password-long-enough", "000bad", "127.0.0.1"); e == nil {
		t.Fatal("wrong code")
	}
	result, e := accounts.Register(ctx, "a@example.com", "password-long-enough", delivery.code, "127.0.0.1")
	if e != nil {
		t.Fatal(e)
	}
	if result.ExpiresIn != 900 || result.User.Email == nil || *result.User.Email != "a@example.com" {
		t.Fatal("contract")
	}
	if _, e = accounts.EmailLogin(ctx, "a@example.com", "incorrect-password", "127.0.0.1"); !errors.Is(e, domain.ErrCredentials) {
		t.Fatal(e)
	}
	if _, e = accounts.EmailLogin(ctx, "unknown@example.com", "incorrect-password", "127.0.0.1"); !errors.Is(e, domain.ErrCredentials) {
		t.Fatal(e)
	}
	logged, e := accounts.EmailLogin(ctx, "a@example.com", "password-long-enough", "127.0.0.1")
	if e != nil || logged.User.ID != result.User.ID {
		t.Fatal(e)
	}
	refreshed, e := sessions.Refresh(ctx, logged.RefreshToken)
	if e != nil {
		t.Fatal(e)
	}
	if _, e = sessions.Refresh(ctx, logged.RefreshToken); e == nil {
		t.Fatal("refresh replay")
	}
	live := nativejwt.LiveTokens{Service: tokens, Store: store}
	if _, e = live.Parse(ctx, refreshed.Token); e != nil {
		t.Fatal(e)
	}
	if e = sessions.Logout(ctx, logged.RefreshToken); e != nil {
		t.Fatal(e)
	}
	if _, e = live.Parse(ctx, refreshed.Token); e == nil {
		t.Fatal("logout race token alive")
	}
	key := "email:reset_password:a@example.com"
	hash := crypto.Digest("otp", key+":123456")
	_ = store.PutCode(ctx, key, hash, time.Now().Add(time.Minute))
	_ = store.ActivateCode(ctx, key, hash)
	if e = accounts.Reset(ctx, "a@example.com", "new-password-long", "123456", "127.0.0.1"); e != nil {
		t.Fatal(e)
	}
	if _, e = sessions.Me(ctx, result.Token); e == nil {
		t.Fatal("reset session alive")
	}
	logged, e = accounts.EmailLogin(ctx, "a@example.com", "new-password-long", "127.0.0.1")
	if e != nil {
		t.Fatal(e)
	}
	if e = sessions.Delete(ctx, logged.Token, "no"); !errors.Is(e, domain.ErrInvalid) {
		t.Fatal("confirmation", e)
	}
	if e = sessions.Delete(ctx, logged.Token, "DELETE"); e != nil {
		t.Fatal(e)
	}
	if _, e = sessions.Me(ctx, logged.Token); e == nil {
		t.Fatal("deleted session alive")
	}
	if e = codes.Send(ctx, "phone", "13800138000", "login", "127.0.0.1"); e != nil {
		t.Fatal(e)
	}
	phone, e := accounts.PhoneLogin(ctx, "+8613800138000", delivery.code, "127.0.0.1")
	if e != nil || phone.User.Provider != "phone" || phone.User.PhoneNumber == nil {
		t.Fatal(e)
	}
	if _, e = accounts.PhoneLogin(ctx, "13800138000", delivery.code, "127.0.0.1"); e == nil {
		t.Fatal("phone code replay")
	}
}

type fakeDelivery struct{ code string }

func (*fakeDelivery) Enabled() bool                                     { return true }
func (f *fakeDelivery) Send(_ context.Context, _, code, _ string) error { f.code = code; return nil }

func TestAppleServerNotificationRevokesOrDeletesAccountIdempotently(t *testing.T) {
	p := testsupport.OpenTestPostgres(t)
	s := postgres.NewNativeStore(p)
	ctx := context.Background()
	base := time.Now().UTC().Truncate(time.Second)
	newApple := func(subject, sessionID string, issuedAt time.Time) domain.User {
		t.Helper()
		u, err := s.Login(ctx, ports.LoginMutation{
			Provider: "apple", Subject: subject, OpenID: "native-" + sessionID, AppleRefresh: []byte("encrypted-refresh"), ProviderIssuedAt: issuedAt,
			Session: domain.Session{ID: sessionID, RefreshHash: "refresh-" + sessionID, AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)},
		})
		if err != nil {
			t.Fatal(err)
		}
		return u
	}

	u := newApple("apple-consent", "consent-session", base.Add(-time.Minute))
	revoke := domain.AppleNotification{ID: "evt-consent", Type: "consent-revoked", Subject: "apple-consent", IssuedAt: base, EventTime: base.UnixMilli()}
	if err := s.ApplyAppleEvent(ctx, revoke); err != nil {
		t.Fatal(err)
	}
	var storedEventID, storedSubject string
	if err := p.QueryRow(ctx, "SELECT id, subject FROM auth_apple_notifications WHERE event_type=$1", "consent-revoked").Scan(&storedEventID, &storedSubject); err != nil {
		t.Fatal(err)
	}
	if storedEventID == revoke.ID || storedSubject == revoke.Subject {
		t.Fatal("raw Apple notification identifiers persisted")
	}
	if _, _, err := s.Session(ctx, "consent-session"); err == nil {
		t.Fatal("consent-revoked left session alive")
	}
	identity, err := s.FindIdentity(ctx, "apple", "apple-consent")
	if err != nil || identity.User.ID != u.ID || len(identity.AppleRefresh) != 0 {
		t.Fatalf("identity after revoke = %+v err=%v", identity, err)
	}

	// A fresh Apple credential issued after the event may reauthenticate.
	newApple("apple-consent", "after-consent", base.Add(time.Minute))
	// Redelivery of the same notification must not revoke the newly established session.
	if err := s.ApplyAppleEvent(ctx, revoke); err != nil {
		t.Fatal("repeat revoke must be idempotent", err)
	}
	if _, _, err := s.Session(ctx, "after-consent"); err != nil {
		t.Fatal("redelivery revoked fresh session", err)
	}

	// A distinct notification that was signed before the newer Apple login but delivered later is stale too.
	delayedOld := domain.AppleNotification{ID: "evt-consent-delayed", Type: "consent-revoked", Subject: "apple-consent", IssuedAt: base.Add(-30 * time.Second), EventTime: base.Add(-30 * time.Second).UnixMilli()}
	if err := s.ApplyAppleEvent(ctx, delayedOld); err != nil {
		t.Fatal("delayed old notification", err)
	}
	if _, _, err := s.Session(ctx, "after-consent"); err != nil {
		t.Fatal("older first-delivery notification revoked newer login", err)
	}

	// A login whose Apple credential predates the latest destructive notification must not land after it.
	if _, err := s.Login(ctx, ports.LoginMutation{
		Provider: "apple", Subject: "apple-consent", OpenID: "stale-openid", AppleRefresh: []byte("stale"), ProviderIssuedAt: base.Add(-time.Second),
		Session: domain.Session{ID: "stale-session", RefreshHash: "stale-refresh", AuthenticatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)},
	}); !errors.Is(err, domain.ErrCredentials) {
		t.Fatalf("stale Apple login accepted: %v", err)
	}

	deleted := newApple("apple-deleted", "deleted-session", base.Add(-time.Minute))
	deletion := domain.AppleNotification{ID: "evt-delete", Type: "account-deleted", Subject: "apple-deleted", IssuedAt: base, EventTime: base.UnixMilli()}
	if err := s.ApplyAppleEvent(ctx, deletion); err != nil {
		t.Fatal(err)
	}
	if _, err := s.FindIdentity(ctx, "apple", "apple-deleted"); err == nil {
		t.Fatal("deleted Apple identity remains")
	}
	var count int
	if err := p.QueryRow(ctx, "SELECT count(*) FROM users WHERE id=$1", deleted.ID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("deleted user count=%d err=%v", count, err)
	}

	// Recreate after Apple issues a newer credential; replaying the old deletion must not delete it again.
	recreated := newApple("apple-deleted", "recreated-session", base.Add(time.Minute))
	if err := s.ApplyAppleEvent(ctx, deletion); err != nil {
		t.Fatal("repeat deletion must be idempotent", err)
	}
	if _, _, err := s.Session(ctx, "recreated-session"); err != nil {
		t.Fatal("replayed deletion removed recreated session", err)
	}
	if got, err := s.FindIdentity(ctx, "apple", "apple-deleted"); err != nil || got.User.ID != recreated.ID {
		t.Fatalf("recreated identity lost: %+v %v", got, err)
	}
}
