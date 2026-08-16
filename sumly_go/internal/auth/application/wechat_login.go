package application

import (
	"context"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
	userdomain "gitee.com/oryjk/sumly/sumly_go/internal/user/domain"
	userports "gitee.com/oryjk/sumly/sumly_go/internal/user/ports"
)

type WechatLogin struct {
	wechat ports.WechatGateway
	users  userports.Repository
	tokens ports.TokenService
}

type WechatLoginResult struct {
	Token string
	User  userdomain.User
}

func NewWechatLogin(wechat ports.WechatGateway, users userports.Repository, tokens ports.TokenService) WechatLogin {
	return WechatLogin{wechat: wechat, users: users, tokens: tokens}
}

func (u WechatLogin) Execute(ctx context.Context, code string) (WechatLoginResult, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return WechatLoginResult{}, sharederror.New(sharederror.KindValidation, "微信登录 code 不能为空")
	}
	identity, err := u.wechat.ExchangeCode(ctx, code)
	if err != nil {
		return WechatLoginResult{}, sharederror.Wrap(sharederror.KindUnauthorized, "微信登录失败", err)
	}
	user, found, err := u.users.FindByOpenID(ctx, identity.OpenID)
	if err != nil {
		return WechatLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "查询用户失败", err)
	}
	if !found {
		user, err = userdomain.NewUser(identity.OpenID)
		if err != nil {
			return WechatLoginResult{}, err
		}
		user, err = u.users.Create(ctx, user)
		if err != nil {
			return WechatLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "创建用户失败", err)
		}
	}
	if !user.IsActive() {
		return WechatLoginResult{}, sharederror.New(sharederror.KindForbidden, "用户已冻结")
	}
	token, err := u.tokens.IssueUser(ctx, user.ID)
	if err != nil {
		return WechatLoginResult{}, sharederror.Wrap(sharederror.KindInternal, "签发登录凭证失败", err)
	}
	return WechatLoginResult{Token: token, User: user}, nil
}
