package postgres_test

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/historical"
	marketpostgres "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/testsupport"
	"testing"
	"time"
)

func TestMarketSyncPersistsSeedAndDeliversCorrectionsAndDeletions(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	repo := marketpostgres.NewRepository(pool)
	annual, _ := historical.AnnualGold()
	if err := repo.SeedAnnual(ctx, annual); err != nil {
		t.Fatal(err)
	}
	first, err := repo.SyncHistory(ctx, "xauusd", "")
	if err != nil || !first.Reset || len(first.Points) != 116 {
		t.Fatalf("first %v %v", first, err)
	}
	if err := repo.SeedAnnual(ctx, annual); err != nil {
		t.Fatal(err)
	}
	unchanged, err := repo.SyncHistory(ctx, "xauusd", first.Cursor)
	if err != nil || unchanged.Reset || len(unchanged.Points) != 0 {
		t.Fatalf("seed was not idempotent: %+v %v", unchanged, err)
	}
	day := time.Date(2016, 1, 4, 0, 0, 0, 0, time.UTC)
	bar := domain.DailyBar{Date: day, Open: 1000, High: 1100, Low: 900, Close: 1050}
	if err := repo.SaveDaily(ctx, []domain.DailyBar{bar}); err != nil {
		t.Fatal(err)
	}
	delta, err := repo.SyncHistory(ctx, "xauusd", first.Cursor)
	if err != nil || len(delta.Points) != 1 || delta.Points[0].Close != 1050 {
		t.Fatalf("delta %+v %v", delta, err)
	}
	if err := repo.SaveDaily(ctx, []domain.DailyBar{bar}); err != nil {
		t.Fatal(err)
	}
	same, _ := repo.SyncHistory(ctx, "xauusd", delta.Cursor)
	if len(same.Points) != 0 {
		t.Fatal("unchanged bar produced new revision")
	}
	bar.Close = 1060
	if err := repo.SaveDaily(ctx, []domain.DailyBar{bar}); err != nil {
		t.Fatal(err)
	}
	corrected, _ := repo.SyncHistory(ctx, "xauusd", delta.Cursor)
	if len(corrected.Points) != 1 || corrected.Points[0].Close != 1060 {
		t.Fatal("missed old correction")
	}
	if _, err := pool.Exec(ctx, "DELETE FROM gold_daily_bars WHERE symbol='XAUUSD'"); err != nil {
		t.Fatal(err)
	}
	deleted, _ := repo.SyncHistory(ctx, "xauusd", corrected.Cursor)
	if len(deleted.Points) != 1 || !deleted.Points[0].Deleted {
		t.Fatal("missing tombstone")
	}
	reset, _ := repo.SyncHistory(ctx, "xauusd", "old-database:9999")
	if !reset.Reset || len(reset.Points) != 116 {
		t.Fatal("bad cursor must reset")
	}
	other, _ := repo.SyncHistory(ctx, "au9999", "")
	if len(other.Points) != 0 {
		t.Fatal("cross-series data leak")
	}
}

func TestDailyLeaseSurvivesRestartAndRetriesFailure(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	repo := marketpostgres.NewRepository(pool)
	now := time.Date(2026, 9, 29, 9, 0, 0, 0, time.UTC)
	ok, err := repo.TryDailySync(ctx, now)
	if err != nil || !ok {
		t.Fatal("initial lease", err)
	}
	other := marketpostgres.NewRepository(pool)
	if ok, _ := other.TryDailySync(ctx, now); ok {
		t.Fatal("duplicate lease")
	}
	if err := repo.FinishDailySync(ctx, now, true); err != nil {
		t.Fatal(err)
	}
	if ok, _ := other.TryDailySync(ctx, now.Add(time.Hour)); ok {
		t.Fatal("restarted collector repeated successful daily sync")
	}
	tomorrow := now.Add(24 * time.Hour)
	if ok, _ := other.TryDailySync(ctx, tomorrow); !ok {
		t.Fatal("next day not due")
	}
	if err := other.FinishDailySync(ctx, tomorrow, false); err != nil {
		t.Fatal(err)
	}
	if ok, _ := repo.TryDailySync(ctx, tomorrow.Add(time.Minute)); ok {
		t.Fatal("immediate retry storm")
	}
	if ok, _ := repo.TryDailySync(ctx, tomorrow.Add(16*time.Minute)); !ok {
		t.Fatal("failed job not retried")
	}
}

func TestAnnualCorrectionSurvivesSeedAndSeriesCursorCannotSkipData(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	repo := marketpostgres.NewRepository(pool)
	annual, _ := historical.AnnualGold()
	if err := repo.SeedAnnual(ctx, annual); err != nil {
		t.Fatal(err)
	}
	initial, err := repo.SyncHistory(ctx, "xauusd", "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, "UPDATE market_history_points SET close=20,open=20,high=20,low=20 WHERE granularity='annual' AND trading_date='1900-07-01'"); err != nil {
		t.Fatal(err)
	}
	if err := repo.SeedAnnual(ctx, annual); err != nil {
		t.Fatal(err)
	}
	delta, err := repo.SyncHistory(ctx, "xauusd", initial.Cursor)
	if err != nil || len(delta.Points) != 1 || delta.Points[0].Close != 20 {
		t.Fatal("lost annual correction", err)
	}
	loaded, err := repo.LoadAnnual(ctx)
	if err != nil || loaded[0].Price != 20 {
		t.Fatal("annual history still read embedded CSV")
	}
	other, err := repo.SyncHistory(ctx, "au9999", delta.Cursor)
	if err != nil || !other.Reset {
		t.Fatal("cross-series cursor accepted")
	}
}

func TestSyncCursorDoesNotSkipConcurrentUncommittedCorrections(t *testing.T) {
	pool := testsupport.OpenTestPostgres(t)
	ctx := context.Background()
	repo := marketpostgres.NewRepository(pool)
	annual, _ := historical.AnnualGold()
	if err := repo.SeedAnnual(ctx, annual); err != nil {
		t.Fatal(err)
	}
	first, _ := repo.SyncHistory(ctx, "xauusd", "")
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, "UPDATE market_history_points SET close=21 WHERE trading_date='1900-07-01'"); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := pool.Exec(ctx, "UPDATE market_history_points SET close=22 WHERE trading_date='1901-07-01'")
		done <- err
	}()
	select {
	case err := <-done:
		t.Fatalf("later writer bypassed transactional clock: %v", err)
	case <-time.After(100 * time.Millisecond):
	}
	before, err := repo.SyncHistory(ctx, "xauusd", first.Cursor)
	if err != nil || len(before.Points) != 0 {
		t.Fatal("read uncommitted data", err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	after, err := repo.SyncHistory(ctx, "xauusd", before.Cursor)
	if err != nil || len(after.Points) != 2 {
		t.Fatalf("lost concurrent correction: %+v %v", after, err)
	}
}
