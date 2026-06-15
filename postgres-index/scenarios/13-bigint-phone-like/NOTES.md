# 13 - Prefix phone search: column type defeats the index

**Origin:** real engagement. An operations tool searched customers by the first digits of a phone number (`phone LIKE '1234566%'`) and took ~30s per lookup. Phone was stored as `bigint`. Switching the column to text dropped it to ~100ms.

**Hypothesis held: yes, with the nuance that the fix is two steps, not one.**

Three variants on a dedicated `phones13` table (11-digit phones, deterministic multiplicative-hash seed), prefix `150000%`, warm cache, p50 of 12 runs:

| size | A bigint + cast | B text, plain (non-C) | C text, text_pattern_ops | matches |
| --- | --- | --- | --- | --- |
| 1M  | 29.2 ms  | 22.4 ms  | 0.021 ms | 10  |
| 3M  | 60.9 ms  | 45.0 ms  | 0.043 ms | 30  |
| 10M | 162.8 ms | 106.6 ms | 0.048 ms | 100 |
| 30M | 452.5 ms | 287.1 ms | 0.080 ms | 299 |

Plans (committed): A and B are both Parallel Seq Scans; C is an Index Only Scan on `p13_vc_pat`. A->C at 30M is ~5,600x.

**Findings:**
- **bigint kills it twice.** `LIKE` needs text, so `phone_bi::text LIKE 'p%'` casts every row (function-on-column, index unusable), and a numeric B-tree is not ordered by digit-string anyway. Seq Scan.
- **Switching to text is not automatically enough.** Under a non-`C` collation a plain text B-tree still cannot serve `LIKE 'prefix%'` (variant B), so it Seq Scans too, only a bit faster than A because it skips the cast. This is the "we changed it to varchar and it was still slow" trap.
- **`text_pattern_ops` is the real fix** (variant C): collation-independent prefix ordering, so the planner range-scans. Sub-0.1ms.
- **Warm/parallel caveat:** A is "only" ~450ms here because the box runs a 4-worker parallel seq scan on a warm cache. Cold and unparallelized (one connection, cold buffers, a wider real row) is the seconds-to-tens-of-seconds the operations team actually saw. The multiple over C is the honest, version-stable point, not the absolute A number.
- **Box collation:** default is `C.UTF-8`, under which a plain text index *would* already serve LIKE. Variant B forces `en-US-x-icu` collation on the column to reproduce the non-C trap that bites most real databases.

PG 18.4. See `results.json`, `explain-before.txt` (A), `explain-after.txt` (C), and `explains/` for B and every size.
