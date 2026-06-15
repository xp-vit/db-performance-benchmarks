-- Wide range scan over a ~0.5% time window (bounds computed from row count in run.sh).
-- ts = '2020-01-01' + id seconds, so a [lo, hi) second window selects a contiguous id range.
SELECT count(*), avg(value)
FROM events
WHERE ts >= timestamptz '2020-01-01 00:00:00+00' + (:lo) * interval '1 second'
  AND ts <  timestamptz '2020-01-01 00:00:00+00' + (:hi) * interval '1 second';
