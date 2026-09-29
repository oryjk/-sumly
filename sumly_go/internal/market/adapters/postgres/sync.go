package postgres

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	marketsqlc "gitee.com/oryjk/sumly/sumly_go/internal/market/adapters/postgres/sqlc"
	"gitee.com/oryjk/sumly/sumly_go/internal/market/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

func dateOnly(t time.Time) pgtype.Date {
	y, m, d := t.Date()
	return pgtype.Date{Time: time.Date(y, m, d, 0, 0, 0, 0, time.UTC), Valid: true}
}
func (r *Repository) SeedAnnual(ctx context.Context, points []domain.GoldHistoryPoint) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	q := r.queries.WithTx(tx)
	if _, err = q.ClaimHistorySeed(ctx, "usgs-ds140-1900-2015-v1"); errors.Is(err, pgx.ErrNoRows) {
		return nil
	} else if err != nil {
		return err
	}
	if len(points) != 116 {
		return fmt.Errorf("annual seed must contain 116 years")
	}
	params := marketsqlc.SeedAnnualHistoryParams{}
	for _, p := range points {
		params.Dates = append(params.Dates, dateOnly(p.Date))
		params.Prices = append(params.Prices, p.Price)
	}
	if err = q.SeedAnnualHistory(ctx, params); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func (r *Repository) LoadAnnual(ctx context.Context) ([]domain.GoldHistoryPoint, error) {
	rows, err := r.queries.LoadAnnualHistory(ctx)
	if err != nil {
		return nil, err
	}
	points := make([]domain.GoldHistoryPoint, 0, len(rows))
	for _, row := range rows {
		points = append(points, domain.GoldHistoryPoint{Date: row.TradingDate.Time, Price: row.Close, Granularity: "annual", Source: row.Source})
	}
	return points, nil
}
func (r *Repository) SyncHistory(ctx context.Context, series, cursor string) (domain.HistorySync, error) {
	result := domain.HistorySync{Series: series, Unit: "USD/troy_oz", Points: []domain.HistoryChange{}}
	symbol := ""
	switch series {
	case "xauusd":
		symbol = "XAUUSD"
	case "au9999":
		symbol = "AU9999"
		result.Unit = "CNY/g"
	case "comex-gold":
		symbol = "GCZ26.CMX"
	default:
		return result, fmt.Errorf("unknown series")
	}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return result, err
	}
	defer tx.Rollback(ctx)
	q := r.queries.WithTx(tx)
	clock, err := q.HistoryClock(ctx)
	if err != nil {
		return result, err
	}
	prefix := clock.Epoch + ":" + series + ":"
	revision, parseErr := strconv.ParseInt(strings.TrimPrefix(cursor, prefix), 10, 64)
	result.Reset = !strings.HasPrefix(cursor, prefix) || parseErr != nil || revision < 0 || revision > clock.Revision
	if result.Reset {
		revision = 0
	}
	rows, err := q.HistoryDelta(ctx, marketsqlc.HistoryDeltaParams{Symbol: symbol, Revision: revision})
	if err != nil {
		return result, err
	}
	for _, row := range rows {
		if result.Reset && row.Deleted {
			continue
		}
		result.Points = append(result.Points, domain.HistoryChange{Date: row.TradingDate.Time.Format("2006-01-02"), Granularity: row.Granularity, Open: row.Open, High: row.High, Low: row.Low, Close: row.Close, Source: row.Source, Deleted: row.Deleted})
	}
	result.Cursor = prefix + strconv.FormatInt(clock.Revision, 10)
	return result, tx.Commit(ctx)
}
func (r *Repository) TryDailySync(ctx context.Context, now time.Time) (bool, error) {
	_, err := r.queries.TryDailySync(ctx, marketsqlc.TryDailySyncParams{Symbol: r.symbol, NowAt: timestamp(now), Day: dateOnly(now.UTC().Add(-8 * time.Hour))})
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}
func (r *Repository) FinishDailySync(ctx context.Context, now time.Time, success bool) error {
	return r.queries.FinishDailySync(ctx, marketsqlc.FinishDailySyncParams{Symbol: r.symbol, Day: dateOnly(now.UTC().Add(-8 * time.Hour)), Success: success})
}
