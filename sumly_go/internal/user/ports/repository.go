package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
)

type Repository interface {
	FindByOpenID(context.Context, string) (domain.User, bool, error)
	FindByID(context.Context, int64) (domain.User, bool, error)
	Create(context.Context, domain.User) (domain.User, error)
	UpdateAppProfile(context.Context, domain.User) (domain.User, error)
}
