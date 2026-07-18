-- Build the PK + the "couple of indexes" after the bulk load, then ANALYZE.
-- These are the indexes the REINDEX workload rebuilds and the bitmap-scan
-- workload relies on.
\set ON_ERROR_STOP on

ALTER TABLE events ADD CONSTRAINT events_pkey PRIMARY KEY (id);

-- composite index for the multi-tenant time-range access path
CREATE INDEX IF NOT EXISTS events_tenant_ts ON events (tenant_id, ts);
-- low-cardinality index whose matches are scattered across the heap ->
-- a range/IN predicate on it produces a bitmap heap scan over many pages
CREATE INDEX IF NOT EXISTS events_type_status ON events (event_type, status);

ANALYZE events;

INSERT INTO load_progress (table_name, max_id)
VALUES ('events_finalized', 1)
ON CONFLICT (table_name) DO UPDATE SET max_id = 1, updated_at = now();
