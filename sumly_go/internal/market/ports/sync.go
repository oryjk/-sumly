package ports

import (
	"context"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"time"
)

type HistorySyncStore interface {
	SyncHistory(context.Context, string, string) (domain.HistorySync, error)
}
type AnnualHistoryStore interface {
	LoadAnnual(context.Context) ([]domain.GoldHistoryPoint, error)
}
type DailySyncSchedule interface {
	TryDailySync(context.Context, time.Time) (bool, error)
	FinishDailySync(context.Context, time.Time, bool) error
}
