# Results summary

PostgreSQL 18.4 (`postgres:18.4@sha256:29ee7bb3...e783b565`), 32c / 93Gi box, warm cache,
p50 of 12 server-side runs. Full method in `METHODOLOGY.md`; every number traces to a
`results.json` + committed `EXPLAIN` under `scenarios/NN-*/`. Headline figures use the largest
tier in each sweep.

| # | Hypothesis | Measured (headline) | Held? |
| --- | --- | --- | --- |
| 01 | Right composite order serves the query with no Sort; wrong order forces Sort, orders of magnitude slower | Right vs **no index**: 447 ms &#8594; 0.033 ms at 30M (~13,000x). Wrong order: only ~2x slower, **no Sort** | **Partly.** Right order confirmed; "wrong order forces a Sort / is useless" is FALSE on PG18 (in-index filter keeps it ordered) |
| 02 | INCLUDE turns Index Scan + heap into Index Only Scan; buffers ~100 &#8594; single digits | Buffers 227,109 &#8594; 89 at 30M (~2,500x); `Heap Fetches: 0` | **Yes**, bigger than stated |
| 03 | Heap Fetches reappear after mass UPDATE until re-VACUUM | 0 &#8594; 553,092 &#8594; 0; p50 13.5 &#8594; 56 &#8594; 16 ms | **Yes** |
| 04 | jsonb `@>` is N times faster with GIN than seq scan | **Selectivity-driven:** rare predicate (~0.02%) **312x** at 30M (876 &#8594; 2.8 ms); moderate (~0.83%) only ~1.5x | **Yes, with a caveat.** True N-times for a selective predicate; ~1.5x for ~1%. Use the rare-value example |
| 05 | BRIN ~1000x smaller than B-tree, competitive on range scans; collapses when shuffled | Size **10,546x** smaller at 100M (208 KB vs 2.2 GB); BRIN ~25x faster than seq but ~1.5x **slower** than B-tree; shuffled = planner drops BRIN | **Size: yes (understated).** "Competitive-to-faster than B-tree": no - win is size, not speed. Collapse: yes |
| 06 | enum vs varchar vs bigint vs uuid change index size; uuid ~2x bigint | smallint=enum=short-varchar (208 MB, dedup); uuid 946 MB vs bigint 674 MB = **1.4x**; uuid v4 inserts 4.5x slower than bigint | **Partly.** Short-label rounding yes; uuid is ~1.4x not 2x; status size is cardinality/dedup not type width |
| 07 | function-wrap and implicit-cast defeat the index, 100-1000x slower | Seq Scan both; lower(email) 144 ms &#8594; 0.012 ms; numeric cast 582 ms &#8594; 0.012 ms | **Yes**, larger than stated |
| 08 | `LIKE '%term%'` seq-scans; trigram GIN drops it to ms | 510 ms &#8594; 93 ms at 30M (5x), 19x at 1M; index 537 MB | **Yes (qualitatively).** Warm speedup 5-19x, shrinks with scale; "tens of sec &#8594; few ms" is a cold figure |
| 09 | Unindexed FK cascade delete is O(n^2); index makes it flat | 5,000 deletes / 500k child: 77,153 ms vs 183 ms (~420x); indexed stays flat | **Yes** (cleanest war story) |
| 10 | Each index drops insert throughput ~linearly; 5 indexes ~ 2.5x write cost | 5 indexes = 4.7x slower (104k vs 490k rows/s); 8 indexes = 7.9x; WAL 146 &#8594; 793 MB | **Yes, steeper than stated** (~4-5x at 5, not 2.5x) |
| 11 | Indexing a hot column drops HOT ~95% &#8594; ~0; fillfactor 70 partially restores | Indexed = 0% HOT at **both** fillfactors; no-index ff70 = 97.6%, ff100 = 5.5% | **Partly.** Index kills HOT at any fillfactor; fillfactor only helps when column is NOT indexed. Reword draft |
| 12 | Partial index is a fraction of full size and as fast; planner skips it on predicate mismatch | 33x smaller (988 MB vs 30 MB) at 30M; equal latency; used on match, skipped on mismatch | **Yes** |
| 13 | Phone stored as bigint, `phone LIKE 'p%'` ignores the index (real war story); text fixes it | 30M warm: bigint+cast 453 ms (Seq Scan), text plain non-C 287 ms (Seq Scan), text_pattern_ops 0.08 ms (~5,600x) | **Yes, two-step.** Fix is text AND `text_pattern_ops` (or C collation), not text alone; warm/parallel makes A sub-second vs the team's cold tens-of-seconds |

## What surprised (most valuable for the post)

- **04 GIN on jsonb is selectivity-driven:** ~312x for a rare needle (~0.02%) but only ~1.5x
  for a ~1% predicate vs a warm parallel seq scan. Both are measured here; pick the rare-value
  example for the headline and the conclusion is honest.
- **05 BRIN is slower than a B-tree** on the range scan - its entire case is being 10,000x
  smaller, not faster. Reframe from "competitive-to-faster" to "almost as fast at a tiny
  fraction of the size."
- **01 wrong column order is not catastrophic on PG18** - it still scans the index in sort
  order and filters from within it. The war-story gap is right-index vs *no* index, not
  right-vs-wrong order.
- **11 fillfactor does not rescue HOT on an indexed column** - the draft conflates two
  independent levers; correct it to avoid stating something false.
- **06 the status-column size story is deduplication/cardinality, not enum-vs-varchar**, and
  uuid is ~40% bigger than bigint per index, not double.

## Less dramatic than the draft implies (must fix copy to stay honest)

- 05 (BRIN "competitive-to-faster than B-tree"), 08 ("tens of seconds to a few ms" is cold,
  warm is 510 ms &#8594; 93 ms), 06 ("uuid ~2x bigint").
- 04 (GIN) only when the predicate is ~1% selective; it is fully dramatic (~312x) for a rare
  predicate, so the post is honest if it uses the rare-value example.

## More dramatic than the draft implies (can strengthen copy)

- 01 (right vs no index ~13,000x), 02 (~2,500x fewer buffers), 05 size (10,000x), 07
  (~10,000x), 09 (~420x), 10 (~5x at 5 indexes, not 2.5x).

## Post-ready charts

All 14 SVGs in `charts/` regenerate from `results.json` via `charts/gen.py`. Strongest:
`05-brin-size.svg`, `09-unindexed-fk.svg`, `01-composite-order.svg`, `08-trigram-like.svg`,
`02-covering-include.svg`, `10-write-amplification.svg`, `11-hot-update.svg`.
