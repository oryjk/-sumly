package application

import (
	"context"
	"errors"
	"testing"

	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/user/ports"
)

func TestGetMeReturnsActiveUser(t *testing.T) {
	users := newFakeRepository()
	users.byID[int64(42)] = userdomain.User{ID: 42, OpenID: "openid-1", Nickname: "小明", Status: userdomain.StatusActive}
	service := NewAppService(users)

	user, err := service.GetMe(context.Background(), sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 42})
	if err != nil {
		t.Fatalf("get me: %v", err)
	}
	if user.Nickname != "小明" {
		t.Fatalf("expected nickname 小明, got %s", user.Nickname)
	}
}

func TestGetMeRejectsNonUserActors(t *testing.T) {
	service := NewAppService(newFakeRepository())

	if _, err := service.GetMe(context.Background(), sharedauth.Actor{Kind: sharedauth.ActorAdmin, ID: 1}); err == nil {
		t.Fatal("expected admin actor to be rejected")
	}
}

func TestGetMeRejectsMissingUser(t *testing.T) {
	service := NewAppService(newFakeRepository())

	_, err := service.GetMe(context.Background(), sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 42})
	if err == nil || !errors.Is(err, sharederror.ErrUnauthorized) {
		t.Fatalf("expected unauthorized error, got %v", err)
	}
}

func TestUpdateMePersistsNickname(t *testing.T) {
	users := newFakeRepository()
	users.byID[int64(42)] = userdomain.User{ID: 42, OpenID: "openid-1", Nickname: "旧昵称", Status: userdomain.StatusActive}
	service := NewAppService(users)
	nickname := "新昵称"

	user, err := service.UpdateMe(context.Background(), sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 42}, UpdateMeCommand{Nickname: &nickname})
	if err != nil {
		t.Fatalf("update me: %v", err)
	}
	if user.Nickname != "新昵称" {
		t.Fatalf("expected updated nickname, got %s", user.Nickname)
	}
	if users.updated.Nickname != "新昵称" {
		t.Fatalf("expected persisted nickname, got %s", users.updated.Nickname)
	}
}

func TestUpdateMeRequiresAtLeastOneField(t *testing.T) {
	service := NewAppService(newFakeRepository())

	_, err := service.UpdateMe(context.Background(), sharedauth.Actor{Kind: sharedauth.ActorUser, ID: 42}, UpdateMeCommand{})
	if err == nil || !errors.Is(err, sharederror.ErrValidation) {
		t.Fatalf("expected validation error, got %v", err)
	}
}

type fakeRepository struct {
	byID    map[int64]userdomain.User
	updated userdomain.User
}

func newFakeRepository() *fakeRepository {
	return &fakeRepository{byID: make(map[int64]userdomain.User)}
}

func (f *fakeRepository) FindByOpenID(_ context.Context, _ string) (userdomain.User, bool, error) {
	return userdomain.User{}, false, nil
}

func (f *fakeRepository) FindByID(_ context.Context, userID int64) (userdomain.User, bool, error) {
	user, ok := f.byID[userID]
	return user, ok, nil
}

func (f *fakeRepository) Create(_ context.Context, user userdomain.User) (userdomain.User, error) {
	return user, nil
}

func (f *fakeRepository) UpdateAppProfile(_ context.Context, user userdomain.User) (userdomain.User, error) {
	f.updated = user
	f.byID[user.ID] = user
	return user, nil
}

var _ ports.Repository = (*fakeRepository)(nil)
