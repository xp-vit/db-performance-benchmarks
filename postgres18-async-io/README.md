# postgres18-async-io

Does PostgreSQL 18's asynchronous I/O actually make your workload faster? This suite measures
`io_method = sync | worker | io_uring` on realistic operations, cold and warm, on one disclosed
NVMe rig — and produces a decision guide for **when async I/O wins and when it doesn't**.

Every number is our own measurement (see `METHODOLOGY.md` and `results/rig.json`). No borrowed
figures.

## Quick start

```bash
cd postgres18-async-io
./load.sh                       # bring up PG18 + resumable 30M-row load (~2 min, ~8 GB)
./bench/run-warm.sh             # warm sweep — no root needed
sudo -v && ./bench/run-cold.sh  # cold sweep — needs root to drop the OS page cache
python3 aggregate.py            # build results/RESULTS.md (tables + decision matrix)
```

`load.sh` and the load are **resumable** — re-run after any interruption and it continues from
the last committed batch.

## What is measured

| Workload | Why | Async expected to help? |
| --- | --- | --- |
| Cold sequential scan | streaming read of the whole heap | yes |
| Cold bitmap heap scan | scattered ~5% reads (the `effective_io_concurrency` case) | yes, most |
| Cold VACUUM (post-update) | maintenance read path (`maintenance_io_concurrency`) | maybe |
| Cold REINDEX | full-heap read to rebuild an index | maybe |
| Warm OLTP point-lookup | cache-served single-row reads | no (the honest boundary) |

Swept: `io_method`, `effective_io_concurrency` (1/16/64), `maintenance_io_concurrency`,
`io_workers`. Cold = shared_buffers flushed + OS page cache dropped before each run.

## Layout

```
docker-compose.yml   PG18.4, seccomp=unconfined (needed for io_uring), tuned + pinned by digest
config/settings.sh   dataset size, io_method / eic / io_workers sweeps, run counts
sql/                 schema + deterministic resumable seed
load.sh              resumable loader
lib/bench.sh         helpers: io_method swap, cold-cache drop, pg_stat_io accounting, timing
bench/run-warm.sh    warm sweep (no root)
bench/run-cold.sh    cold sweep (drops caches; needs root)
aggregate.py         raw/*.jsonl -> results/RESULTS.md
results/             rig.json, raw/*.jsonl, RESULTS.md
```

## Important caveats

- **io_uring needs `seccomp=unconfined`** under Docker (default profile blocks the syscalls).
  Production should allowlist io_uring in a custom seccomp profile instead. See `METHODOLOGY.md`.
- Async I/O gains are **storage-specific** — measured on a Samsung 990 PRO / ext4 / kernel 6.12.
- `results/raw/*.jsonl` and `results/RESULTS.md` are generated; regenerate from a clean clone.
