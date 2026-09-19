package application

import (
	"context"
	"errors"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"testing"
	"time"
)

func TestRealtimeFiveSecondBucketsKeepActualTimeAndHistoricalFX(t *testing.T) {
	s := NewGoldMarketService(&fakeSource{})
	now := time.Date(2026, 9, 18, 15, 0, 2, 0, time.UTC)
	s.now = func() time.Time { return now }
	q := domain.GoldQuote{Price: 3100, USDCNY: 7, AsOf: now}
	s.recordRealtime(q)
	now = now.Add(time.Second)
	q.AsOf = now
	q.Price = 3101
	s.recordRealtime(q)
	points := s.RealtimePoints()
	if len(points) != 1 || !points[0].Time.Equal(q.AsOf) {
		t.Fatalf("same bucket = %+v", points)
	}
	first := points[0].Price
	now = now.Add(5 * time.Second)
	// 同一分钟的上游时间戳也可有真实的新采样。
	q.USDCNY = 8
	s.recordRealtime(q)
	s.recordRealtime(q) // 缓存报价不能生成虚假新样本。
	points = s.RealtimePoints()
	if len(points) != 2 || !points[1].Time.Equal(now) || !points[1].SourceTime.Equal(q.AsOf) || points[0].Price != first || points[1].Price != q.CNYPerGram() {
		t.Fatalf("points=%+v", points)
	}
	points[0].Price = 0
	if s.RealtimePoints()[0].Price != first {
		t.Fatal("caller mutated buffer")
	}
}
func TestRealtimeRejectsStaleInvalidAndEvictsOldSamples(t *testing.T) {
	s := NewGoldMarketService(&fakeSource{})
	now := time.Now()
	s.now = func() time.Time { return now }
	q := domain.GoldQuote{Price: 3100, USDCNY: 7, AsOf: now.Add(-time.Hour)}
	s.recordRealtime(q)
	q.AsOf = now
	q.USDCNY = 0
	s.recordRealtime(q)
	if len(s.RealtimePoints()) != 0 {
		t.Fatal("accepted stale or invalid sample")
	}
	q.USDCNY = 7
	s.recordRealtime(q)
	now = now.Add(21 * time.Minute)
	if len(s.RealtimePoints()) != 1 {
		t.Fatal("last available window disappeared while quotes were paused")
	}
	q.AsOf = now
	s.recordRealtime(q)
	if points := s.RealtimePoints(); len(points) != 1 || !points[0].Time.Equal(now) {
		t.Fatalf("new quote did not advance window: %+v", points)
	}
}

func TestRealtimeDoesNotRecordFallbackCacheWhenSourceFails(t *testing.T) {
	source := &fakeSource{err: errors.New("upstream unavailable")}
	service := NewGoldMarketService(source)
	now := time.Now()
	service.quote = domain.GoldQuote{Price: 4350, USDCNY: 7, AsOf: now}
	service.quoteAt = now.Add(-time.Minute)
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	service.CollectRealtime(ctx)
	if source.quoteCalls != 1 || len(service.RealtimePoints()) != 0 {
		t.Fatal("failed fetch created a new sample from cached quote")
	}
}

type recoverySource struct {
	fakeSource
	minutes []domain.IntradayPoint
}

func (f *recoverySource) FetchGoldIntraday(context.Context) ([]domain.IntradayPoint, error) {
	return f.minutes, f.err
}

func TestRealtimeClosedMarketEndsAtSourceQuoteAndRecoversActualMinutes(t *testing.T) {
	end := time.Date(2026, 9, 19, 4, 54, 0, 0, time.FixedZone("CST", 8*3600))
	q := domain.GoldQuote{Price: 4378.29, USDCNY: 6.6977, AsOf: end}
	source := &recoverySource{fakeSource: fakeSource{quotes: []domain.GoldQuote{q}}}
	for i := 21; i > 0; i-- {
		source.minutes = append(source.minutes, domain.IntradayPoint{Time: end.Add(-time.Duration(i) * time.Minute), Price: 4370})
	}
	s := NewGoldMarketService(source)
	s.now = func() time.Time { return end.Add(48 * time.Hour) }
	points, interval, err := s.GetGoldRealtime(context.Background())
	if err != nil || interval != 60 || len(points) != 21 || !points[0].Time.Equal(end.Add(-RealtimeWindow)) || !points[20].Time.Equal(end) || points[20].Price != q.CNYPerGram() {
		t.Fatalf("recovered: %+v interval=%d err=%v", points, interval, err)
	}
	if len(s.RealtimePoints()) != 0 {
		t.Fatal("minute recovery polluted five-second samples")
	}
}

func TestRealtimeClosedMarketKeepsSecondsAndUsesLastSourceTimestamp(t *testing.T) {
	end := time.Now().Add(-48 * time.Hour).Truncate(time.Minute)
	q := domain.GoldQuote{Price: 4378.29, USDCNY: 6.6977, AsOf: end}
	s := NewGoldMarketService(&fakeSource{quotes: []domain.GoldQuote{q}})
	for i := -250; i <= 12; i++ {
		at := end.Add(time.Duration(i) * 5 * time.Second)
		sourceAt := at
		if at.After(end) {
			sourceAt = end
		}
		s.realtime = append(s.realtime, domain.RealtimePoint{Time: at, SourceTime: sourceAt, Price: 940})
	}
	points, interval, err := s.GetGoldRealtime(context.Background())
	if err != nil || interval != 5 || len(points) != 241 || !points[0].Time.Equal(end.Add(-RealtimeWindow)) || !points[240].Time.Equal(end) || points[240].Price != q.CNYPerGram() {
		t.Fatalf("frozen window: count=%d interval=%d err=%v", len(points), interval, err)
	}
}

func TestNativeRealtimeKeepsOriginalUnitWithoutFX(t *testing.T) {
	for _, currency := range []string{"CNY", "USD"} {
		s := NewNativeGoldMarketService(&fakeSource{}, nil)
		now := time.Now()
		s.now = func() time.Time { return now }
		s.recordRealtime(domain.GoldQuote{Price: 946, Currency: currency, AsOf: now})
		if p := s.RealtimePoints(); len(p) != 1 || p[0].Price != 946 {
			t.Fatalf("%s samples=%+v", currency, p)
		}
	}
}

func TestDelayedFeedPreservesEventTimeAndDoesNotInventTicks(t *testing.T) {
	s := NewNativeGoldMarketService(&fakeSource{}, nil)
	now := time.Now()
	s.now = func() time.Time { return now }
	q := domain.GoldQuote{Price: 4424.9, Currency: "USD", AsOf: now.Add(-30 * time.Minute), SourceDelaySeconds: 1800}
	s.recordRealtime(q)
	now = now.Add(5 * time.Second)
	s.recordRealtime(q)
	points := s.RealtimePoints()
	if len(points) != 1 || !points[0].Time.Equal(q.AsOf) {
		t.Fatalf("delayed data became fresh ticks: %+v", points)
	}
	now = now.Add(48 * time.Hour)
	s.recordRealtime(q)
	if len(s.RealtimePoints()) != 1 {
		t.Fatal("paused history disappeared")
	}
}
