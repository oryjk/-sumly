-- +goose Up
-- Unclosed observations are refreshed by quotes and must not become cached history.
DELETE FROM gold_daily_bars WHERE trading_date >= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date;
CREATE TABLE market_history_clock (
 id boolean PRIMARY KEY DEFAULT true CHECK (id),
 epoch uuid NOT NULL DEFAULT gen_random_uuid(),
 revision bigint NOT NULL DEFAULT 0
);
INSERT INTO market_history_clock(id) VALUES(true);
CREATE TABLE market_history_points (
 symbol text NOT NULL,
 trading_date date NOT NULL,
 granularity text NOT NULL CHECK(granularity IN ('annual','daily')),
 open double precision NOT NULL,
 high double precision NOT NULL,
 low double precision NOT NULL,
 close double precision NOT NULL,
 source text NOT NULL,
 deleted boolean NOT NULL DEFAULT false,
 revision bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(symbol,granularity,trading_date)
);
CREATE INDEX market_history_delta ON market_history_points(symbol,revision);
CREATE TABLE market_history_seeds (name text PRIMARY KEY);
CREATE TABLE market_daily_jobs (
 symbol text PRIMARY KEY,
 completed_day date,
 retry_at timestamptz NOT NULL
);
-- A transactional counter serializes writers until commit. Unlike a sequence,
-- a later committed revision can never hide an earlier uncommitted update.
-- +goose StatementBegin
CREATE FUNCTION market_history_revision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE market_history_clock SET revision=revision+1 WHERE id RETURNING revision INTO NEW.revision;
 RETURN NEW;
END;
$$;
-- +goose StatementEnd
CREATE TRIGGER market_history_revision BEFORE INSERT OR UPDATE ON market_history_points
FOR EACH ROW EXECUTE FUNCTION market_history_revision();
-- +goose StatementBegin
CREATE FUNCTION market_daily_projection() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b gold_daily_bars;
BEGIN
 IF TG_OP='DELETE' THEN b:=OLD; ELSE b:=NEW; END IF;
 IF b.trading_date >= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date THEN RETURN NULL; END IF;
 INSERT INTO market_history_points(symbol,trading_date,granularity,open,high,low,close,source,deleted)
 VALUES(b.symbol,b.trading_date,'daily',b.open,b.high,b.low,b.close,
 CASE b.symbol WHEN 'AU9999' THEN 'sge' WHEN 'XAUUSD' THEN 'sina-xauusd' ELSE 'yahoo' END,TG_OP='DELETE')
 ON CONFLICT(symbol,granularity,trading_date) DO UPDATE SET
 open=EXCLUDED.open,high=EXCLUDED.high,low=EXCLUDED.low,close=EXCLUDED.close,source=EXCLUDED.source,deleted=EXCLUDED.deleted
 WHERE (market_history_points.open,market_history_points.high,market_history_points.low,market_history_points.close,market_history_points.deleted)
 IS DISTINCT FROM (EXCLUDED.open,EXCLUDED.high,EXCLUDED.low,EXCLUDED.close,EXCLUDED.deleted);
 RETURN NULL;
END;
$$;
-- +goose StatementEnd
CREATE TRIGGER market_daily_projection AFTER INSERT OR UPDATE OR DELETE ON gold_daily_bars
FOR EACH ROW EXECUTE FUNCTION market_daily_projection();
INSERT INTO market_history_points(symbol,trading_date,granularity,open,high,low,close,source)
SELECT symbol,trading_date,'daily',open,high,low,close,
 CASE symbol WHEN 'AU9999' THEN 'sge' WHEN 'XAUUSD' THEN 'sina-xauusd' ELSE 'yahoo' END
FROM gold_daily_bars WHERE trading_date < (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date;

-- +goose Down
DROP TRIGGER market_daily_projection ON gold_daily_bars;
DROP FUNCTION market_daily_projection();
DROP TABLE market_daily_jobs;
DROP TABLE market_history_seeds;
DROP TABLE market_history_points;
DROP FUNCTION market_history_revision();
DROP TABLE market_history_clock;
