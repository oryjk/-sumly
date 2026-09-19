package postgres_test

import (
	"context"
	"errors"
	marketpostgres "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
	"testing"
	"time"
)

func TestHistorySurvivesNewRepositoryAndPrunesOnlyExpiredSamples(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	repo := marketpostgres.NewRepository(pool)
	now := time.Date(2026, 9, 18, 16, 0, 2, 0, time.UTC)
	for _, age := range []time.Duration{21 * time.Minute, 20 * time.Minute, 5 * time.Second, 0} {
		p := domain.RealtimePoint{Time: now.Add(-age), SourceTime: now.Add(-age), Price: 938}
		if err := repo.SaveRealtime(ctx, p); err != nil {
			t.Fatal(err)
		}
	}
	// 同一个五秒切片以较新的采样替换，乱序旧值不能覆盖它。
	newer := domain.RealtimePoint{Time: now.Add(time.Second), SourceTime: now, Price: 939}
	if err := repo.SaveRealtime(ctx, newer); err != nil {
		t.Fatal(err)
	}
	if err := repo.SaveRealtime(ctx, domain.RealtimePoint{Time: now, SourceTime: now, Price: 937}); err != nil {
		t.Fatal(err)
	}
	if err := repo.PruneRealtime(ctx); err != nil {
		t.Fatal(err)
	}
	restored, err := marketpostgres.NewRepository(pool).LoadRealtime(ctx)
	if err != nil || len(restored) != 3 || restored[2].Price != 939 {
		t.Fatalf("restored=%+v err=%v", restored, err)
	}
}

func TestDailyUpsertsTradingDateAndNeverPrunesHistory(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repo := marketpostgres.NewRepository(pool)
	ctx := context.Background()
	day := time.Date(2020, 1, 2, 0, 0, 0, 0, time.FixedZone("CST", 8*3600))
	bars := []domain.DailyBar{{Date: day, Open: 1500, High: 1520, Low: 1490, Close: 1510}}
	if err := repo.SaveDaily(ctx, bars); err != nil {
		t.Fatal(err)
	}
	bars[0].Close = 1515
	bars = append(bars, domain.DailyBar{Date: day.AddDate(0, 0, 1), Open: 1515, High: 1530, Low: 1500, Close: 1520})
	if err := repo.SaveDaily(ctx, bars); err != nil {
		t.Fatal(err)
	}
	if err := repo.PruneRealtime(ctx); err != nil {
		t.Fatal(err)
	}
	stored, err := marketpostgres.NewRepository(pool).LoadDaily(ctx)
	if err != nil || len(stored) != 2 || stored[0].Close != 1515 || stored[0].Date.Format("2006-01-02") != "2020-01-02" {
		t.Fatalf("daily=%+v err=%v", stored, err)
	}
}

type historySource struct {
	bars []domain.DailyBar
	err  error
}

func (s historySource) FetchGoldQuote(context.Context) (domain.GoldQuote, error) {
	return domain.GoldQuote{}, s.err
}
func (s historySource) FetchGoldDailyKLines(context.Context) ([]domain.DailyBar, error) {
	return s.bars, s.err
}

func TestServiceRestoresDatabaseHistoryWhenUpstreamIsOffline(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	repo := marketpostgres.NewRepository(pool)
	ctx := context.Background()
	now := time.Now().Add(-48 * time.Hour)
	for _, age := range []time.Duration{21 * time.Minute, 5 * time.Second} {
		if err := repo.SaveRealtime(ctx, domain.RealtimePoint{Time: now.Add(-age), SourceTime: now.Add(-age), Price: 938}); err != nil {
			t.Fatal(err)
		}
	}
	old := domain.DailyBar{Date: time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC), Open: 1500, High: 1520, Low: 1490, Close: 1510}
	if err := repo.SaveDaily(ctx, []domain.DailyBar{old}); err != nil {
		t.Fatal(err)
	}
	latest := old
	latest.Date = old.Date.AddDate(0, 0, 1)
	latest.Close = 1515
	writer := application.NewGoldMarketService(historySource{bars: []domain.DailyBar{latest}}, repo)
	merged, err := writer.GetGoldDailyKLines(ctx)
	if err != nil || len(merged) != 2 {
		t.Fatalf("persist and merge: %v %v", merged, err)
	}
	restarted := application.NewGoldMarketService(historySource{err: errors.New("upstream offline")}, marketpostgres.NewRepository(pool))
	if err := restarted.RestoreHistory(ctx); err != nil {
		t.Fatal(err)
	}
	if points := restarted.RealtimePoints(); len(points) != 1 || points[0].Price != 938 {
		t.Fatalf("restored samples=%+v", points)
	}
	bars, err := restarted.GetGoldDailyKLines(ctx)
	if err != nil || len(bars) != 2 || bars[1].Close != 1515 {
		t.Fatalf("stored daily fallback: %+v %v", bars, err)
	}
}

func TestNativeMarketsAreIsolatedAndSurviveClosure(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	end := time.Now().Add(-48 * time.Hour).Truncate(time.Second)
	for i, symbol := range []string{"AU9999", "XAUUSD", "GCZ26.CMX"} {
		repo := marketpostgres.NewNativeRepository(pool, symbol)
		anchor := end.Add(time.Duration(i) * time.Hour)
		for _, age := range []time.Duration{21 * time.Minute, 20 * time.Minute, 5 * time.Second, 0} {
			if err := repo.SaveRealtime(ctx, domain.RealtimePoint{Time: anchor.Add(-age), SourceTime: anchor.Add(-age), Price: float64(946 + i)}); err != nil {
				t.Fatal(err)
			}
		}
		if err := repo.PruneRealtime(ctx); err != nil {
			t.Fatal(err)
		}
		day := domain.DailyBar{Date: anchor, Open: float64(940 + i), High: float64(950 + i), Low: float64(930 + i), Close: float64(946 + i)}
		if err := repo.SaveDaily(ctx, []domain.DailyBar{day}); err != nil {
			t.Fatal(err)
		}
	}
	for i, symbol := range []string{"AU9999", "XAUUSD", "GCZ26.CMX"} {
		repo := marketpostgres.NewNativeRepository(pool, symbol)
		p, err := repo.LoadRealtime(ctx)
		if err != nil || len(p) != 3 || p[2].Price != float64(946+i) {
			t.Fatalf("%s: %+v %v", symbol, p, err)
		}
		bars, err := repo.LoadDaily(ctx)
		if err != nil || len(bars) != 1 || bars[0].Close != float64(946+i) {
			t.Fatalf("%s daily: %+v %v", symbol, bars, err)
		}
	}
	legacy, err := marketpostgres.NewRepository(pool).LoadRealtime(ctx)
	if err != nil || len(legacy) != 0 {
		t.Fatal("native samples leaked into legacy CNY chart")
	}
}
