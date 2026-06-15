# db-performance-benchmarks

Reproducible PostgreSQL performance benchmarks with real, re-runnable numbers — clone the repo, run one command, get the same charts.

## Honest-metrics policy

Every reported number traces to a committed `EXPLAIN (ANALYZE, BUFFERS)` and a results file. No cherry-picked runs, no invented data, no hidden caveats. Null results and "this common belief is wrong on modern PostgreSQL" findings are reported as-is. If a measured effect is smaller than expected, the number stands and the writeup says so.

## Suites

| Folder | Topic | Status |
| --- | --- | --- |
| `postgres-index/` | PostgreSQL indexing: 12 scenarios, one per common claim | available |

## How to run

Each suite folder has its own `docker-compose.yml`, `run-all.sh`, and `METHODOLOGY.md`. PostgreSQL version, hardware, config, and run count are recorded per suite. See `postgres-index/README.md` to start.
