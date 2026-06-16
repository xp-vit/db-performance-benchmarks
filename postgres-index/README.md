# postgres-index

Reproducible PostgreSQL 18 benchmarks for common indexing decisions.
Twelve scenarios, one per claim. Clone, run one command, get the same numbers.

## What this suite proves

Each scenario isolates one indexing decision and measures it across a data-size sweep, with
the query plan committed next to the number. Several findings come out *less* dramatic than
folklore suggests; the number stands and the writeup says so. Highlights:

| # | Scenario | What it shows |
| --- | --- | --- |
| 01 | Composite column order | right vs wrong vs no index for a tenant+status+sort query |
| 02 | Covering index (INCLUDE) | Index Only Scan cuts buffers ~100 &#8594; single digits |
| 03 | Covering caveat (visibility map) | Heap Fetches reappear after a mass UPDATE until VACUUM |
| 04 | GIN on jsonb | `@>` containment: seq scan vs GIN |
| 05 | BRIN on time series | ~1000x smaller than B-tree; collapses on shuffled data |
| 06 | Column type &#8594; index size | enum vs varchar vs smallint vs bigint vs uuid |
| 07 | "Index ignored" | function-wrapped column and implicit cast defeat the index |
| 08 | Leading-wildcard LIKE | `%term%` seq scan vs trigram GIN |
| 09 | Unindexed foreign key | cascade delete goes quadratic without the FK index |
| 10 | Write amplification | inserts/sec and WAL vs number of indexes |
| 11 | HOT update | indexing a hot column kills HOT; fillfactor only helps when it is not indexed |
| 12 | Partial index | hot-slice index is a fraction of full size and as fast |
| 13 | Prefix search vs column type | `LIKE 'p%'` on a bigint cast and a non-C plain index both seq-scan; `text_pattern_ops` serves it |

## How to run

```bash
cd postgres-index
./run-all.sh            # full size sweep (1M..30M orders, 1M..100M events)
QUICK=1 ./run-all.sh    # fast dev pass on small tiers
```

`run-all.sh` brings up the pinned PostgreSQL 18.4 container, installs the schema + seed +
timing harness, runs all 13 scenarios across the sweep, and regenerates every chart.

To run one scenario:

```bash
bash scenarios/01-composite-order/run.sh
```

## Layout

```
docker-compose.yml      pinned PG18.4, tuned for the box (see METHODOLOGY.md)
sql/                    schema, deterministic seed, server-side timing harness
lib/bench.sh            shared runner helpers
config/sizes.sh         the size sweep tiers
scenarios/NN-*/         setup.sql, query.sql, run.sh, NOTES.md (results.json + explain-*.txt generated on run)
charts/gen.py           regenerates brand-palette SVG charts from results.json
METHODOLOGY.md          hardware, version+digest, config, timing, honest-metrics rules
```

## Honest metrics

Every chart value traces to a committed `EXPLAIN (ANALYZE, BUFFERS)` and a `results.json`.
No cherry-picked runs, no invented data. Where a measured effect is smaller than the common
claim, the number stands and the writeup says so. See the repo-root README for the policy.
