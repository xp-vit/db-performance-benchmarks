# 03 - Covering caveat: visibility map / Heap Fetches

**Hypothesis:** the same index-only scan shows `Heap Fetches: 0` right after VACUUM, but after
a mass UPDATE the visibility map goes stale, `Heap Fetches: N>0` appears and latency rises,
until re-VACUUM restores it.

**Measured (30M rows, warm):**

| state | Heap Fetches | p50 |
| --- | --- | --- |
| post-VACUUM | 0 | 13.5 ms |
| post mass-UPDATE | 553,092 | 56.1 ms |
| post re-VACUUM | 0 | 15.9 ms |

**Finding:** held cleanly. A mass UPDATE of the queried tenant clears the visibility-map
all-visible bits on those pages, so the "index only" scan silently starts visiting the heap to
check row visibility (553k heap fetches at 30M), and latency rises ~4x. A follow-up VACUUM
rebuilds the map and the scan is heap-free again. This is the concrete counter to
"a covering index never touches the heap."

**Caveat:** the latency multiplier depends on how much of the queried slice was updated and on
cache state; the durable, cache-independent signal is the Heap Fetches count, which is what the
chart shows.

**Backing:** `explain-before.txt` (post-VACUUM, Heap Fetches 0), `explain-after.txt`
(post-UPDATE, Heap Fetches > 0).
