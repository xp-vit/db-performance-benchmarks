# Methodology

What a skeptic should read first. Every published number in this campaign is produced by
the harness described here and is backed by a committed `results.json` plus an
`EXPLAIN (ANALYZE, BUFFERS)` capture under `scenarios/NN-*/`.

## Database

- **PostgreSQL 18.4** (Debian build `18.4-1.pgdg13+1`), official image
  `postgres:18.4`, pinned by digest:
  `sha256:29ee7bb30d804447dc9a91fd0d74322ae1dc3a4072cc6346f70a5ed6e783b565`
- Run via `docker-compose.yml` in this folder. Locale `C.UTF-8`, encoding `UTF8`.

### Server configuration (held constant across a scenario's before/after)

| setting | value |
| --- | --- |
| shared_buffers | 8GB |
| effective_cache_size | 24GB |
| work_mem | 256MB |
| maintenance_work_mem | 2GB |
| random_page_cost | 1.1 (SSD-realistic) |
| effective_io_concurrency | 200 |
| max_parallel_workers_per_gather | 4 |
| max_wal_size | 16GB |
| wal_compression | off |
| track_io_timing | on |

The only scenarios that change a config knob do so explicitly and say so in their `NOTES.md`.

## Hardware / host

- 32 cores, 93 GiB RAM, local NVMe SSD.
- Linux 6.12 (Manjaro). Single-tenant: nothing else heavy running during the timed runs.
- Date of the recorded run: 2026-06-14.

## Datasets (deterministic seed)

Values are a pure hash of the row id (`hashtextextended`), not `random()`/`setseed()`,
so the dataset is byte-identical regardless of how many parallel workers build it.

- **customers** - id, mixed-case email, citext email, created_at.
- **orders** (the multi-tenant workhorse) - tenant_id (~500 distinct, power-law skew so a
  few tenants dominate; an approximation of Zipf, not exact Zipf), customer_id (FK),
  status (6 values, ~5% `pending`), created_at (correlated with id, correlation ~0.9997),
  amount_cents, payload jsonb, search_text (product-name-like, ~0.3% carry a rare needle).
- **events / events_shuffled** - append-only time series; `events` is physically ordered by
  ts (correlation ~1.0), `events_shuffled` holds the same rows in random order
  (correlation ~0.0) to show BRIN collapse.
- **typesize** - parallel columns (enum / varchar / smallint / bigint / uuid v4 / uuid v7)
  for the index-size comparison.

### Size sweep (decision: full sweep, all 12 scenarios)

Each scenario is measured across a sweep so the "gap grows with N" effects are visible, not
asserted. Tiers:

- orders-backed scenarios and the type-size scenario: **1M, 3M, 10M, 30M** rows.
- BRIN / time-series: **1M, 10M, 100M** rows.
- Scenarios whose natural variable is not table size sweep that variable instead:
  09 sweeps the cascade-delete batch N; 10 sweeps the index count (0,1,2,3,5,8);
  11 sweeps the (indexed?, fillfactor) corners.

`QUICK=1` runs a small-tier dev pass; the published numbers come from the full tiers.

## Timing

- Latency is measured **server-side** by `bench_time()` (in `sql/90-bench-harness.sql`):
  each query is executed inside the server with `clock_timestamp()` deltas, so the reported
  milliseconds are pure execution + planning and exclude client / docker round-trip.
- **Warm cache:** 3 warmup executions before timing (the default). Each timed query is
  re-planned per execution (no prepared statement), matching an ordinary ad-hoc query.
- **N = 12 timed runs** per query; we report **p50 and p95** (and min). Never a single run.
- **Buffers and plan shape** (Seq Scan / Sort / Index Only Scan / Heap Fetches) come from a
  committed `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`. The first `Buffers:` line (root node) is
  the cumulative total for the plan.
- A `cold_restart()` helper (container restart, clearing shared_buffers) is available for
  cold-cache checks; the headline numbers are warm and labelled as such.

## Honest-metrics rules applied here

- Null and less-dramatic-than-expected results are reported as-is in each scenario's `NOTES.md`.
- Tables are `ANALYZE`d before measuring unless the scenario is about stale statistics.
- Scenarios that mutate shared tables re-seed a clean dataset afterwards so later scenarios
  are not contaminated; each scenario drops leftover indexes before measuring.
- Reproduce everything from a clean clone with `./run-all.sh`.
