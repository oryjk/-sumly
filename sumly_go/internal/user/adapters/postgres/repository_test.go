package postgres_test

import (
	"context"
	"testing"

	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
	userpostgres "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/postgres"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
)

func TestRepositoryCreatesAndFindsUserByOpenID(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repository := userpostgres.NewRepository(pool)
	ctx := context.Background()

	created, err := repository.Create(ctx, userdomain.User{OpenID: "openid-repository-test", Nickname: "小明"})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	if created.ID <= 0 || created.Status != userdomain.StatusActive {
		t.Fatalf("unexpected created user: %+v", created)
	}

	found, ok, err := repository.FindByOpenID(ctx, "openid-repository-test")
	if err != nil || !ok {
		t.Fatalf("find by openid: found=%v err=%v", ok, err)
	}
	if found.ID != created.ID || found.Nickname != "小明" {
		t.Fatalf("unexpected found user: %+v", found)
	}

	_, ok, err = repository.FindByOpenID(ctx, "openid-missing")
	if err != nil || ok {
		t.Fatalf("expected missing user, found=%v err=%v", ok, err)
	}
}

func TestRepositoryUpdatesAppProfile(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repository := userpostgres.NewRepository(pool)
	ctx := context.Background()

	created, err := repository.Create(ctx, userdomain.User{OpenID: "openid-profile-test"})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	created, err = created.UpdateAppProfile(strPtr("新昵称"), strPtr("王小明"))
	if err != nil {
		t.Fatalf("apply profile update: %v", err)
	}
	updated, err := repository.UpdateAppProfile(ctx, created)
	if err != nil {
		t.Fatalf("persist profile update: %v", err)
	}
	if updated.Nickname != "新昵称" || updated.RealName == nil || *updated.RealName != "王小明" {
		t.Fatalf("unexpected updated user: %+v", updated)
	}

	found, ok, err := repository.FindByID(ctx, updated.ID)
	if err != nil || !ok {
		t.Fatalf("find by id: found=%v err=%v", ok, err)
	}
	if found.Nickname != "新昵称" {
		t.Fatalf("expected persisted nickname, got %s", found.Nickname)
	}
}

func strPtr(value string) *string {
	return &value
}
