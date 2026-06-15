-- Server-side timing harness. Measures EXECUTE latency with clock_timestamp(),
-- so reported ms is pure server execution+planning, excluding client/docker round-trip.
-- Each iteration re-plans (no prepared statement) which matches a normal ad-hoc query.

CREATE OR REPLACE FUNCTION bench_time(p_sql text, p_runs int, p_warmup int DEFAULT 3)
RETURNS double precision[]
LANGUAGE plpgsql AS $$
DECLARE
  t0  timestamptz;
  arr double precision[] := '{}';
  i   int;
BEGIN
  FOR i IN 1..p_warmup LOOP EXECUTE p_sql; END LOOP;     -- warm cache + plan
  FOR i IN 1..p_runs LOOP
    t0  := clock_timestamp();
    EXECUTE p_sql;
    arr := arr || (extract(epoch FROM clock_timestamp() - t0) * 1000.0);
  END LOOP;
  RETURN arr;
END $$;

-- Convenience: returns one row of percentiles for a query.
CREATE OR REPLACE FUNCTION bench_stats(p_sql text, p_runs int DEFAULT 12, p_warmup int DEFAULT 3)
RETURNS TABLE(p50_ms double precision, p95_ms double precision, min_ms double precision, n int)
LANGUAGE sql AS $$
  WITH t AS (SELECT unnest(bench_time(p_sql, p_runs, p_warmup)) AS ms)
  SELECT round(percentile_cont(0.5)  WITHIN GROUP (ORDER BY ms)::numeric, 3)::float8,
         round(percentile_cont(0.95) WITHIN GROUP (ORDER BY ms)::numeric, 3)::float8,
         round(min(ms)::numeric, 3)::float8,
         count(*)::int
  FROM t;
$$;
