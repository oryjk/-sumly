package bootstrap

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"net"
	"os"
	"strings"

	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/credentials"
	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/providers"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NativeConfig struct {
	Enabled        bool
	Apple          providers.AppleConfig
	SMS            providers.SMS
	SMTP           providers.SMTP
	TrustedProxies []string
}

func loadNativeConfig() (NativeConfig, error) {
	c := NativeConfig{Enabled: os.Getenv("NATIVE_AUTH_ENABLED") == "true"}
	if raw := strings.TrimSpace(os.Getenv("TRUSTED_PROXY_CIDRS")); raw != "" {
		for _, cidr := range strings.Split(raw, ",") {
			cidr = strings.TrimSpace(cidr)
			if _, _, e := net.ParseCIDR(cidr); e != nil {
				return c, fmt.Errorf("invalid TRUSTED_PROXY_CIDRS")
			}
			c.TrustedProxies = append(c.TrustedProxies, cidr)
		}
	}
	if !c.Enabled {
		return c, nil
	}
	c.Apple = providers.AppleConfig{ClientID: os.Getenv("APPLE_CLIENT_ID"), TeamID: os.Getenv("APPLE_TEAM_ID"), KeyID: os.Getenv("APPLE_KEY_ID")}
	if path := os.Getenv("APPLE_PRIVATE_KEY_FILE"); path != "" {
		b, e := os.ReadFile(path)
		if e != nil {
			return c, fmt.Errorf("cannot read APPLE_PRIVATE_KEY_FILE")
		}
		p, _ := pem.Decode(b)
		if p == nil {
			return c, fmt.Errorf("invalid Apple private key")
		}
		k, e := x509.ParsePKCS8PrivateKey(p.Bytes)
		if e != nil {
			return c, fmt.Errorf("invalid Apple PKCS8 private key")
		}
		key, ok := k.(*ecdsa.PrivateKey)
		if !ok || key.Curve.Params().Name != "P-256" {
			return c, fmt.Errorf("Apple key must be ES256")
		}
		c.Apple.PrivateKey = key
	}
	c.SMS = providers.SMS{AccessKeyID: os.Getenv("ALIYUN_ACCESS_KEY_ID"), AccessKeySecret: os.Getenv("ALIYUN_ACCESS_KEY_SECRET"), SignName: os.Getenv("ALIYUN_SMS_SIGN_NAME"), TemplateCode: os.Getenv("ALIYUN_SMS_TEMPLATE_CODE")}
	c.SMTP = providers.SMTP{Host: os.Getenv("SMTP_HOST"), Port: os.Getenv("SMTP_PORT"), Username: os.Getenv("SMTP_USERNAME"), Password: os.Getenv("SMTP_PASSWORD"), From: os.Getenv("SMTP_FROM"), Mode: os.Getenv("SMTP_TLS_MODE")}
	return c, nil
}
func buildNative(config Config, pool *pgxpool.Pool, tokens *jwt.Service) (*authhttp.NativeHandler, authhttp.Middleware, error) {
	middleware := authhttp.NewMiddleware(tokens)
	if !config.Native.Enabled {
		return authhttp.NewNativeHandler(application.Accounts{}, application.Sessions{}), middleware, nil
	}
	crypto, e := credentials.New(config.JWTSecret)
	if e != nil {
		return nil, middleware, e
	}
	store := postgres.NewNativeStore(pool)
	apple := providers.NewApple(config.Native.Apple, nil, crypto)
	codes := application.Codes{Store: store, Crypto: crypto, Phone: config.Native.SMS, Email: config.Native.SMTP}
	sessions := application.Sessions{Store: store, Crypto: crypto, Tokens: tokens, Apple: apple}
	dummy, e := crypto.HashPassword(crypto.Random())
	if e != nil {
		return nil, middleware, e
	}
	accounts := application.Accounts{Store: store, Crypto: crypto, Codes: codes, Sessions: sessions, Apple: apple, DummyHash: dummy}
	return authhttp.NewNativeHandler(accounts, sessions), authhttp.NewMiddleware(jwt.LiveTokens{Service: tokens, Store: store}), nil
}
