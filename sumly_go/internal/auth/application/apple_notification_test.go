package application

import (
	"context"
	"errors"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

type notificationApple struct {
	ports.AppleGateway
	event domain.AppleNotification
	err   error
}

func (notificationApple) Enabled() bool { return false }
func (a notificationApple) VerifyNotification(context.Context, string) (domain.AppleNotification, error) {
	return a.event, a.err
}

type notificationStore struct {
	ports.NativeStore
	event domain.AppleNotification
	err   error
	calls int
}

func (s *notificationStore) ApplyAppleEvent(_ context.Context, event domain.AppleNotification) error {
	s.event, s.calls = event, s.calls+1
	return s.err
}

func TestAppleNotificationAppliesAccountEventsAndIgnoresEmailEvents(t *testing.T) {
	ctx := context.Background()
	for _, kind := range []string{"consent-revoked", "account-deleted"} {
		store := &notificationStore{}
		accounts := Accounts{Store: store, Apple: notificationApple{event: domain.AppleNotification{ID: "event-" + kind, Type: kind, Subject: "apple-subject"}}}
		if err := accounts.HandleAppleNotification(ctx, "signed"); err != nil {
			t.Fatal(err)
		}
		if store.calls != 1 || store.event.Subject != "apple-subject" || store.event.Type != kind {
			t.Fatalf("%s not applied: %+v", kind, store)
		}
	}
	for _, kind := range []string{"email-enabled", "email-disabled"} {
		store := &notificationStore{}
		accounts := Accounts{Store: store, Apple: notificationApple{event: domain.AppleNotification{ID: "event-" + kind, Type: kind, Subject: "apple-subject"}}}
		if err := accounts.HandleAppleNotification(ctx, "signed"); err != nil {
			t.Fatal(err)
		}
		if store.calls != 0 {
			t.Fatalf("%s unexpectedly mutated account", kind)
		}
	}
}

func TestAppleNotificationRejectsUnverifiedOrUnknownEvents(t *testing.T) {
	ctx := context.Background()
	store := &notificationStore{}
	accounts := Accounts{Store: store, Apple: notificationApple{err: domain.ErrCredentials}}
	if err := accounts.HandleAppleNotification(ctx, "bad"); !errors.Is(err, domain.ErrCredentials) {
		t.Fatal(err)
	}
	accounts.Apple = notificationApple{event: domain.AppleNotification{Type: "future-event", Subject: "apple-subject"}}
	if err := accounts.HandleAppleNotification(ctx, "signed"); !errors.Is(err, domain.ErrInvalid) {
		t.Fatalf("unknown event: %v", err)
	}
	if store.calls != 0 {
		t.Fatal("untrusted/unknown event changed account")
	}
}
