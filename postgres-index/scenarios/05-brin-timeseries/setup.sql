-- Scenario 05: BRIN on a time-ordered table.
-- On events (physical order == ts order) BRIN is tiny and competitive on range scans.
-- On events_shuffled (same rows, random order) the BRIN range scan collapses to seq-scan time.
CREATE INDEX IF NOT EXISTS e05_brin_ts        ON events          USING brin (ts);
CREATE INDEX IF NOT EXISTS e05_btree_ts       ON events          USING btree (ts);
CREATE INDEX IF NOT EXISTS e05_brin_ts_shuf   ON events_shuffled USING brin (ts);
