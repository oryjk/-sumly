package application

import (
	"context"
	"strings"
	"unicode/utf8"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	userports "gitee.com/oryjk/sumly/sumly_go/internal/user/ports"
)

const (
	devOpenIDPrefix        = "dev-"
	maxDevIdentifierLength = 120
)

// DevLogin 是仅开发测试使用的登录：identifier 加 dev- 前缀作为 openid，
// 复用与微信登录一致的"查不到自动注册"路径。仅 DEV_LOGIN_ENABLED=true 时挂载路由。
type DevLogin struct {
	users  userports.Repository
	tokens ports.TokenService
}

type DevLoginResult struct {
	Token string
	User  userdomain.User
}

func NewDevLogin(users userports.Repository, tokens ports.TokenService) DevLogin {
	return DevLogin{users: users, tokens: tokens}
}

func (u DevLogin) Execute(ctx context.Context, identifier string) (DevLoginResult, error) {
	identifier = strings.TrimSpace(identifier)
	if identifier == "" {
		return DevLoginResult{}, sharederror.New(sharederror.KindValidation, "开发登录标识不能为空")
	}
	if utf8.RuneCountInString(identifier) > maxDevIdentifierLength {
		return DevLoginResult{}, sharederror.New(sharederror.KindValidation, "开发登录标识不能超过 120 个字符")
	}
	openID := devOpenIDPrefix + identifier
	user, found, err := u.users.FindByOpenID(ctx, openID)
	if err != nil {
		return DevLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "查询用户失败", err)
	}
	if !found {
		user, err = userdomain.NewUser(openID)
		if err != nil {
			return DevLoginResult{}, err
		}
		user, err = u.users.Create(ctx, user)
		if err != nil {
			return DevLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "创建用户失败", err)
		}
	}
	if !user.IsActive() {
		return DevLoginResult{}, sharederror.New(sharederror.KindForbidden, "用户已冻结")
	}
	token, err := u.tokens.IssueUser(ctx, user.ID)
	if err != nil {
		return DevLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "签发登录凭证失败", err)
	}
	return DevLoginResult{Token: token, User: user}, nil
}
