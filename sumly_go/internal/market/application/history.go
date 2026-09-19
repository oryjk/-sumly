package application

import (
	"context"
	"log/slog"
	"time"
)

// RestoreHistory 在采集启动前恢复数据库；以最后有效行情为窗口终点，停更和重启不会清空历史。
func (s *GoldMarketService) RestoreHistory(ctx context.Context) error {
	if s.store == nil {
		return nil
	}
	if err := s.store.PruneRealtime(ctx); err != nil {
		return err
	}
	points, err := s.store.LoadRealtime(ctx)
	if err != nil {
		return err
	}
	bars, err := s.store.LoadDaily(ctx)
	if err != nil {
		return err
	}
	s.realtimeMu.Lock()
	s.realtime = points
	s.realtimeMu.Unlock()
	s.mu.Lock()
	s.daily = bars
	if len(bars) > 0 {
		s.dailyAt = s.now().Add(-s.dailyTTL)
	}
	s.mu.Unlock()
	return nil
}

// CollectDaily 无需用户打开 App 也持续保存日线；首次抓取可补齐上游提供的历史。
func (s *GoldMarketService) CollectDaily(ctx context.Context) {
	refresh := func() {
		requestCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		if _, err := s.GetGoldDailyKLines(requestCtx); err != nil && ctx.Err() == nil {
			slog.Error("collect gold daily failed", "error", err)
		}
	}
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	refresh()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			refresh()
		}
	}
}
