package application

import (
	"context"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"math"
	"sort"
	"time"
)

// SyncDaily runs independently of readers. The durable schedule coalesces all
// collectors for a symbol and retries failed requests after the lease expires.
func (s *GoldMarketService) SyncDaily(ctx context.Context) (result error) {
	s.dailyFetchMu.Lock()
	defer s.dailyFetchMu.Unlock()
	now := s.now()
	if schedule, ok := s.store.(ports.DailySyncSchedule); ok {
		acquired, err := schedule.TryDailySync(ctx, now)
		if err != nil {
			return err
		}
		if !acquired {
			return nil
		}
		defer func() {
			cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
			defer cancel()
			if err := schedule.FinishDailySync(cleanup, now, result == nil); err != nil && result == nil {
				result = err
			}
		}()
	}
	bars, err := s.source.FetchGoldDailyKLines(ctx)
	if err != nil {
		return err
	}
	current := map[string]domain.DailyBar{}
	if s.store != nil {
		stored, err := s.store.LoadDaily(ctx)
		if err != nil {
			return err
		}
		for _, bar := range stored {
			current[bar.Date.Format("2006-01-02")] = bar
		}
	}
	valid := map[string]domain.DailyBar{}
	for _, bar := range bars {
		key := bar.Date.Format("2006-01-02")
		if bar.Date.IsZero() || key >= now.UTC().Format("2006-01-02") {
			continue
		}
		if !validPrice(bar.Open) || !validPrice(bar.High) || !validPrice(bar.Low) || !validPrice(bar.Close) {
			continue
		}
		valid[key] = bar
	}
	if len(valid) == 0 {
		return fmt.Errorf("source returned no valid closed daily bars")
	}
	changes := []domain.DailyBar{}
	for key, bar := range valid {
		old, exists := current[key]
		if !exists || old.Open != bar.Open || old.High != bar.High || old.Low != bar.Low || old.Close != bar.Close {
			changes = append(changes, bar)
		}
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].Date.Before(changes[j].Date) })
	if len(changes) > 0 && s.store != nil {
		if err := s.store.SaveDaily(ctx, changes); err != nil {
			return err
		}
	}
	return nil
}
func validPrice(p float64) bool { return p > 0 && !math.IsNaN(p) && !math.IsInf(p, 0) }
