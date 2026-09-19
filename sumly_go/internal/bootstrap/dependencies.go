package bootstrap

import (
	"context"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/feed"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/sge"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/yahoo"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"log/slog"
	"net/http"
	"sync"
	"time"

	authhttp "gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/http"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/jwt"
	"gitee.com/oryjk/sumly/sumly_go/internal/auth/adapters/wechat"
	authapplication "gitee.com/oryjk/sumly/sumly_go/internal/auth/application"
	markethttp "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/http"
	marketpostgres "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/sina"
	marketapplication "gitee.com/oryjk/sumly/sumly_go/internal/market/application"
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
	GoldInstruments *markethttp.InstrumentsHandler
	AuthMiddleware  *authhttp.Middleware
	UserAuth        *authhttp.Handler
	AppUsers        *userhttp.AppHandler
	ActiveUsers     authhttp.ActiveUserChecker
	GoldMarket      *markethttp.Handler
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

	sinaClient := sina.NewClient(&http.Client{Timeout: 10 * time.Second})
	goldMarketService := marketapplication.NewGoldMarketService(sinaClient, marketpostgres.NewRepository(pool))
	if err := goldMarketService.RestoreHistory(ctx); err != nil {
		closePool()
		return Dependencies{}, nil, fmt.Errorf("restore market history: %w", err)
	}
	goldMarketHandler := markethttp.NewHandler(goldMarketService)

	domesticQuote := sina.NewInstrumentClient(sinaClient, "gds_AU9999", "AU9999", "CNY")
	londonSource := sina.NewInstrumentClient(sinaClient, "hf_XAU", "XAUUSD", "USD")
	domesticSource := feed.Source{Quote: domesticQuote, Daily: &sge.Client{HTTP: &http.Client{Timeout: 20 * time.Second}}}
	comexSource := &yahoo.Client{HTTP: &http.Client{Timeout: 10 * time.Second}, Symbol: "GCZ26.CMX", FX: londonSource}
	markets := []marketapplication.InstrumentMarket{
		{Instrument: domain.Instrument{ID: "comex-gold", Name: "纽约黄金期货", Symbol: "GCZ26.CMX", Kind: "future", Currency: "USD", Unit: "USD/troy_oz", QuoteSource: "yahoo", DailySource: "yahoo", Exchange: "COMEX", Contract: "GCZ26", DelaySeconds: 1800}, Service: marketapplication.NewNativeGoldMarketService(comexSource, marketpostgres.NewNativeRepository(pool, "GCZ26.CMX"))},
		{Instrument: domain.Instrument{ID: "au9999", Name: "国内黄金", Symbol: "AU9999", Kind: "spot", Currency: "CNY", Unit: "CNY/g", QuoteSource: "sina", DailySource: "sge", Exchange: "SGE"}, Service: marketapplication.NewNativeGoldMarketService(domesticSource, marketpostgres.NewNativeRepository(pool, "AU9999"))},
		{Instrument: domain.Instrument{ID: "xauusd", Name: "伦敦现货黄金", Symbol: "XAUUSD", Kind: "spot", Currency: "USD", Unit: "USD/troy_oz", QuoteSource: "sina", DailySource: "sina"}, Service: marketapplication.NewNativeGoldMarketService(londonSource, marketpostgres.NewNativeRepository(pool, "XAUUSD"))},
	}
	for _, m := range markets {
		if err := m.Service.RestoreHistory(ctx); err != nil {
			closePool()
			return Dependencies{}, nil, fmt.Errorf("restore %s history: %w", m.Instrument.ID, err)
		}
	}
	instrumentsHandler := markethttp.NewInstrumentsHandler(marketapplication.NewInstruments(markets))
	samplerCtx, stopSampler := context.WithCancel(ctx)
	var workers sync.WaitGroup
	services := []*marketapplication.GoldMarketService{goldMarketService}
	for _, m := range markets {
		services = append(services, m.Service)
	}
	for _, service := range services {
		workers.Add(2)
		go func() { defer workers.Done(); service.CollectRealtime(samplerCtx) }()
		go func() { defer workers.Done(); service.CollectDaily(samplerCtx) }()
	}
	closeAll := func() { stopSampler(); workers.Wait(); closePool() }

	return Dependencies{
		GoldInstruments: instrumentsHandler,
		AuthMiddleware:  &authMiddleware,
		UserAuth:        userAuthHandler,
		AppUsers:        appUserHandler,
		ActiveUsers:     appUserService,
		GoldMarket:      goldMarketHandler,
	}, closeAll, nil
}
