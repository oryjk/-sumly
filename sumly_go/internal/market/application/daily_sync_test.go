package application

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"testing"
	"time"
)

type dailyMemory struct {
	bars  []domain.DailyBar
	saves int
}

func (s *dailyMemory) SaveRealtime(context.Context, domain.RealtimePoint) error     { return nil }
func (s *dailyMemory) PruneRealtime(context.Context) error                          { return nil }
func (s *dailyMemory) LoadRealtime(context.Context) ([]domain.RealtimePoint, error) { return nil, nil }
func (s *dailyMemory) SaveDaily(_ context.Context, b []domain.DailyBar) error {
	s.saves++
	s.bars = append(s.bars, b...)
	return nil
}
func (s *dailyMemory) LoadDaily(context.Context) ([]domain.DailyBar, error) { return s.bars, nil }
func TestPersistedDailyReadNeverFetchesUpstream(t *testing.T) {
	source := &fakeSource{}
	store := &dailyMemory{bars: []domain.DailyBar{{Close: 1000}}}
	s := NewGoldMarketService(source, store)
	for i := 0; i < 3; i++ {
		bars, err := s.GetGoldDailyKLines(context.Background())
		if err != nil || len(bars) != 1 {
			t.Fatal(bars, err)
		}
	}
	if source.dailyCalls != 0 {
		t.Fatal("query fetched upstream", source.dailyCalls)
	}
}
func TestSyncDailyExcludesLiveAndInvalidBarsAndWritesOnlyChanges(t *testing.T) {
	now := time.Date(2026, 9, 29, 9, 0, 0, 0, time.UTC)
	old := domain.DailyBar{Date: now.AddDate(0, 0, -2), Open: 1000, High: 1100, Low: 900, Close: 1050}
	latest := old
	latest.Date = now.AddDate(0, 0, -1)
	today := old
	today.Date = now
	invalid := old
	invalid.Date = now.AddDate(0, 0, -3)
	invalid.Close = 0
	source := &fakeSource{daily: []domain.DailyBar{old, latest, today, invalid}}
	store := &dailyMemory{bars: []domain.DailyBar{old}}
	s := NewGoldMarketService(source, store)
	s.now = func() time.Time { return now }
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.bars) != 2 || store.bars[1].Close != 1050 {
		t.Fatal("bad incremental write", store.bars)
	}
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if store.saves != 1 {
		t.Fatal("unchanged data rewritten", store.saves)
	}
}

func TestSyncDailyPreservesSourceCloseDespiteInconsistentHistoricalBounds(t *testing.T) {
	bar := domain.DailyBar{Date: time.Date(2012, 12, 25, 0, 0, 0, 0, time.UTC), Open: 1660.69, High: 1657.01, Low: 1656.51, Close: 1658.79}
	store := &dailyMemory{}
	s := NewGoldMarketService(&fakeSource{daily: []domain.DailyBar{bar}}, store)
	if err := s.SyncDaily(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(store.bars) != 1 || store.bars[0].Close != bar.Close {
		t.Fatal("discarded usable close because source OHLC disagreed")
	}
}
