package application

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"math"
)

// GetGoldRealtime 停更时将窗口固定在上游最后报价时间，不能随墙上时钟消失。
// 五秒历史缺失时仅回退到真实分钟记录，通过返回的间隔明确区分；不回填采样库。
func (s *GoldMarketService) GetGoldRealtime(ctx context.Context) ([]domain.RealtimePoint, int, error) {
	points := s.RealtimePoints()
	quote, err := s.GetGoldQuote(ctx)
	if err != nil {
		if len(points) == 0 {
			return nil, 5, err
		}
		last := points[len(points)-1]
		return frozenWindow(points, domain.RealtimePoint{Time: last.SourceTime, SourceTime: last.SourceTime, Price: last.Price}), 5, nil
	}
	if s.validRealtime(quote, s.now()) && len(points) > 1 {
		return points, 5, nil
	}
	if quote.AsOf.IsZero() || quote.AsOf.After(s.now()) || s.realtimePrice(quote) <= 0 || math.IsNaN(s.realtimePrice(quote)) || math.IsInf(s.realtimePrice(quote), 0) {
		return points, 5, nil
	}
	end := domain.RealtimePoint{Time: quote.AsOf, SourceTime: quote.AsOf, Price: s.realtimePrice(quote)}
	// 并发请求返回的旧报价不能让已采集的窗口倒退。
	if len(points) > 0 && points[len(points)-1].SourceTime.After(end.Time) {
		last := points[len(points)-1]
		end = domain.RealtimePoint{Time: last.SourceTime, SourceTime: last.SourceTime, Price: last.Price}
	}
	frozen := frozenWindow(points, end)
	if len(frozen) > 1 {
		return frozen, 5, nil
	}
	minutes, minuteErr := s.GetGoldIntraday(ctx)
	if minuteErr != nil {
		return frozen, 5, nil
	}
	recovered := make([]domain.RealtimePoint, 0, len(minutes))
	for _, p := range minutes {
		price := p.Price
		if !s.nativeRealtime {
			price = p.Price / domain.GramsPerTroyOunce * quote.USDCNY
		}
		if price > 0 && !math.IsNaN(price) && !math.IsInf(price, 0) {
			recovered = append(recovered, domain.RealtimePoint{Time: p.Time, SourceTime: p.Time, Price: price})
		}
	}
	return frozenWindow(recovered, end), 60, nil
}

func frozenWindow(points []domain.RealtimePoint, end domain.RealtimePoint) []domain.RealtimePoint {
	cutoff := end.Time.Add(-RealtimeWindow)
	result := make([]domain.RealtimePoint, 0, len(points)+1)
	for _, p := range points {
		if !p.Time.Before(cutoff) && p.Time.Before(end.Time) {
			result = append(result, p)
		}
	}
	return append(result, end)
}
