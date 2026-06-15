# 08 - Leading-wildcard LIKE -> pg_trgm

**Hypothesis:** `search_text LIKE '%term%'` cannot use a B-tree and seq-scans (seconds on 10M);
a `GIN (gin_trgm_ops)` index drops it to milliseconds.

**Measured (p50, warm):**

| rows | seq scan | trigram GIN | speedup | trigram index size |
| --- | --- | --- | --- | --- |
| 1M | 25.6 ms | 1.4 ms | 19x | 19 MB |
| 3M | 62.3 ms | 9.0 ms | 7x | 55 MB |
| 10M | 189 ms | 28.5 ms | 7x | 180 MB |
| 30M | 510 ms | 93 ms | 5x | 537 MB |

**Finding:** held - the trigram GIN turns the un-indexable leading wildcard into an index scan
and is the only one of the search options that works at all. But two honest qualifiers for the
copy:

1. **The speedup shrinks with scale** (19x at 1M down to 5x at 30M), because the needle matches
   a growing absolute number of rows and the bitmap heap recheck cost grows with it.
2. **These are warm numbers.** The common "tens of seconds to a few milliseconds" claim is a
   cold/larger-table figure; warm on this box the seq scan is 510 ms (not tens of seconds) and
   trigram is 93 ms (not a few ms). The qualitative win is solid; label the numbers warm or
   cite a cold run for the dramatic figure.
3. The trigram index is **large** (537 MB at 30M, bigger than many B-trees) - a real cost to
   weigh.

**Chart:** seq vs trigram latency (log).
