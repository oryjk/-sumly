package application

import (
	"context"

	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/user/ports"
)

type AppService struct {
	repository ports.Repository
}

type UpdateMeCommand struct {
	Nickname *string
	RealName *string
}

func NewAppService(repository ports.Repository) AppService {
	return AppService{repository: repository}
}

func (s AppService) GetMe(ctx context.Context, actor sharedauth.Actor) (domain.User, error) {
	if !actor.IsUser() {
		return domain.User{}, sharederror.ErrForbidden
	}
	return s.activeUser(ctx, actor.ID)
}

func (s AppService) UpdateMe(ctx context.Context, actor sharedauth.Actor, command UpdateMeCommand) (domain.User, error) {
	if !actor.IsUser() {
		return domain.User{}, sharederror.ErrForbidden
	}
	if command.Nickname == nil && command.RealName == nil {
		return domain.User{}, sharederror.New(sharederror.KindValidation, "至少提供一个需要更新的字段")
	}
	user, err := s.activeUser(ctx, actor.ID)
	if err != nil {
		return domain.User{}, err
	}
	user, err = user.UpdateAppProfile(command.Nickname, command.RealName)
	if err != nil {
		return domain.User{}, err
	}
	updated, err := s.repository.UpdateAppProfile(ctx, user)
	if err != nil {
		return domain.User{}, sharederror.Wrap(sharederror.KindInternal, "更新用户资料失败", err)
	}
	return updated, nil
}

func (s AppService) EnsureActive(ctx context.Context, userID int64) error {
	_, err := s.activeUser(ctx, userID)
	return err
}

func (s AppService) activeUser(ctx context.Context, userID int64) (domain.User, error) {
	user, found, err := s.repository.FindByID(ctx, userID)
	if err != nil {
		return domain.User{}, sharederror.Wrap(sharederror.KindInternal, "查询用户失败", err)
	}
	if !found || !user.IsActive() {
		return domain.User{}, sharederror.ErrUnauthorized
	}
	return user, nil
}
