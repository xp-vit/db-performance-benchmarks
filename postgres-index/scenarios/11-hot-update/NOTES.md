# 11 - HOT update killed by indexing a hot column

**Hypothesis (common claim):** indexing a frequently-updated column drops the HOT-update rate
from ~95% to near zero; raising fillfactor to 70 partially restores HOT.

**Measured (50k rows, 10k repeatedly updated, 50 passes = 500k updates):**

| config | HOT rate | update time |
| --- | --- | --- |
| no index on hot column, fillfactor 100 | 5.5% | 4,144 ms |
| no index on hot column, fillfactor 70 | **97.6%** | 3,399 ms |
| index on hot column, fillfactor 100 | 0.0% | 4,374 ms |
| index on hot column, fillfactor 70 | **0.0%** | 4,380 ms |

**Finding - the common claim needs correcting (this is a myth-buster):** HOT depends
on **two independent** conditions, and the four corners separate them:

1. **Indexing the updated column makes HOT impossible, at any fillfactor.** Both indexed runs
   are 0.0% HOT - fillfactor 70 does **not** "partially restore" it (0.0% either way), because
   a changed *indexed* column always needs a new index entry, which is exactly what HOT avoids.
2. **Fillfactor is the lever only when the column is *not* indexed.** With no index on the hot
   column, fillfactor 100 starves HOT (5.5%, no free space) while fillfactor 70 gives it room
   to thrive (97.6%).

So "drop the index OR raise fillfactor" is wrong; they fix different halves. The honest rule:
do not index a column you update on every row; and give update-heavy tables fillfactor headroom
for the columns that are *not* indexed. The common "fillfactor 70 partially restores HOT on
the indexed column" claim is wrong.

**Backing:** `explain-before.txt` (update with no hot index), `explain-after.txt` (update with
hot index). Chart: HOT rate across the four configs.
