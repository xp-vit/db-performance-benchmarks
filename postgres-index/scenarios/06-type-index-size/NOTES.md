# 06 - Column type decides index size

**Hypothesis:** index size differs by column type; `bigint` (8B) vs `uuid` (16B) makes every
secondary index ~2x bigger; very short `varchar` rounds to the same slot as `enum`; v4 vs v7
uuid differ on insert locality.

**Measured (30M-row table, one index per column):**

| column | type | index size |
| --- | --- | --- |
| status_smallint | smallint 2B | 207.9 MB |
| status_enum | enum 4B | 207.9 MB |
| status_vc_short | varchar (short labels) | 208.5 MB |
| status_vc_long | varchar (long labels) | 217.0 MB |
| key_bigint | bigint 8B | 673.9 MB |
| key_uuid4 | uuid 16B | 946.3 MB |
| key_uuid7 | uuid 16B | 946.3 MB |

uuid insert-locality (2M rows): bigint 1,170 ms / uuid v7 2,951 ms / uuid v4 5,234 ms;
PK index after load: bigint 45 MB / v7 63 MB / v4 80 MB.

**Findings (two honest nuances):**

1. **The status-column differences are about cardinality (B-tree deduplication), not type
   width.** smallint, enum and short varchar all land at ~208 MB - identical, exactly the
   "short labels round to the same 16-byte slot" point. Long varchar is only ~4% bigger. The
   big number on these columns (208 MB) versus bigint (674 MB) is because status has 6 distinct
   values and dedup crushes it, while bigint is unique. So "enum beats varchar on size" is true
   but tiny for short labels; the real lever is cardinality.

2. **uuid vs bigint is ~1.4x at the index level, not 2x.** Raw key width is 2x (16B vs 8B) but
   per-tuple B-tree overhead dilutes it: 946 MB vs 674 MB = 1.40x. Still the single biggest
   type-driven cost because keys are indexed everywhere. State it as "~40% bigger per
   index," not "double."

3. **uuid v4 is the real penalty.** Random v4 inserts are 4.5x slower than bigint and 1.8x
   slower than time-ordered v7, and leave a 26% larger PK index (page-split bloat). v7 ~ bigint
   locality. If you must use uuid, use v7.

**Chart:** index size by type (bar), 30M rows.
