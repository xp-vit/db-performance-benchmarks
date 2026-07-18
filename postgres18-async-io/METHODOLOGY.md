# Methodology — Postgres 18 async I/O benchmark

Every number in `results/RESULTS.md` is our own measurement on the single rig below.
No figures are borrowed from other blogs or PostgreSQL marketing. Where a claim rests
on too few runs or noisy data, the aggregator flags it "second run needed".

## Rig (disclosed in full)

| | |
| --- | --- |
| CPU | AMD Ryzen 9 7950X3D (16 cores / 32 threads) |
| RAM | 93 GiB |
| Disk (PGDATA) | Samsung SSD 990 PRO 1TB NVMe |
| Filesystem | ext4 |
| Kernel | 6.12.94-1-MANJARO |
| PostgreSQL | 18.4 (official Docker image, Debian build, compiled with liburing) |
| Container | Docker 29.x, `security_opt: seccomp=unconfined` |

Async I/O gains are storage-dependent — these numbers are specific to this NVMe + ext4 +
kernel. On a slower disk the cold-read wins get larger; on a faster one, smaller.

## The variable under test

`io_method` (PG18, `PGC_POSTMASTER` — changed via `ALTER SYSTEM` + container restart):

- `sync` — the pre-18 behavior: each read issued and waited on synchronously.
- `worker` — PG18 default: a pool of `io_workers` (default 3) issues reads asynchronously.
- `io_uring` — reads submitted through the Linux io_uring interface from the backend itself.

Swept alongside it:
- `effective_io_concurrency` (scans; `PGC_USERSET`, per session): 1, 16, 64.
- `maintenance_io_concurrency` (VACUUM / REINDEX; PG18 routes maintenance reads through this): 16 (default headline; `MIC_COLD="1 16 64"` to expand).
- `io_workers` (worker method only; `SWEEP_WORKERS=1`): 3, 6, 12.

Everything else is fixed and identical across arms: `shared_buffers=4GB` (deliberately
smaller than the 6.2 GB heap so a cold scan must read from storage),
`maintenance_work_mem=2GB`, `max_wal_size=16GB`, `track_io_timing=on`.

## io_uring under Docker — a real caveat

The default Docker seccomp profile blocks `io_uring_setup`/`io_uring_enter`, so
`io_method=io_uring` fails with `could not setup io_uring queue: Operation not permitted`.
We run the container with `seccomp=unconfined` to enable it. In production you would ship a
custom seccomp profile that allowlists the io_uring syscalls rather than disabling seccomp.
`sync` and `worker` need no special privileges.

## Cold vs warm

- **Cold** (where async I/O is expected to help): before each measured run we `CHECKPOINT`,
  stop the container (flushing PostgreSQL's `shared_buffers`), `sync`, drop the OS page cache
  (`echo 3 > /proc/sys/vm/drop_caches`, needs root), restart, then run the operation once.
- **Warm** (the honest boundary): data served from cache; no dropping. Async I/O should be flat.

## Workloads

1. **Cold sequential scan** — `SELECT count(*), sum, avg` over 30M rows, single process
   (`max_parallel_workers_per_gather=0`) so async prefetch is the isolated variable.
2. **Cold bitmap heap scan** — a ~5% predicate whose matches are scattered across the heap
   (`event_type IN (2,5) AND status = 3`), the classic `effective_io_concurrency` case.
3. **Cold VACUUM** — after a fresh ~5% scattered UPDATE (dead tuples to reclaim).
4. **Cold REINDEX** — rebuild `events_tenant_ts` (reads the whole heap).
5. **Warm OLTP point-lookup** — pgbench PK lookups; the workload where async I/O should NOT help.

## Measurement

- Query ops: server-side `Execution Time` from `EXPLAIN (ANALYZE, BUFFERS, TIMING)`.
- Maintenance ops: wall time around the statement.
- I/O volume: `pg_stat_io` reads (× 8 KB) captured per operation via `pg_stat_reset_shared('io')`.
- OLTP: pgbench TPS, 8 clients, 20 s.
- Runs: warm ×5, cold ×3 per config (median reported; `aggregate.py` flags n<3 or CV>20%).

## Reproduce

```bash
cd postgres18-async-io
./load.sh                      # resumable 30M-row load (~2 min)
./bench/run-warm.sh            # warm sweep (no root)
sudo -v && ./bench/run-cold.sh # cold sweep (needs root for drop_caches)
python3 aggregate.py           # raw/*.jsonl -> results/RESULTS.md
```
