package ports

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
)

// GoldHistoryStore 秒级样本按保留窗口清理；日线按交易日幂等保存、长期保留。
type GoldHistoryStore interface {
	SaveRealtime(context.Context, domain.RealtimePoint) error
	PruneRealtime(context.Context) error
	LoadRealtime(context.Context) ([]domain.RealtimePoint, error)
	SaveDaily(context.Context, []domain.DailyBar) error
	LoadDaily(context.Context) ([]domain.DailyBar, error)
}
