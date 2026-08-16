package application

import (
	"context"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	userports "gitee.com/oryjk/sumly/sumly_go/internal/user/ports"
)

func TestWechatLoginCreatesMissingUserAndIssuesJWT(t *testing.T) {
	gateway := &fakeWechatGateway{identity: ports.WechatIdentity{OpenID: "openid-1"}}
	users := newFakeUsers()
	tokens := &fakeTokenService{token: "jwt-1"}
	useCase := NewWechatLogin(gateway, users, tokens)

	result, err := useCase.Execute(context.Background(), "wx-code")
	if err != nil {
		t.Fatalf("execute login: %v", err)
	}
	if result.Token != "jwt-1" {
		t.Fatalf("expected jwt-1, got %s", result.Token)
	}
	if users.created.OpenID != "openid-1" {
		t.Fatalf("expected created openid openid-1, got %s", users.created.OpenID)
	}
}

func TestWechatLoginReturnsExistingUserWithoutRecreating(t *testing.T) {
	gateway := &fakeWechatGateway{identity: ports.WechatIdentity{OpenID: "openid-1"}}
	users := newFakeUsers()
	users.byOpenID["openid-1"] = userdomain.User{ID: 9, OpenID: "openid-1", Status: userdomain.StatusActive}
	tokens := &fakeTokenService{token: "jwt-1"}
	useCase := NewWechatLogin(gateway, users, tokens)

	result, err := useCase.Execute(context.Background(), "wx-code")
	if err != nil {
		t.Fatalf("execute login: %v", err)
	}
	if result.User.ID != 9 {
		t.Fatalf("expected existing user 9, got %d", result.User.ID)
	}
	if users.created.OpenID != "" {
		t.Fatalf("expected no user creation, got %+v", users.created)
	}
}

func TestWechatLoginRejectsFrozenUser(t *testing.T) {
	gateway := &fakeWechatGateway{identity: ports.WechatIdentity{OpenID: "openid-1"}}
	users := newFakeUsers()
	users.byOpenID["openid-1"] = userdomain.User{ID: 9, OpenID: "openid-1", Status: userdomain.StatusFrozen}
	useCase := NewWechatLogin(gateway, users, &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), "wx-code"); err == nil {
		t.Fatal("expected frozen user login to fail")
	}
}

func TestWechatLoginRejectsEmptyCode(t *testing.T) {
	useCase := NewWechatLogin(&fakeWechatGateway{}, newFakeUsers(), &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), "  "); err == nil {
		t.Fatal("expected empty code to fail")
	}
}

func TestWechatLoginWrapsGatewayFailure(t *testing.T) {
	gateway := &fakeWechatGateway{err: context.DeadlineExceeded}
	useCase := NewWechatLogin(gateway, newFakeUsers(), &fakeTokenService{token: "jwt-1"})

	if _, err := useCase.Execute(context.Background(), "wx-code"); err == nil {
		t.Fatal("expected gateway failure to fail")
	}
}

type fakeWechatGateway struct {
	identity ports.WechatIdentity
	err      error
}

func (f *fakeWechatGateway) ExchangeCode(context.Context, string) (ports.WechatIdentity, error) {
	return f.identity, f.err
}

type fakeUsers struct {
	byOpenID map[string]userdomain.User
	created  userdomain.User
}

func newFakeUsers() *fakeUsers {
	return &fakeUsers{byOpenID: make(map[string]userdomain.User)}
}

func (f *fakeUsers) FindByOpenID(_ context.Context, openID string) (userdomain.User, bool, error) {
	user, ok := f.byOpenID[openID]
	return user, ok, nil
}

func (f *fakeUsers) FindByID(_ context.Context, userID int64) (userdomain.User, bool, error) {
	for _, user := range f.byOpenID {
		if user.ID == userID {
			return user, true, nil
		}
	}
	return userdomain.User{}, false, nil
}

func (f *fakeUsers) Create(_ context.Context, user userdomain.User) (userdomain.User, error) {
	user.ID = 11
	f.created = user
	f.byOpenID[user.OpenID] = user
	return user, nil
}

func (f *fakeUsers) UpdateAppProfile(_ context.Context, user userdomain.User) (userdomain.User, error) {
	return user, nil
}

var _ userports.Repository = (*fakeUsers)(nil)

type fakeTokenService struct {
	token string
}

func (f *fakeTokenService) IssueUser(context.Context, int64) (string, error) {
	return f.token, nil
}

func (f *fakeTokenService) IssueAdmin(_ context.Context, _ int64, _ bool) (string, error) {
	return f.token, nil
}

func (f *fakeTokenService) Parse(context.Context, string) (sharedauth.Actor, error) {
	return sharedauth.Actor{}, nil
}
