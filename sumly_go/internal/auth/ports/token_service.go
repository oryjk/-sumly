package ports

import (
	"context"

	sharedauth "gitee.com/oryjk/sumly/sumly_go/internal/shared/auth"
)

type TokenService interface {
	IssueUser(context.Context, int64) (string, error)
	IssueAdmin(context.Context, int64, bool) (string, error)
	Parse(context.Context, string) (sharedauth.Actor, error)
}
