# 09 - Unindexed foreign key -> quadratic cascade delete

**Hypothesis:** `child.parent_id` referencing `parent(id)` is NOT auto-indexed; deleting N
parents with `ON DELETE CASCADE` does N seq scans of the child (quadratic); the FK index makes
it flat.

**Measured (cascade-delete time):**

| child rows | N parents | no FK index | FK indexed |
| --- | --- | --- | --- |
| 100k | 100 | 442 ms | 124 ms |
| 100k | 1,000 | 2,907 ms | 131 ms |
| 100k | 5,000 | 9,868 ms | 176 ms |
| 500k | 100 | 2,099 ms | 119 ms |
| 500k | 1,000 | 18,111 ms | 127 ms |
| 500k | 5,000 | **77,153 ms** | 183 ms |
| 500k | 20,000 | (skipped, > 5e9 row cap) | 386 ms |

**Finding:** held emphatically - this is the cleanest war-story chart in the suite. Without the
FK index, delete time grows roughly linearly in N *and* in child size (the product is the
quadratic): deleting 5,000 parents from a 500k-row child takes 77 seconds. With one index on
`child(parent_id)` the same delete is 183 ms - ~420x faster - and stays flat as N grows. PG
does not create this index for you.

**Honest note (no silent truncation):** the worst no-index point (20k deletes / 500k child)
was deliberately skipped because it would scan > 5e9 child rows (minutes); the indexed run at
that point is 386 ms, so the divergence is already unambiguous. The chart's no-index curve is
log-scale.

**Backing:** `explain-before.txt` (cascade delete, no FK index: per-parent Seq Scan of child),
`explain-after.txt` (FK indexed: Index Scan).
