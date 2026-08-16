package ports

import "context"

type WechatIdentity struct {
	OpenID     string
	SessionKey string
	UnionID    *string
}

type WechatGateway interface {
	ExchangeCode(context.Context, string) (WechatIdentity, error)
}
