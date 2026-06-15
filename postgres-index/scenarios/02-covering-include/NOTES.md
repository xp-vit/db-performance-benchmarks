# 02 - Covering index (INCLUDE) -> index-only scan

**Hypothesis:** adding `INCLUDE (amount_cents)` turns an Index Scan + heap fetch into an
Index Only Scan, cutting shared buffers ~100 to single digits and latency 30-50%.

**Measured (buffers touched, warm):**

| rows | plain (Index Scan + heap) | INCLUDE (Index Only Scan) |
| --- | --- | --- |
| 1M | 7,636 | 4 |
| 10M | 75,687 | 12 |
| 30M | 227,109 | 89 |

`Index Only Scan` with `Heap Fetches: 0` confirmed in every INCLUDE run.

**Finding:** held, and the I/O story is even bigger than "~100 to single digits": at 30M the
covering index drops buffers touched by ~2,500x (227k to 89). The query sums `amount_cents`
over a tenant+status slice; the plain index must visit the heap for every matching row, the
covering index answers entirely from the index leaf.

**Caveat:** the INCLUDE index is larger on disk (it carries `amount_cents` in every leaf),
and the heap-free property depends on the visibility map staying current - see scenario 03.

**Chart:** buffers before/after (the buffer reduction reads better than the latency here, since
both are sub-millisecond warm).
