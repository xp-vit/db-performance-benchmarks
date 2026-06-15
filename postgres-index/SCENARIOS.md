# postgres-index — Scenario Spec

12 benchmark scenarios, one per common indexing claim. See `METHODOLOGY.md` for methodology, output contract, and chart style.

Each scenario isolates one indexing decision. The bracketed letter is a grouping tag.

## Shared datasets

Build these once; most scenarios reuse them. Fixed seed, recorded row counts.

### `customers` (~1M rows)
`id bigint PK`, `email text`, `email_ci citext` (for the case-insensitive variant), `created_at timestamptz`.

### `orders` (~10M rows) — the multi-tenant workhorse
```
id           bigint PK
tenant_id    bigint        -- ~500 distinct, skewed (Zipfian): a few big tenants
customer_id  bigint        -- FK -> customers(id)
status       text          -- ~6 values: pending/paid/shipped/cancelled/refunded/closed; ~5% pending
created_at   timestamptz   -- spread over 3 years, correlated with id (append order)
amount_cents bigint
payload      jsonb         -- realistic doc with a few indexed-worthy keys
search_text  text          -- product-name-like free text for trigram search
```
Skew matters: status is low-cardinality (drives partial-index, low-selectivity, dedup), tenant_id is the lead composite column, created_at is the range/sort column.

### `events` (~100M rows) — append-only time series for BRIN
`id bigint`, `ts timestamptz` (monotonic, high correlation), `device_id int`, `value double precision`. Also keep a **shuffled copy** (`events_shuffled`) with the same rows in random physical order to show BRIN collapse.

### type-size tables (scenario 6 only)
Small set of single-column tables / parallel columns on a 10M-row table to compare index size by type: `enum` vs `varchar` status; `uuid` (v4) vs `uuid` (v7) vs `bigint` key.

---

## Scenarios

### 01 — Composite column order (the war-story chart)  [B]
**Topic:** Composite column order. **Hypothesis:** for `WHERE tenant_id=$1 AND status=$2 ORDER BY created_at DESC LIMIT 20`, the index `(tenant_id, status, created_at DESC)` serves it with no Sort and reads ~20 rows; the wrong order `(created_at, tenant_id, status)` forces a scan + Sort and is orders of magnitude slower.
**Measure:** p50/p95 latency both index orders; row/buffer counts; presence of Sort node. **Chart:** two-bar latency (right vs wrong order), log scale if needed. The headline "seconds to tens of ms" contrast.

### 02 — Covering index / INCLUDE → index-only scan  [C]
**Topic:** Covering indexes. **Hypothesis:** adding `INCLUDE (amount_cents, status)` to a hot lookup turns an Index Scan + heap fetch into an Index Only Scan, cutting shared buffers ~100→single digits and latency 30-50%.
**Measure:** buffers (shared hit/read) before/after; latency p50/p95; confirm `Index Only Scan` + `Heap Fetches: 0`. **Chart:** buffers before/after (the I/O story reads better than the time here).

### 03 — Covering caveat: visibility map / Heap Fetches  [C]
**Topic:** Covering indexes (the caveat paragraph). **Hypothesis:** the same index-only scan shows `Heap Fetches: 0` right after VACUUM, but after a mass UPDATE the visibility map goes stale and `Heap Fetches: N>0` appears and latency rises, until re-VACUUM restores it.
**Measure:** Heap Fetches + latency at three points: post-VACUUM, post-mass-UPDATE, post-re-VACUUM. **Chart:** Heap Fetches (and latency) across the three states. Counters the "covering index = never touches heap" myth.

### 04 — GIN on jsonb vs seq scan  [A]
**Topic:** B-tree is the default, not the only kind. **Hypothesis:** `payload @> '{"key":"val"}'` containment on 10M rows is N× faster with `GIN (payload jsonb_path_ops)` than a seq scan; note GIN serves no index-only scan.
**Measure:** seq scan vs GIN latency p50/p95; index size; (optional) `jsonb_ops` vs `jsonb_path_ops` size + the key-exists `?` difference. **Chart:** latency seq vs GIN (log scale).

### 05 — BRIN on time-series: size + range scan, and the collapse  [A][L]
**Topic:** B-tree is the default, not the only kind. **Hypothesis:** on 100M time-ordered `events`, a BRIN index on `ts` is ~1000× smaller than the B-tree (KB/MB vs GB) and competitive-to-faster on wide range scans; on `events_shuffled` (same data, random order) the BRIN range scan collapses toward seq-scan time.
**Measure:** index size BRIN vs B-tree; range-scan latency on ordered vs shuffled. **Chart:** two charts — index size (bar, dramatic) and ordered-vs-shuffled latency. The size bar is a strong standalone.

### 06 — Column type decides index size  [D]
**Topic:** The type of the indexed column decides its size. **Hypothesis:** on a 10M-row column, index size differs by type: `bigint` (8B) vs `uuid` (16B) makes every secondary index ~2× bigger; very short `varchar` labels round to the same slot as `enum` (8-byte header + MAXALIGN), so the gap appears only with longer labels. Also v4 vs v7 uuid insert locality.
**Measure:** index size in MB per type; (optional) insert throughput uuid v4 vs v7 vs bigint. **Chart:** index size bar by type. The honest nuance is the point: short labels barely differ; uuid vs bigint is the real gap.

### 07 — "I added an index and nothing changed": function on column + implicit cast  [E]
**Topic:** Why you added an index and nothing got faster. **Hypothesis:** `WHERE lower(email)=$1` ignores a plain `email` index (needs an expression index on `lower(email)`); `WHERE bigint_col = '42'::numeric` (implicit cast) forces a seq scan + per-row cast, 100-1000× slower than the correctly-typed predicate.
**Measure:** latency for (a) plain index unused vs expression index used, (b) casted predicate seq scan vs correctly-typed index scan. **Chart:** before/after latency for both sub-cases (grouped bars).

### 08 — Leading-wildcard LIKE → pg_trgm  [H]
**Topic:** Why you added an index and nothing got faster (wildcard). **Hypothesis:** `search_text LIKE '%term%'` can't use a B-tree and seq-scans (seconds on 10M rows); a `GIN (search_text gin_trgm_ops)` index drops it to milliseconds.
**Measure:** seq scan vs trigram GIN latency p50/p95; index size. **Chart:** latency seq vs trigram (log scale). Strong hero-candidate chart.

### 09 — Unindexed foreign key → O(n²) cascade delete + slow join  [F]
**Topic:** Index your foreign keys. **Hypothesis:** `orders.customer_id` referencing `customers(id)` is NOT auto-indexed; deleting N customers with `ON DELETE CASCADE` does N seq scans of `orders` (quadratic); adding the FK index makes it flat. Joins on the FK also speed up.
**Measure:** cascade-delete time for growing N (e.g. delete 100 / 1k / 10k parents) without vs with the index → show the curve diverge; join latency before/after. **Chart:** delete time vs N (two curves: O(n²) vs flat). The diverging-curve chart is memorable.

### 10 — Write amplification: insert throughput vs number of indexes  [G]
**Topic:** Indexes that hurt. **Hypothesis:** each added index drops insert throughput roughly linearly and multiplies WAL + write I/O; ~5 indexes ≈ ~2.5× the write cost of the unindexed table.
**Measure:** bulk-insert / sustained-insert throughput (rows/sec) at 0,1,2,3,5,8 indexes; WAL bytes generated. **Chart:** inserts/sec vs index count (descending line). The "indexes aren't free" chart.

### 11 — HOT update killed by indexing a hot column  [G]
**Topic:** Indexes that hurt. **Hypothesis:** indexing a frequently-updated column (`updated_at`-style) drops the HOT-update rate from ~95% to near zero, so every update now writes every index; raising fillfactor to 70 partially restores HOT on update-heavy load.
**Measure:** HOT update rate (`pg_stat_user_tables.n_tup_hot_upd / n_tup_upd`) and update latency: (a) no index on hot column, (b) index on hot column, (c) index + fillfactor 70. **Chart:** HOT rate across the three configs (bar). Subtle but high-credibility.

### 12 — Partial index: size + latency vs full index  [I]
**Topic:** Partial indexes. **Hypothesis:** for the common `WHERE status='pending'` access path (~5% of rows), a partial index `WHERE status='pending'` is a fraction of the full-index size and at least as fast; the planner only uses it when the query predicate matches the partial WHERE.
**Measure:** index size partial vs full; query latency; demonstrate the planner skipping the partial index when the predicate doesn't match. **Chart:** index size partial vs full (bar) with latency annotation.

---

## Not in scope

Topics not covered here (skip-scan deep-dive, citext/collation, keyset pagination, COUNT(*), random_page_cost, plan_cache_mode, BRIN pages_per_range tuning) are out of scope for this suite.

## Definition of done

12 scenario folders with data + EXPLAIN + chart, `METHODOLOGY.md`, and `run-all.sh` reproducing everything from a clean clone, with per-scenario `NOTES.md` recording which hypotheses held, which surprised, and any number less dramatic than the common claim.
