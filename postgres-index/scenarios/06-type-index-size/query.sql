-- This scenario measures index SIZE, not query latency. The "query" is the size probe:
SELECT pg_relation_size('ts06_idx') AS index_size_bytes;
-- and the uuid insert-locality sub-test times bulk inserts of bigint vs uuidv4 vs uuidv7 keys.
