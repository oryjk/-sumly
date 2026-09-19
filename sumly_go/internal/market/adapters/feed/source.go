// Package feed 组合各供应商端口，数据抓取仍由各自的外部适配器负责。
package feed

import (
	"context"
	"fmt"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
)

type Source struct {
	Quote    ports.GoldQuoteSource
	Daily    ports.GoldDailySource
	Intraday ports.GoldIntradaySource
}

func (s Source) FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error) {
	return s.Quote.FetchGoldQuote(ctx)
}
func (s Source) FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error) {
	return s.Daily.FetchGoldDailyKLines(ctx)
}
func (s Source) FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error) {
	if s.Intraday == nil {
		return nil, fmt.Errorf("timestamped intraday history unavailable")
	}
	return s.Intraday.FetchGoldIntraday(ctx)
}
