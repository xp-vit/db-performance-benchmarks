-- Scenario 10: every index is a write tax. Measure insert throughput + WAL as a function
-- of how many indexes the table carries. run.sh creates 0..8 of these between runs.
DROP TABLE IF EXISTS t10 CASCADE;
CREATE TABLE t10 (
  id bigint, a bigint, b bigint, c timestamptz, d text, e bigint, f integer, g text
);
-- candidate indexes (added incrementally):
--   t10_a (a)  t10_b (b)  t10_c (c)  t10_d (d)  t10_e (e)  t10_f (f)  t10_g (g)  t10_ab (a,b)
