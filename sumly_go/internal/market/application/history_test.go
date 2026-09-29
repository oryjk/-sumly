package application_test

import (
	"context"
	"errors"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/historical"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/application"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"testing"
	"time"
)

type historyDaily struct {
	bars []domain.DailyBar
	err  error
}

func (s historyDaily) GetGoldDailyKLines(context.Context) ([]domain.DailyBar, error) {
	return s.bars, s.err
}
func TestHistoryJoinsAnnualAndDailyWithoutInventingDays(t *testing.T) {
	annual, err := historical.AnnualGold()
	if err != nil {
		t.Fatal(err)
	}
	if len(annual) != 116 || annual[0].Date.Year() != 1900 || annual[115].Date.Year() != 2015 {
		t.Fatal("annual coverage")
	}
	if annual[0].Price != 609000*domain.GramsPerTroyOunce/1000000 {
		t.Fatal("nominal USD/ton conversion")
	}
	day := func(s string) time.Time { v, _ := time.Parse("2006-01-02", s); return v }
	service := application.NewGoldHistory(historyDaily{bars: []domain.DailyBar{
		{Date: day("2015-12-31"), Close: 999}, {Date: day("2016-01-05"), Close: 1080},
		{Date: day("2016-01-04"), Close: 1070}, {Date: day("2016-01-04"), Close: 1071},
		{Date: day("2016-01-06"), Close: 0}, {Date: day("2999-01-01"), Close: 1000},
	}}, annual)
	points, err := service.GetGoldHistory(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(points) != 118 || points[116].Date.Format("2006-01-02") != "2016-01-04" || points[117].Price != 1080 {
		t.Fatalf("bad join: %+v", points[115:])
	}
	if points[115].Granularity != "annual" || points[116].Granularity != "daily" {
		t.Fatal("lost granularity")
	}
}
func TestHistoryReportsDailyFailureInsteadOfPresentingOldAnnualDataAsCurrent(t *testing.T) {
	s := application.NewGoldHistory(historyDaily{err: errors.New("offline")}, nil)
	if _, err := s.GetGoldHistory(context.Background()); err == nil {
		t.Fatal("hidden unavailable daily data")
	}
}
