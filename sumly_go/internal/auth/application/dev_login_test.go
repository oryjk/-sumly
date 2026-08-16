package application

import (
	"context"
	"strings"
	"testing"

	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
)

func TestDevLoginCreatesMissingUserWithPrefixedOpenID(t *testing.T) {
	users := newFakeUsers()
	tokens := &fakeTokenService{token: "jwt-1"}
	useCase := NewDevLogin(users, tokens)

	result, err := useCase.Execute(context.Background(), "test-user-01")
	if err != nil {
		t.Fatalf("execute dev login: %v", err)
	}
	if result.Token != "jwt-1" {
		t.Fatalf("expected jwt-1, got %s", result.Token)
	}
	if users.created.OpenID != "dev-test-user-01" {
		t.Fatalf("expected created openid dev-test-user-01, got %s", users.created.OpenID)
	}
}

func TestDevLoginReturnsExistingUserWithoutRecreating(t *testing.T) {
	users := newFakeUsers()
	users.byOpenID["dev-test-user-01"] = userdomain.User{ID: 9, OpenID: "dev-test-user-01", Status: userdomain.StatusActive}
	useCase := NewDevLogin(users, &fakeTokenService{token: "jwt-1"})

	result, err := useCase.Execute(context.Background(), "test-user-01")
	if err != nil {
		t.Fatalf("execute dev login: %v", err)
	}
	if result.User.ID != 9 {
		t.Fatalf("expected existing user 9, got %d", result.User.ID)
	}
	if users.created.OpenID != "" {
		t.Fatalf("expected no user creation, got %+v", users.created)
	}
}

func TestDevLoginRejectsEmptyIdentifier(t *testing.T) {
	useCase := NewDevLogin(newFakeUsers(), &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), "  "); err == nil {
		t.Fatal("expected empty identifier to fail")
	}
}

func TestDevLoginRejectsTooLongIdentifier(t *testing.T) {
	useCase := NewDevLogin(newFakeUsers(), &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), strings.Repeat("a", 121)); err == nil {
		t.Fatal("expected identifier longer than 120 characters to fail")
	}
}

func TestDevLoginRejectsFrozenUser(t *testing.T) {
	users := newFakeUsers()
	users.byOpenID["dev-test-user-01"] = userdomain.User{ID: 9, OpenID: "dev-test-user-01", Status: userdomain.StatusFrozen}
	useCase := NewDevLogin(users, &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), "test-user-01"); err == nil {
		t.Fatal("expected frozen user login to fail")
	}
}
