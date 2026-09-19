package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type fakeSource struct {
	quotes []domain.GoldQuote
	daily  []domain.DailyBar
	err    error

	quoteCalls int
	dailyCalls int
}

func (f *fakeSource) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	f.quoteCalls++
	if f.err != nil {
		return domain.GoldQuote{}, f.err
	}
	if f.quoteCalls <= len(f.quotes) {
		return f.quotes[f.quoteCalls-1], nil
	}
	return f.quotes[len(f.quotes)-1], nil
}

func (f *fakeSource) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	f.dailyCalls++
	if f.err != nil {
		return nil, f.err
	}
	return f.daily, nil
}

func newTestService(source *fakeSource, now *time.Time) *GoldMarketService {
	service := NewGoldMarketService(source)
	service.now = func() time.Time { return *now }
	service.quoteTTL = 2 * time.Second
	service.dailyTTL = time.Minute
	return service
}

func TestGetGoldQuoteCachesWithinTTL(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 9, 17, 13, 0, 0, 0, time.UTC)
	source := &fakeSource{quotes: []domain.GoldQuote{{Symbol: "XAUUSD", Price: 4300, PrevClose: 4200}}}
	service := newTestService(source, &now)

	first, err := service.GetGoldQuote(ctx)
	if err != nil {
		t.Fatalf("first GetGoldQuote() error = %v", err)
	}
	if first.Price != 4300 {
		t.Errorf("first.Price = %v, want 4300", first.Price)
	}

	now = now.Add(1 * time.Second) // TTL 内
	second, err := service.GetGoldQuote(ctx)
	if err != nil {
		t.Fatalf("second GetGoldQuote() error = %v", err)
	}
	if second.Price != 4300 {
		t.Errorf("second.Price = %v, want cached 4300", second.Price)
	}
	if source.quoteCalls != 1 {
		t.Errorf("source.quoteCalls = %d, want 1（TTL 内不回源）", source.quoteCalls)
	}

	now = now.Add(2 * time.Second) // 过期，回源
	source.quotes = []domain.GoldQuote{{Symbol: "XAUUSD", Price: 4350, PrevClose: 4200}}
	third, err := service.GetGoldQuote(ctx)
	if err != nil {
		t.Fatalf("third GetGoldQuote() error = %v", err)
	}
	if third.Price != 4350 || source.quoteCalls != 2 {
		t.Errorf("third.Price = %v, quoteCalls = %d; want 4350, 2（过期后回源）", third.Price, source.quoteCalls)
	}
}

func TestGetGoldQuoteServesStaleOnSourceFailure(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 9, 17, 13, 0, 0, 0, time.UTC)
	source := &fakeSource{quotes: []domain.GoldQuote{{Symbol: "XAUUSD", Price: 4300, PrevClose: 4200}}}
	service := newTestService(source, &now)

	if _, err := service.GetGoldQuote(ctx); err != nil {
		t.Fatalf("warm up error = %v", err)
	}

	now = now.Add(time.Hour) // 缓存早已过期
	source.err = errors.New("upstream down")
	quote, err := service.GetGoldQuote(ctx)
	if err != nil {
		t.Fatalf("GetGoldQuote() on source failure error = %v, want stale value", err)
	}
	if quote.Price != 4300 {
		t.Errorf("quote.Price = %v, want stale 4300", quote.Price)
	}
}

func TestGetGoldQuoteFailsWithoutCache(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 9, 17, 13, 0, 0, 0, time.UTC)
	source := &fakeSource{err: errors.New("upstream down")}
	service := newTestService(source, &now)

	if _, err := service.GetGoldQuote(ctx); err == nil {
		t.Error("GetGoldQuote() without cache on failure: want error")
	}
}

func TestGetGoldDailyKLinesCachesAndServesStale(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 9, 17, 13, 0, 0, 0, time.UTC)
	source := &fakeSource{daily: []domain.DailyBar{{Close: 3875.25}}}
	service := newTestService(source, &now)

	if _, err := service.GetGoldDailyKLines(ctx); err != nil {
		t.Fatalf("first error = %v", err)
	}
	if _, err := service.GetGoldDailyKLines(ctx); err != nil {
		t.Fatalf("second error = %v", err)
	}
	if source.dailyCalls != 1 {
		t.Errorf("dailyCalls = %d, want 1", source.dailyCalls)
	}

	now = now.Add(2 * time.Hour)
	source.err = errors.New("upstream down")
	bars, err := service.GetGoldDailyKLines(ctx)
	if err != nil {
		t.Fatalf("stale error = %v", err)
	}
	if len(bars) != 1 || bars[0].Close != 3875.25 {
		t.Errorf("stale bars = %+v, want cached value", bars)
	}
}
