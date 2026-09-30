\set ON_ERROR_STOP on
\if :{?apply}
\else
\set apply false
\endif
BEGIN;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE sge_history_input (
 trading_date date PRIMARY KEY,
 open double precision NOT NULL,
 high double precision NOT NULL,
 low double precision NOT NULL,
 close double precision NOT NULL,
 source_url text NOT NULL CHECK (source_url LIKE 'https://www.sge.com.cn/sjzx/mrhqsj/%'),
 source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
 CHECK (low > 0 AND high >= low AND open BETWEEN low AND high AND close BETWEEN low AND high),
 CHECK (open NOT IN ('NaN','Infinity','-Infinity') AND high NOT IN ('NaN','Infinity','-Infinity')
  AND low NOT IN ('NaN','Infinity','-Infinity') AND close NOT IN ('NaN','Infinity','-Infinity'))
);
\copy sge_history_input FROM 'sge-au9999.csv' WITH (FORMAT csv, HEADER true)

DO $$ BEGIN
 IF (SELECT count(*) FROM sge_history_input) <> 3794
  OR (SELECT min(trading_date) FROM sge_history_input) <> DATE '2002-10-31'
  OR (SELECT max(trading_date) FROM sge_history_input) <> DATE '2023-12-29' THEN
  RAISE EXCEPTION 'Unexpected dataset; verify audit.json and CSV checksum';
 END IF;
END $$;

-- Briefly serialize daily writers so the before/after checks share one state.
LOCK TABLE gold_daily_bars IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE sge_existing AS SELECT * FROM gold_daily_bars;
CREATE TEMP TABLE sge_new AS
 SELECT i.* FROM sge_history_input i WHERE NOT EXISTS (
  SELECT 1 FROM gold_daily_bars b WHERE b.symbol='AU9999' AND b.trading_date=i.trading_date
 );

-- Preserve every existing observation; fill only absent days.
INSERT INTO gold_daily_bars(symbol,trading_date,open,high,low,close)
SELECT 'AU9999',trading_date,open,high,low,close FROM sge_new ORDER BY trading_date
ON CONFLICT (symbol,trading_date) DO NOTHING;

DO $$ BEGIN
 IF EXISTS (SELECT * FROM sge_existing EXCEPT SELECT * FROM gold_daily_bars) THEN
  RAISE EXCEPTION 'An existing daily observation changed';
 END IF;
 IF EXISTS (
  SELECT 1 FROM sge_new i LEFT JOIN market_history_points p
   ON p.symbol='AU9999' AND p.trading_date=i.trading_date AND p.granularity='daily'
  WHERE p.symbol IS NULL OR p.deleted OR p.source <> 'sge'
   OR (p.open,p.high,p.low,p.close) IS DISTINCT FROM (i.open,i.high,i.low,i.close)
 ) THEN RAISE EXCEPTION 'History projection failed; no data committed'; END IF;
 IF (SELECT count(*) FROM gold_daily_bars) <>
  (SELECT count(*) FROM sge_existing) + (SELECT count(*) FROM sge_new) THEN
  RAISE EXCEPTION 'Unexpected daily row count';
 END IF;
END $$;

SELECT count(*) AS inserted_days, min(trading_date) AS first_inserted,
 max(trading_date) AS last_inserted FROM sge_new;
SELECT count(*) AS domestic_days, min(trading_date), max(trading_date)
FROM gold_daily_bars WHERE symbol='AU9999';
SELECT revision AS history_revision FROM market_history_clock;

-- Default to a rollback. To apply after inspecting the dry run, pass -v apply=1.
\if :apply
COMMIT;
\else
ROLLBACK;
\endif
