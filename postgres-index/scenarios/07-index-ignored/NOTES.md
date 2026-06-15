# 07 - "I added an index and nothing changed"

**Hypothesis:** `WHERE lower(email)=$1` ignores a plain `email` index (needs an expression
index); `WHERE bigint_col = '42'::numeric` (implicit cast) forces a seq scan + per-row cast,
100-1000x slower than the correctly-typed predicate.

**Measured (30M rows, p50, warm):**

| sub-case | index ignored | correct index | speedup |
| --- | --- | --- | --- |
| (a) `lower(email)` | 144 ms (Seq Scan) | 0.012 ms (expression index) | ~12,000x |
| (b) `id = '42'::numeric` | 582 ms (Seq Scan) | 0.012 ms (typed `id = 42`) | ~48,000x |

**Finding:** held emphatically, and bigger than the common "100-1000x" claim. Both wrong forms
produce a full Seq Scan (`a_plain_seqscan=true`, `b_cast_seqscan=true`); the fix in each case
is sub-millisecond. (a) A plain `email` index cannot serve `lower(email)`; an expression index
on `lower(email)` makes it instant. (b) Comparing a `bigint` PK to a `numeric` literal forces
the comparison into numeric and throws the index away; passing the literal as the column's type
restores the PK index.

**Caveat:** the multiplier is this large partly because the fixed query hits a single row, so
the "correct" side is a point lookup. The durable point is qualitative: wrong form = Seq Scan,
right form = index. Numbers are warm; cold seq scans would be larger still.

**Backing:** `explain-before.txt` (lower(email) Seq Scan), `explain-after.txt` (expression
index used).
