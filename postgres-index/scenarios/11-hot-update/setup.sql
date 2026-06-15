-- Scenario 11: indexing a frequently-updated column disables the HOT-update optimization,
-- so every update must write every index. Raising fillfactor restores some HOT headroom.
-- run.sh builds t11 with the right fillfactor / index per config.
DROP TABLE IF EXISTS t11 CASCADE;
-- created per-config in run.sh:
--   CREATE TABLE t11 (id bigint PRIMARY KEY, h bigint, pad text) WITH (fillfactor=...);
--   [CREATE INDEX t11_h ON t11 (h);]   -- the hot column index that kills HOT
