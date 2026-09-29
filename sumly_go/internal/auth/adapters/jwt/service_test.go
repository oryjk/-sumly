package jwt

import (
	"context"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/domain"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
)

const testSecret = "01234567890123456789012345678901"

func TestServiceRoundTripsUserActor(t *testing.T) {
	service, err := NewService(testSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	token, err := service.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue user token: %v", err)
	}

	actor, err := service.Parse(context.Background(), token)
	if err != nil {
		t.Fatalf("parse user token: %v", err)
	}
	expected := sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 42}
	if actor != expected {
		t.Fatalf("expected actor %+v, got %+v", expected, actor)
	}
}

func TestServiceRoundTripsSuperAdminActor(t *testing.T) {
	service, err := NewService(testSecret, time.Hour)
	if err != nil {
		t.Fatalf("create JWT service: %v", err)
	}
	token, err := service.IssueAdmin(context.Background(), 7, true)
	if err != nil {
		t.Fatalf("issue admin token: %v", err)
	}

	actor, err := service.Parse(context.Background(), token)
	if err != nil {
		t.Fatalf("parse admin token: %v", err)
	}
	expected := sharedauth.Actor{Kind: sharedauth.ActorAdmin, ID: 7, IsSuperAdmin: true}
	if actor != expected {
		t.Fatalf("expected actor %+v, got %+v", expected, actor)
	}
}

func TestServiceRejectsTokenSignedWithAnotherSecret(t *testing.T) {
	issuer, err := NewService(testSecret, time.Hour)
	if err != nil {
		t.Fatalf("create issuer: %v", err)
	}
	parser, err := NewService("abcdefghijklmnopqrstuvwxyz123456", time.Hour)
	if err != nil {
		t.Fatalf("create parser: %v", err)
	}
	token, err := issuer.IssueUser(context.Background(), 42)
	if err != nil {
		t.Fatalf("issue token: %v", err)
	}

	if _, err := parser.Parse(context.Background(), token); err == nil {
		t.Fatal("expected invalid signature error")
	}
}

func TestServiceRejectsShortSecret(t *testing.T) {
	if _, err := NewService("too-short", time.Hour); err == nil {
		t.Fatal("expected short secret error")
	}
}

func TestLegacyParserRejectsNativeSessionTokens(t *testing.T) {
	s, _ := NewService("01234567890123456789012345678901", time.Hour)
	token, e := s.IssueNative(context.Background(), domain.Session{ID: "session", UserID: 1})
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.Parse(context.Background(), token); e == nil {
		t.Fatal("native token accepted without live session check")
	}
	if id, e := s.ParseNative(context.Background(), token); e != nil || id != "session" {
		t.Fatal(id, e)
	}
	legacy, _ := s.IssueUser(context.Background(), 1)
	if _, e = s.ParseNative(context.Background(), legacy); e == nil {
		t.Fatal("legacy token accepted as native")
	}
}
