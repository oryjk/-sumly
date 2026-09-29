package application

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"math"
	"sort"
	"time"
)

type DailyGoldHistory interface {
	GetGoldDailyKLines(context.Context) ([]domain.DailyBar, error)
}
type GoldHistory struct {
	daily       DailyGoldHistory
	annual      []domain.GoldHistoryPoint
	annualStore ports.AnnualHistoryStore
}

func NewGoldHistory(daily DailyGoldHistory, annual []domain.GoldHistoryPoint) *GoldHistory {
	return &GoldHistory{daily: daily, annual: append([]domain.GoldHistoryPoint(nil), annual...)}
}
func NewStoredGoldHistory(daily DailyGoldHistory, store ports.AnnualHistoryStore) *GoldHistory {
	return &GoldHistory{daily: daily, annualStore: store}
}
func (s *GoldHistory) GetGoldHistory(ctx context.Context) ([]domain.GoldHistoryPoint, error) {
	bars, err := s.daily.GetGoldDailyKLines(ctx)
	if err != nil {
		return nil, err
	}
	points := append([]domain.GoldHistoryPoint(nil), s.annual...)
	if s.annualStore != nil {
		points, err = s.annualStore.LoadAnnual(ctx)
		if err != nil {
			return nil, err
		}
	}
	now := time.Now()
	byDay := map[string]domain.DailyBar{}
	for _, bar := range bars {
		if bar.Date.Year() < 2016 || bar.Date.After(now) || bar.Close <= 0 || math.IsNaN(bar.Close) || math.IsInf(bar.Close, 0) {
			continue
		}
		byDay[bar.Date.Format("2006-01-02")] = bar
	}
	for _, bar := range byDay {
		points = append(points, domain.GoldHistoryPoint{Date: bar.Date, Price: bar.Close, Granularity: "daily", Source: "sina-xauusd"})
	}
	sort.Slice(points, func(i, j int) bool { return points[i].Date.Before(points[j].Date) })
	return points, nil
}
