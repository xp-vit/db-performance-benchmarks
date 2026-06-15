# 04 - GIN on jsonb vs sequential scan

**Hypothesis:** `payload @> '{...}'` containment is N times faster with `GIN (jsonb_path_ops)`
than a seq scan; `jsonb_path_ops` is smaller than `jsonb_ops` (cannot serve key-exists `?`).

**Measured (p50, warm) - two predicates of different selectivity:**

| rows | moderate (~0.83%) seq / GIN / speedup | rare (~0.02%) seq / GIN / speedup |
| --- | --- | --- |
| 1M | 45.7 / 18.3 ms / 2.5x | 44.1 / 0.098 ms / **450x** |
| 3M | 101 / 55.3 ms / 1.8x | 99.7 / 0.289 ms / **345x** |
| 10M | 327 / 189 ms / 1.7x | 305 / 1.06 ms / **288x** |
| 30M | 903 / 589 ms / 1.5x | 876 / 2.81 ms / **312x** |

**Finding - the GIN win is entirely selectivity-driven, and that is the story:**

- For a **rare** predicate (the `sku = 'RARE-NEEDLE'` value, ~0.02% of rows) GIN is
  **~300-450x faster** - 876 ms to 2.8 ms at 30M. This is the dramatic, honest number.
- For a **moderately selective** predicate (~0.83%, the category+region+priority combo) GIN is
  only **~1.5-2.5x** faster and the edge *shrinks* with scale, because the bitmap heap recheck
  touches a growing absolute number of rows and the seq scan runs in parallel warm.

So "GIN is N times faster" is true only when the predicate is selective. Use the rare-value
example for a headline number (reproducible here), or state the selectivity next to a moderate
number - do not imply orders of magnitude for a ~1% filter.

`jsonb_path_ops` is consistently ~48% smaller than `jsonb_ops`; use it unless you need `?`.

**Backing:** `explain-before.txt` / `explain-after.txt` are the rare-predicate seq vs GIN plans;
per-predicate per-size plans in `explains/`. Chart: `04-gin-jsonb.svg` (rare predicate, log
scale; note line carries the moderate-predicate contrast).
