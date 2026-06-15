# 12 - Partial index: size + latency vs full index

**Hypothesis:** for the common `WHERE status='pending'` path (~5% of rows), a partial index
`WHERE status='pending'` is a fraction of the full-index size and at least as fast; the planner
only uses it when the query predicate matches the partial WHERE.

**Measured:**

| rows | full index `(status, created_at)` | partial `(created_at) WHERE status='pending'` | ratio | full p50 | partial p50 |
| --- | --- | --- | --- | --- | --- |
| 1M | 33 MB | 1.0 MB | 32x | 0.023 ms | 0.023 ms |
| 10M | 330 MB | 10 MB | 33x | 0.029 ms | 0.022 ms |
| 30M | 988 MB | 30 MB | 33x | 0.026 ms | 0.024 ms |

**Finding:** held on every count. The partial index is ~32-33x smaller than the full composite
(it indexes only the ~5% `pending` slice and only `created_at`), and serves the matching query
at the same sub-millisecond latency. The planner uses the partial index when the query
predicate matches (`partial_used_on_match=true`) and correctly **skips** it when the query asks
for `status='paid'` (`partial_skipped_on_mismatch=true`), falling back to another path.

**Caveat:** the 32x size ratio combines two effects - the partial WHERE (5% of rows) and the
narrower key (one column vs two). Both are legitimate reasons to prefer the partial index for a
single hot access path; if you need multiple statuses, the full index earns its size.

**Backing:** `explain-after.txt` (partial index used for `status='pending'`),
`explains/partial-skip-paid-*.txt` (partial skipped for `status='paid'`).
