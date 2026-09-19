package ports

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

type GoldQuoteSource interface {
	FetchGoldQuote(context.Context) (domain.GoldQuote, error)
}
type GoldDailySource interface {
	FetchGoldDailyKLines(context.Context) ([]domain.DailyBar, error)
}
