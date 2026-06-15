# 05 - BRIN on time series: size, range scan, and the collapse

**Hypothesis:** on time-ordered `events`, a BRIN index on `ts` is ~1000x smaller than the
B-tree and competitive-to-faster on wide range scans; on `events_shuffled` (same data, random
order) the BRIN range scan collapses toward seq-scan time.

**Measured:**

| rows | BRIN size | B-tree size | ratio | seq scan | BRIN ordered | B-tree ordered | BRIN shuffled |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1M | 24 KB | 21 MB | 915x | 21.2 ms | 1.8 ms | 0.4 ms | 22.1 ms |
| 10M | 32 KB | 214 MB | 6,856x | 99 ms | 4.9 ms | 3.5 ms | 110 ms |
| 100M | 208 KB | **2.2 GB** | **10,546x** | 726 ms | 29 ms | 19.8 ms | 818 ms |

**Finding:** the size story is enormous and *under*-stated by "~1000x": at 100M rows BRIN is
208 KB versus a 2.2 GB B-tree, a 10,000x difference. On the ordered range scan BRIN is ~25x
faster than a seq scan (726 ms to 29 ms at 100M).

**Honest correction to the hypothesis:** BRIN is **not** "competitive-to-faster than the
B-tree" on this range scan - the B-tree is consistently ~1.5x faster (19.8 ms vs 29 ms at
100M). BRIN's win is *size*, not speed: it gives ~96% of the B-tree's range-scan benefit at
1/10,000th of the size. That is the honest framing - choose BRIN to save gigabytes, not to win
a latency race.

**Collapse confirmed:** on `events_shuffled` (correlation ~0) the planner abandons BRIN
entirely (`brin_used_shuffled=false`) and the query runs as a seq scan, slightly *slower* than
the plain seq scan due to overhead (818 ms vs 726 ms at 100M). BRIN is useless without physical
correlation.

**Charts:** `05-brin-size.svg` (the dramatic size bar) and `05-brin-latency.svg`
(seq vs BRIN-ordered vs BRIN-shuffled).
