-- Reference: the five workloads under test. The drivers issue these (with
-- per-session SET for parallelism / io concurrency); this file documents them.

-- 1) COLD large sequential scan (single process, so async prefetch is the variable)
--    SET max_parallel_workers_per_gather = 0;
SELECT count(*), sum(amount_cents), avg(amount_cents) FROM events;

-- 2) Bitmap heap scan: ~5% of rows, scattered across the heap via a low-card index
--    (event_type IN (2,5) -> 2/8, AND status = 3 -> 1/5  => ~5%)
SELECT count(*), sum(amount_cents) FROM events
WHERE event_type IN (2,5) AND status = 3;

-- 3a) VACUUM after a bulk update (dead tuples scattered -> read-heavy vacuum).
--     The driver first does an (unmeasured) UPDATE over a ~10% slice, then:
VACUUM (VERBOSE) events;

-- 3b) plain VACUUM on the freshly loaded table (baseline, little to do)
VACUUM events;

-- 4) Index build / REINDEX (reads the whole heap to rebuild an index)
REINDEX INDEX events_tenant_ts;

-- 5) WARM OLTP point lookups (the honest boundary: async I/O should NOT help).
--    Driver runs many single-row PK lookups from cache.
SELECT * FROM events WHERE id = $1;
