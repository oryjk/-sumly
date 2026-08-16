package bootstrap

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/wechat"
	authapplication "gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	userhttp "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/http"
	userpostgres "gitee.com/oryjk/sumly/sumly_go/internal/user/adapters/postgres"
	userapplication "gitee.com/oryjk/sumly/sumly_go/internal/user/application"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	jwtTTL         = 24 * time.Hour
	wechatEndpoint = "https://api.weixin.qq.com/sns/jscode2session"
)

type Dependencies struct {
	AuthMiddleware *authhttp.Middleware
	UserAuth       *authhttp.Handler
	AppUsers       *userhttp.AppHandler
	ActiveUsers    authhttp.ActiveUserChecker
}

func BuildDependencies(ctx context.Context, config Config) (Dependencies, func(), error) {
	pool, err := pgxpool.New(ctx, config.DatabaseURL)
	if err != nil {
		return Dependencies{}, nil, fmt.Errorf("open PostgreSQL pool: %w", err)
	}
	closePool := func() { pool.Close() }
	if err := pool.Ping(ctx); err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("ping PostgreSQL: %w", err)
	}

	tokens, err := jwt.NewService(config.JWTSecret, jwtTTL)
	if err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("create JWT service: %w", err)
	}
	authMiddleware := authhttp.NewMiddleware(tokens)

	userRepository := userpostgres.NewRepository(pool)
	appUserService := userapplication.NewAppService(userRepository)
	appUserHandler := userhttp.NewAppHandler(appUserService)
	wechatClient := wechat.NewClient(&http.Client{Timeout: 10 * time.Second}, wechatEndpoint, config.WechatAppID, config.WechatAppSecret)
	wechatLogin := authapplication.NewWechatLogin(wechatClient, userRepository, tokens)
	var devLogin authhttp.DevLoginUseCase
	if config.DevLoginEnabled {
		// 纵深防御：dev 登录允许任意 identifier 直接换取 JWT，启用必须在日志中可见。
		slog.Warn("dev login endpoint is enabled (DEV_LOGIN_ENABLED=true); never enable in production")
		login := authapplication.NewDevLogin(userRepository, tokens)
		devLogin = login
	}
	userAuthHandler := authhttp.NewHandler(wechatLogin, devLogin)

	return Dependencies{
		AuthMiddleware: &authMiddleware,
		UserAuth:       userAuthHandler,
		AppUsers:       appUserHandler,
		ActiveUsers:    appUserService,
	}, closePool, nil
}
