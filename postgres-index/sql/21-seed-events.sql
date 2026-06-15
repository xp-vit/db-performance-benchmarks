-- Deterministic seed for events + events_shuffled.
-- Parameter:  :events  number of rows.
-- events is inserted in id order with strictly monotonic ts  => pg_stats.correlation ~ 1.0.
-- events_shuffled holds the SAME rows ordered by a hash      => correlation ~ 0.0.

\set ON_ERROR_STOP on
\echo seeding events = :events

TRUNCATE events, events_shuffled;

INSERT INTO events (id, ts, device_id, value)
SELECT g,
       '2020-01-01 00:00:00+00'::timestamptz + (g * interval '1 second'),  -- strictly monotonic
       (u01(g, 81) * 10000)::int,
       u01(g, 82) * 100.0
FROM generate_series(1, :events) g;

-- same rows, deliberately scrambled on disk
INSERT INTO events_shuffled
SELECT id, ts, device_id, value
FROM events
ORDER BY u01(id, 99);

ANALYZE events;
ANALYZE events_shuffled;

\echo seeded events. correlation check (ordered should be ~1, shuffled ~0):
SELECT 'events'          AS tbl, correlation FROM pg_stats WHERE tablename='events'          AND attname='ts'
UNION ALL
SELECT 'events_shuffled' AS tbl, correlation FROM pg_stats WHERE tablename='events_shuffled' AND attname='ts';
