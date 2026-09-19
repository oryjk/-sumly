package application

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"log/slog"
	"math"
	"time"
)

const RealtimeInterval = 5 * time.Second
const RealtimeWindow = 20 * time.Minute

// CollectRealtime 独立于客户端请求持续采集。仅记录新鲜的真实报价，不回填或插值。
func (s *GoldMarketService) CollectRealtime(ctx context.Context) {
	sample := func() {
		if s.store != nil {
			pruneCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
			err := s.store.PruneRealtime(pruneCtx)
			cancel()
			if err != nil && ctx.Err() == nil {
				slog.Error("prune gold samples failed", "error", err)
			}
		}
		requestCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
		defer cancel()
		quote, err := s.source.FetchGoldQuote(requestCtx)
		if err == nil && ctx.Err() == nil {
			s.mu.Lock()
			s.quote, s.quoteAt = quote, s.now()
			s.mu.Unlock()
			now := s.now()
			if s.validRealtime(quote, now) && s.store != nil {
				point := domain.RealtimePoint{Time: s.sampleTime(quote, now), SourceTime: quote.AsOf, Price: s.realtimePrice(quote)}
				if err := s.store.SaveRealtime(requestCtx, point); err != nil {
					slog.Error("persist gold sample failed", "error", err)
					return
				}
				s.recordRealtimeAt(quote, now)
			} else if s.store == nil {
				s.recordRealtimeAt(quote, now)
			}
		}
	}
	ticker := time.NewTicker(RealtimeInterval)
	defer ticker.Stop()
	sample()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			sample()
		}
	}
}

func (s *GoldMarketService) validRealtime(q domain.GoldQuote, now time.Time) bool {
	price := s.realtimePrice(q)
	return q.Price > 0 && price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) && !q.AsOf.After(now.Add(5*time.Second)) && now.Sub(q.AsOf) <= (120+time.Duration(q.SourceDelaySeconds))*time.Second
}

func (s *GoldMarketService) recordRealtime(q domain.GoldQuote) { s.recordRealtimeAt(q, s.now()) }
func (s *GoldMarketService) recordRealtimeAt(q domain.GoldQuote, now time.Time) {
	if !s.validRealtime(q, now) {
		return
	}
	price := s.realtimePrice(q)
	now = s.sampleTime(q, now)
	s.realtimeMu.Lock()
	defer s.realtimeMu.Unlock()
	s.pruneRealtime(q.AsOf)
	point := domain.RealtimePoint{Time: now, SourceTime: q.AsOf, Price: price}
	if n := len(s.realtime); n > 0 {
		last := s.realtime[n-1]
		if !point.Time.After(last.Time) {
			return
		}
		if point.Time.Unix()/5 == last.Time.Unix()/5 {
			s.realtime[n-1] = point
			return
		}
	}
	s.realtime = append(s.realtime, point)
}

func (s *GoldMarketService) pruneRealtime(now time.Time) {
	cutoff := now.Add(-RealtimeWindow)
	first := 0
	for first < len(s.realtime) && s.realtime[first].Time.Before(cutoff) {
		first++
	}
	if first > 0 {
		s.realtime = append([]domain.RealtimePoint(nil), s.realtime[first:]...)
	}
}

func (s *GoldMarketService) RealtimePoints() []domain.RealtimePoint {
	s.realtimeMu.Lock()
	defer s.realtimeMu.Unlock()
	return append([]domain.RealtimePoint(nil), s.realtime...)
}

// Delayed feeds retain the actual event timestamp; polling never manufactures newer events.
func (s *GoldMarketService) sampleTime(q domain.GoldQuote, now time.Time) time.Time {
	if q.SourceDelaySeconds > 0 {
		return q.AsOf
	}
	return now
}
