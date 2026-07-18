-- Async I/O benchmark schema: one big multi-tenant table + related tables.
-- Heap is loaded WITHOUT secondary indexes (those are built at finalize and
-- rebuilt by the REINDEX workload). Everything is a pure function of the row
-- id so the load is deterministic and resumable.
\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS customers (
  id           bigint PRIMARY KEY,
  tenant_id    int         NOT NULL,
  email        text        NOT NULL,
  created_at   timestamptz NOT NULL
);

-- The big table: an append-heavy multi-tenant event ledger.
-- Row width is deliberately ~250-300B so 30M rows is ~8-9GB of heap -> a cold
-- sequential scan does real storage I/O even with 4GB shared_buffers.
CREATE TABLE IF NOT EXISTS events (
  id           bigint      NOT NULL,        -- PK added at finalize (kept off during load)
  tenant_id    int         NOT NULL,        -- ~500 tenants, skewed
  customer_id  bigint      NOT NULL,        -- FK-shaped, not enforced (load speed)
  ts           timestamptz NOT NULL,        -- monotonic-ish, correlated with id
  event_type   smallint    NOT NULL,        -- ~8 values; drives the bitmap-scan predicate
  status       smallint    NOT NULL,        -- ~5 values
  amount_cents bigint      NOT NULL,
  region       text        NOT NULL,        -- 4 values
  payload      jsonb       NOT NULL,         -- small realistic doc
  note         text        NOT NULL          -- filler text -> realistic row width
);

-- Progress marker so load.sh can resume after an interruption.
CREATE TABLE IF NOT EXISTS load_progress (
  table_name text PRIMARY KEY,
  max_id     bigint NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Deterministic pseudo-random in [0,1) from an id + salt (parallel-safe, no setseed).
CREATE OR REPLACE FUNCTION u01(seed bigint, salt int)
RETURNS double precision LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT ((hashtextextended(seed::text || ':' || salt::text, 0) & x'7fffffffffffffff'::bigint)
          % 1000000000)::double precision / 1000000000.0
$$;

-- Skewed tenant assignment: a few big tenants carry most rows (power law).
CREATE OR REPLACE FUNCTION tenant_of(seed bigint, n int)
RETURNS int LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT 1 + (floor(power(u01(seed, 7), 2.2) * n))::int
$$;
