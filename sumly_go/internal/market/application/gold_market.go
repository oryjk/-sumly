package application

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	sharederror "gitee.com/oryjk/sumly/sumly_go/internal/shared/domain"
)

const (
	defaultQuoteTTL = 2 * time.Second
	defaultDailyTTL = time.Minute
)

// GoldMarketService 编排金价查询：短 TTL 缓存保护上游，
// 上游失败时退回旧缓存（可能已过期），保证高频轮询端不闪断。
type GoldMarketService struct {
	nativeRealtime bool
	store          ports.GoldHistoryStore
	dailyFetchMu   sync.Mutex
	source         ports.GoldSource
	now            func() time.Time
	quoteTTL       time.Duration
	dailyTTL       time.Duration

	realtimeMu sync.Mutex
	realtime   []domain.RealtimePoint
	intradayMu sync.Mutex
	intraday   []domain.IntradayPoint
	intradayAt time.Time
	mu         sync.Mutex
	quote      domain.GoldQuote
	quoteAt    time.Time
	daily      []domain.DailyBar
	dailyAt    time.Time
}

func NewGoldMarketService(source ports.GoldSource, stores ...ports.GoldHistoryStore) *GoldMarketService {
	var store ports.GoldHistoryStore
	if len(stores) > 0 {
		store = stores[0]
	}
	return &GoldMarketService{
		store:    store,
		source:   source,
		now:      time.Now,
		quoteTTL: defaultQuoteTTL,
		dailyTTL: defaultDailyTTL,
	}
}

func (s *GoldMarketService) GetGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	s.mu.Lock()
	if !s.quoteAt.IsZero() && s.now().Sub(s.quoteAt) < s.quoteTTL {
		quote := s.quote
		s.mu.Unlock()
		return quote, nil
	}
	s.mu.Unlock()

	quote, err := s.source.FetchGoldQuote(ctx)
	if err != nil {
		return s.staleQuoteOrFail(err)
	}

	s.mu.Lock()
	s.quote, s.quoteAt = quote, s.now()
	s.mu.Unlock()
	return quote, nil
}

func (s *GoldMarketService) staleQuoteOrFail(err error) (domain.GoldQuote, error) {
	s.mu.Lock()
	if s.quoteAt.IsZero() {
		s.mu.Unlock()
		return domain.GoldQuote{}, sharederror.Wrap(sharederror.KindInternal, "行情源暂时不可用", err)
	}
	stale, age := s.quote, s.now().Sub(s.quoteAt)
	s.mu.Unlock()
	slog.Warn("gold quote source failed, serving stale cache", "error", err, "cache_age", age.String())
	return stale, nil
}

func (s *GoldMarketService) GetGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	s.dailyFetchMu.Lock()
	defer s.dailyFetchMu.Unlock()
	s.mu.Lock()
	if !s.dailyAt.IsZero() && s.now().Sub(s.dailyAt) < s.dailyTTL {
		bars := s.daily
		s.mu.Unlock()
		return bars, nil
	}
	s.mu.Unlock()

	bars, err := s.source.FetchGoldDailyKLines(ctx)
	if err != nil {
		return s.staleDailyOrFail(err)
	}

	if s.store != nil {
		if err := s.store.SaveDaily(ctx, bars); err != nil {
			return nil, sharederror.Wrap(sharederror.KindInternal, "日线保存失败", err)
		}
		// 上游以后缩短返回范围时，数据库中的旧日线仍要保留并可查询。
		stored, err := s.store.LoadDaily(ctx)
		if err != nil {
			return nil, sharederror.Wrap(sharederror.KindInternal, "日线读取失败", err)
		}
		bars = stored
	}
	s.mu.Lock()
	s.daily, s.dailyAt = bars, s.now()
	s.mu.Unlock()
	return bars, nil
}

func (s *GoldMarketService) staleDailyOrFail(err error) ([]domain.DailyBar, error) {
	s.mu.Lock()
	if s.dailyAt.IsZero() {
		s.mu.Unlock()
		return nil, sharederror.Wrap(sharederror.KindInternal, "行情源暂时不可用", err)
	}
	stale, age := s.daily, s.now().Sub(s.dailyAt)
	s.mu.Unlock()
	slog.Warn("gold daily source failed, serving stale cache", "error", err, "cache_age", age.String())
	return stale, nil
}

// NewNativeGoldMarketService 用于显式品种接口；报价、日线、采样保持原始单位。
func NewNativeGoldMarketService(source ports.GoldSource, store ports.GoldHistoryStore) *GoldMarketService {
	s := NewGoldMarketService(source, store)
	s.nativeRealtime = true
	return s
}
func (s *GoldMarketService) realtimePrice(q domain.GoldQuote) float64 {
	if s.nativeRealtime {
		return q.Price
	}
	return q.CNYPerGram()
}
