-- The measured operation is a cascade delete of N parents:
--   DELETE FROM p09_parent WHERE id <= N;       -- cascades to ~20*N child rows
-- Without an index on p09_child(parent_id) each parent delete seq-scans the whole child
-- table to enforce the FK => O(N * child_rows). With the index it is O(N * log).
-- A representative join is also timed:
SELECT count(*) FROM p09_parent p JOIN p09_child c ON c.parent_id = p.id WHERE p.id <= 100;
