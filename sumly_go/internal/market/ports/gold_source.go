package ports

import (
	"context"

	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

// GoldSource 是行情模块需要的外部数据能力（出站端口）。
// 由 adapters 提供具体实现（如新浪行情），application 只面向本接口编排。
type GoldSource interface {
	FetchGoldQuote(ctx context.Context) (domain.GoldQuote, error)
	FetchGoldDailyKLines(ctx context.Context) ([]domain.DailyBar, error)
}

// GoldIntradaySource 提供最新交易日的分时行情。
type GoldIntradaySource interface {
	FetchGoldIntraday(ctx context.Context) ([]domain.IntradayPoint, error)
}
