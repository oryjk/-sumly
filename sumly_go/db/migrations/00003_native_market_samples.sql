-- +goose Up
-- Legacy gold_realtime_samples remains CNY/g for the existing iOS API.
CREATE TABLE gold_native_samples (
    instrument TEXT NOT NULL,
    bucket TIMESTAMPTZ NOT NULL,
    sampled_at TIMESTAMPTZ NOT NULL,
    source_at TIMESTAMPTZ NOT NULL,
    price DOUBLE PRECISION NOT NULL CHECK (price > 0 AND price < 'Infinity'::float8),
    PRIMARY KEY (instrument, bucket)
);
CREATE INDEX gold_native_samples_window_idx ON gold_native_samples(instrument, source_at);
-- +goose Down
DROP TABLE gold_native_samples;
