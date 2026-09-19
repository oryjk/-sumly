package application

import (
	"context"
	"errors"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"testing"
	"time"
)

type intradaySource struct {
	fakeSource
	calls  int
	points []domain.IntradayPoint
}

func (f *intradaySource) FetchGoldIntraday(context.Context) ([]domain.IntradayPoint, error) {
	f.calls++
	return f.points, f.err
}
func TestIntradayCachesReturnsCopiesAndPreservesTimestampOnFailure(t *testing.T) {
	now := time.Now()
	source := &intradaySource{points: []domain.IntradayPoint{{Time: now, Price: 4300}}}
	service := NewGoldMarketService(source)
	service.now = func() time.Time { return now }
	first, err := service.GetGoldIntraday(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	first[0].Price = 1
	second, err := service.GetGoldIntraday(context.Background())
	if err != nil || second[0].Price != 4300 || source.calls != 1 {
		t.Fatalf("cache = %+v, err=%v", second, err)
	}
	now = now.Add(time.Minute)
	source.err = errors.New("offline")
	stale, err := service.GetGoldIntraday(context.Background())
	if err != nil || stale[0].Price != 4300 || !stale[0].Time.Equal(source.points[0].Time) {
		t.Fatalf("stale = %+v, err=%v", stale, err)
	}
}
func TestIntradayFailsWithoutCache(t *testing.T) {
	source := &intradaySource{fakeSource: fakeSource{err: errors.New("offline")}}
	if _, err := NewGoldMarketService(source).GetGoldIntraday(context.Background()); err == nil {
		t.Fatal("expected error")
	}
}
