package wechat

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/ports"
)

const maxResponseBytes = 1 << 20

type Client struct {
	httpClient *http.Client
	endpoint   string
	appID      string
	appSecret  string
}

type loginResponse struct {
	ErrCode    *int64  `json:"errcode"`
	ErrMsg     string  `json:"errmsg"`
	OpenID     string  `json:"openid"`
	SessionKey string  `json:"session_key"`
	UnionID    *string `json:"unionid"`
}

func NewClient(httpClient *http.Client, endpoint, appID, appSecret string) *Client {
	return &Client{
		httpClient: httpClient,
		endpoint:   endpoint,
		appID:      appID,
		appSecret:  appSecret,
	}
}

func (c *Client) ExchangeCode(ctx context.Context, code string) (ports.WechatIdentity, error) {
	code = strings.TrimSpace(code)
	if code == "" {
		return ports.WechatIdentity{}, errors.New("WeChat code is empty")
	}
	requestURL, err := url.Parse(c.endpoint)
	if err != nil {
		return ports.WechatIdentity{}, fmt.Errorf("parse WeChat endpoint: %w", err)
	}
	query := requestURL.Query()
	query.Set("appid", c.appID)
	query.Set("secret", c.appSecret)
	query.Set("js_code", code)
	query.Set("grant_type", "authorization_code")
	requestURL.RawQuery = query.Encode()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL.String(), nil)
	if err != nil {
		return ports.WechatIdentity{}, fmt.Errorf("create WeChat request: %w", err)
	}
	response, err := c.httpClient.Do(request)
	if err != nil {
		return ports.WechatIdentity{}, fmt.Errorf("call WeChat jscode2session: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return ports.WechatIdentity{}, fmt.Errorf("WeChat jscode2session returned HTTP %d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, maxResponseBytes))
	if err != nil {
		return ports.WechatIdentity{}, fmt.Errorf("read WeChat response: %w", err)
	}
	var payload loginResponse
	if err := json.Unmarshal(body, &payload); err != nil {
		return ports.WechatIdentity{}, fmt.Errorf("decode WeChat response: %w", err)
	}
	if payload.ErrCode != nil && *payload.ErrCode != 0 {
		return ports.WechatIdentity{}, fmt.Errorf("WeChat login error %d: %s", *payload.ErrCode, payload.ErrMsg)
	}
	if strings.TrimSpace(payload.OpenID) == "" {
		return ports.WechatIdentity{}, errors.New("WeChat response is missing openid")
	}
	return ports.WechatIdentity{
		OpenID:     payload.OpenID,
		SessionKey: payload.SessionKey,
		UnionID:    payload.UnionID,
	}, nil
}
