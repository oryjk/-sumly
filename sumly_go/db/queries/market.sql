-- name: SaveRealtime :exec
INSERT INTO gold_realtime_samples (symbol, bucket, sampled_at, source_at, price_cny)
VALUES ('XAUUSD', $1, $2, $3, $4)
ON CONFLICT (symbol, bucket) DO UPDATE SET sampled_at=EXCLUDED.sampled_at,
 source_at=EXCLUDED.source_at, price_cny=EXCLUDED.price_cny
WHERE EXCLUDED.sampled_at > gold_realtime_samples.sampled_at;

-- name: PruneRealtime :exec
DELETE FROM gold_realtime_samples WHERE symbol='XAUUSD' AND sampled_at <
 (SELECT MAX(source_at) - INTERVAL '20 minutes' FROM gold_realtime_samples WHERE symbol='XAUUSD');

-- name: LoadRealtime :many
SELECT sampled_at, source_at, price_cny FROM gold_realtime_samples
WHERE symbol='XAUUSD' AND sampled_at >=
 (SELECT MAX(source_at) - INTERVAL '20 minutes' FROM gold_realtime_samples WHERE symbol='XAUUSD') ORDER BY sampled_at;

-- name: SaveDaily :exec
INSERT INTO gold_daily_bars (symbol, trading_date, open, high, low, close)
SELECT sqlc.arg(symbol)::text, unnest(sqlc.arg(dates)::date[]), unnest(sqlc.arg(opens)::float8[]),
 unnest(sqlc.arg(highs)::float8[]), unnest(sqlc.arg(lows)::float8[]), unnest(sqlc.arg(closes)::float8[])
ON CONFLICT (symbol, trading_date) DO UPDATE SET open=EXCLUDED.open, high=EXCLUDED.high,
 low=EXCLUDED.low, close=EXCLUDED.close, updated_at=NOW()
WHERE (gold_daily_bars.open,gold_daily_bars.high,gold_daily_bars.low,gold_daily_bars.close)
 IS DISTINCT FROM (EXCLUDED.open,EXCLUDED.high,EXCLUDED.low,EXCLUDED.close);

-- name: LoadDaily :many
SELECT trading_date, open, high, low, close FROM gold_daily_bars
WHERE symbol=$1 ORDER BY trading_date;

-- name: SaveNativeSample :exec
INSERT INTO gold_native_samples(instrument,bucket,sampled_at,source_at,price)
VALUES($1,$2,$3,$4,$5)
ON CONFLICT(instrument,bucket) DO UPDATE SET sampled_at=EXCLUDED.sampled_at,source_at=EXCLUDED.source_at,price=EXCLUDED.price
WHERE EXCLUDED.sampled_at > gold_native_samples.sampled_at;

-- name: PruneNativeSamples :exec
DELETE FROM gold_native_samples AS target WHERE target.instrument=$1 AND target.sampled_at <
 (SELECT MAX(latest.source_at)-INTERVAL '20 minutes' FROM gold_native_samples AS latest WHERE latest.instrument=$1);

-- name: LoadNativeSamples :many
SELECT target.sampled_at,target.source_at,target.price FROM gold_native_samples AS target WHERE target.instrument=$1 AND target.sampled_at >=
 (SELECT MAX(latest.source_at)-INTERVAL '20 minutes' FROM gold_native_samples AS latest WHERE latest.instrument=$1) ORDER BY sampled_at;
