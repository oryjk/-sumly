-- +goose Up
CREATE TABLE gold_realtime_samples (
    symbol TEXT NOT NULL,
    bucket TIMESTAMPTZ NOT NULL,
    sampled_at TIMESTAMPTZ NOT NULL,
    source_at TIMESTAMPTZ NOT NULL,
    price_cny DOUBLE PRECISION NOT NULL CHECK (price_cny > 0 AND price_cny < 'Infinity'::float8),
    PRIMARY KEY (symbol, bucket)
);
CREATE INDEX gold_realtime_samples_retention_idx ON gold_realtime_samples (sampled_at);

CREATE TABLE gold_daily_bars (
    symbol TEXT NOT NULL,
    trading_date DATE NOT NULL,
    open DOUBLE PRECISION NOT NULL CHECK (open > 0 AND open < 'Infinity'::float8),
    high DOUBLE PRECISION NOT NULL CHECK (high > 0 AND high < 'Infinity'::float8),
    low DOUBLE PRECISION NOT NULL CHECK (low > 0 AND low < 'Infinity'::float8),
    close DOUBLE PRECISION NOT NULL CHECK (close > 0 AND close < 'Infinity'::float8),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (symbol, trading_date)
);

-- +goose Down
DROP TABLE gold_daily_bars;
DROP TABLE gold_realtime_samples;
