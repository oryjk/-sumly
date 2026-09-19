package postgres

import (
	"context"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/ports"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	queries *marketsqlc.Queries
	symbol  string
	native  bool
}

var _ ports.GoldHistoryStore = (*Repository)(nil)

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{queries: marketsqlc.New(pool), symbol: "XAUUSD"}
}
func timestamp(t time.Time) pgtype.Timestamptz { return pgtype.Timestamptz{Time: t, Valid: true} }

func (r *Repository) SaveRealtime(ctx context.Context, p domain.RealtimePoint) error {
	if r.native {
		return r.queries.SaveNativeSample(ctx, marketsqlc.SaveNativeSampleParams{Instrument: r.symbol, Bucket: timestamp(p.Time.Truncate(5 * time.Second)), SampledAt: timestamp(p.Time), SourceAt: timestamp(p.SourceTime), Price: p.Price})
	}
	return r.queries.SaveRealtime(ctx, marketsqlc.SaveRealtimeParams{
		Bucket: timestamp(p.Time.Truncate(5 * time.Second)), SampledAt: timestamp(p.Time), SourceAt: timestamp(p.SourceTime), PriceCny: p.Price,
	})
}
func (r *Repository) PruneRealtime(ctx context.Context) error {
	if r.native {
		return r.queries.PruneNativeSamples(ctx, r.symbol)
	}
	return r.queries.PruneRealtime(ctx)
}
func (r *Repository) LoadRealtime(ctx context.Context) ([]domain.RealtimePoint, error) {
	if r.native {
		rows, err := r.queries.LoadNativeSamples(ctx, r.symbol)
		if err != nil {
			return nil, err
		}
		result := make([]domain.RealtimePoint, 0, len(rows))
		for _, row := range rows {
			result = append(result, domain.RealtimePoint{Time: row.SampledAt.Time, SourceTime: row.SourceAt.Time, Price: row.Price})
		}
		return result, nil
	}
	rows, err := r.queries.LoadRealtime(ctx)
	if err != nil {
		return nil, err
	}
	result := make([]domain.RealtimePoint, 0, len(rows))
	for _, row := range rows {
		result = append(result, domain.RealtimePoint{Time: row.SampledAt.Time, SourceTime: row.SourceAt.Time, Price: row.PriceCny})
	}
	return result, nil
}
func (r *Repository) SaveDaily(ctx context.Context, bars []domain.DailyBar) error {
	if len(bars) == 0 {
		return nil
	}
	params := marketsqlc.SaveDailyParams{Symbol: r.symbol}
	// DATE 使用交易日的年月日，不能把北京时间零点先转换成 UTC 的前一天。
	for _, bar := range bars {
		year, month, day := bar.Date.Date()
		params.Dates = append(params.Dates, pgtype.Date{Time: time.Date(year, month, day, 0, 0, 0, 0, time.UTC), Valid: true})
		params.Opens = append(params.Opens, bar.Open)
		params.Highs = append(params.Highs, bar.High)
		params.Lows = append(params.Lows, bar.Low)
		params.Closes = append(params.Closes, bar.Close)
	}
	return r.queries.SaveDaily(ctx, params)
}
func (r *Repository) LoadDaily(ctx context.Context) ([]domain.DailyBar, error) {
	rows, err := r.queries.LoadDaily(ctx, r.symbol)
	if err != nil {
		return nil, err
	}
	result := make([]domain.DailyBar, 0, len(rows))
	zone := time.FixedZone("CST", 8*3600)
	for _, row := range rows {
		year, month, day := row.TradingDate.Time.Date()
		result = append(result, domain.DailyBar{Date: time.Date(year, month, day, 0, 0, 0, 0, zone), Open: row.Open, High: row.High, Low: row.Low, Close: row.Close})
	}
	return result, nil
}

// NewNativeRepository scopes every query to one instrument and keeps its original quote unit.
func NewNativeRepository(pool *pgxpool.Pool, symbol string) *Repository {
	return &Repository{queries: marketsqlc.New(pool), symbol: symbol, native: true}
}
