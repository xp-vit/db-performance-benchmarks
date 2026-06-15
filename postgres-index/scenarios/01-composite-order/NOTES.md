# 01 - Composite column order

**Hypothesis:** `(tenant_id, status, created_at DESC)` serves
`WHERE tenant_id=? AND status=? ORDER BY created_at DESC LIMIT 20` with no Sort and ~20 rows;
the wrong order `(created_at, tenant_id, status)` forces a scan + Sort and is orders of
magnitude slower.

**Measured (p50, warm, server-side):**

| rows | no index (baseline) | wrong order | right order |
| --- | --- | --- | --- |
| 1M | 21.6 ms | 0.060 ms | 0.031 ms |
| 10M | 154 ms | 0.070 ms | 0.028 ms |
| 30M | **447 ms** | 0.056 ms | **0.033 ms** |

**Finding:** the right index is an Index Scan, no Sort, flat ~0.03 ms at every size. Against
**no index** the gap is the war story: 447 ms &#8594; 0.033 ms at 30M, roughly 13,000x. The
common "3 seconds to tens of milliseconds" figure is if anything conservative for a cold/larger table.

**Honest caveat (hypothesis only partially held):** the *wrong-order* index is **not**
catastrophic on PostgreSQL 18 and does **not** force a Sort. The planner scans
`o01_wrong` backward in `created_at` order and applies `tenant_id`/`status` as in-index
filters (they are columns of the index), so it stays ordered and only ~2x slower than the
right order. The dramatic slowdown comes from having *no usable composite index at all*
(Seq Scan + Sort), not from column order per se. The honest framing is "right index vs the
missing/equivalent-to-missing index": a wrong-order index that still contains the columns is
salvageable on modern PG.

**Backing:** `explain-before.txt` (no index: Seq Scan + Sort), `explain-after.txt` (right
order: Index Scan, no Sort), per-size plans in `explains/`.
