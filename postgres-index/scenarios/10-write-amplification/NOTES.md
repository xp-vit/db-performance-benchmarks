# 10 - Write amplification: insert throughput vs number of indexes

**Hypothesis:** each added index drops insert throughput roughly linearly and multiplies WAL;
~5 indexes ~ 2.5x the write cost of the unindexed table.

**Measured (bulk insert of 1M rows):**

| indexes | rows/sec | WAL generated |
| --- | --- | --- |
| 0 | 490,292 | 146 MB |
| 1 | 284,917 | 218 MB |
| 2 | 206,054 | 291 MB |
| 3 | 188,374 | 355 MB |
| 5 | 103,546 | 555 MB |
| 8 | 61,955 | 793 MB |

**Finding (more dramatic than the common claim):** held, and the tax is steeper than "5 indexes
~ 2.5x." At 5 indexes throughput is 490k to 104k rows/sec = **4.7x slower**, and WAL is 3.8x; at
8 indexes it is **7.9x slower** with 5.4x the WAL. The first index alone costs the most in
relative terms (1.7x slowdown). The "indexes are not free" point is understated by the common
"~2.5x at 5 indexes" rule of thumb; the measurement is ~4-5x at 5 indexes.

**Caveat:** absolute rows/sec depends on the box and on these being unlogged-free, fsync-normal
bulk inserts; the *ratios* are the portable result. WAL is measured via `pg_wal_lsn_diff`.

**Charts:** `10-write-amplification.svg` (rows/sec vs index count) and `10-write-amp-wal.svg`
(WAL vs index count).
