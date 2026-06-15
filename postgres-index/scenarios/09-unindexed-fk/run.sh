#!/usr/bin/env bash
# Scenario 09 - unindexed FK cascade delete: O(n^2) vs flat. Sweeps delete-batch N
# at two child-table sizes. Each (variant, N) rebuilds the tables for a clean measurement.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="09-unindexed-fk"
RESULTS="$HERE/results.json"
CHILD_PER_PARENT=20
if [ "${QUICK:-0}" = "1" ]; then
  CHILD_SIZES=( "50k:50000" ); DELETE_NS=( 50 200 1000 )
else
  CHILD_SIZES=( "100k:100000" "500k:500000" ); DELETE_NS=( 100 1000 5000 20000 )
fi

seed_fk() {  # $1 child_rows
  local child="$1" parent=$(( $1 / CHILD_PER_PARENT ))
  q "TRUNCATE p09_child, p09_parent;
     INSERT INTO p09_parent SELECT generate_series(1,$parent);
     INSERT INTO p09_child  SELECT g, 1 + (g % $parent), repeat('x',40)
       FROM generate_series(1,$child) g;" >/dev/null
  echo "$parent"
}

run_one() {
  echo "  [09] child=$CHILD_LABEL rows=$CHILD_ROWS" >&2
  pg < "$HERE/setup.sql" >/dev/null
  for variant in noindex indexed; do
    for N in "${DELETE_NS[@]}"; do
      # bound the quadratic: skip noindex points that would scan > 5e9 child rows
      if [ "$variant" = noindex ] && [ $(( N * CHILD_ROWS )) -gt 5000000000 ]; then
        echo "    noindex N=$N child=$CHILD_ROWS SKIPPED (would scan $(( N * CHILD_ROWS )) rows, > 5e9 cap)" >&2
        continue
      fi
      local parent; parent="$(seed_fk "$CHILD_ROWS")"
      [ "$N" -gt "$parent" ] && continue
      if [ "$variant" = indexed ]; then
        q "CREATE INDEX IF NOT EXISTS p09_child_fk ON p09_child (parent_id);" >/dev/null
      else
        q "DROP INDEX IF EXISTS p09_child_fk;" >/dev/null
      fi
      q "ANALYZE p09_parent; ANALYZE p09_child;" >/dev/null
      # time the cascade delete server-side
      local t0; t0="$(q "SELECT extract(epoch FROM clock_timestamp());")"
      q "DELETE FROM p09_parent WHERE id <= $N;" >/dev/null
      local ms; ms="$(q "SELECT round((extract(epoch FROM clock_timestamp()) - $t0)*1000.0, 2);")"
      local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$CHILD_LABEL" --argjson crows "$CHILD_ROWS" \
        --arg variant "$variant" --argjson n "$N" --argjson ms "$ms" --arg pgv "$(pg_version)" \
        '{scenario:$sc, size_label:$size, child_rows:$crows, variant:$variant,
          delete_n:$n, delete_ms:$ms, pg_version:$pgv}')"
      append_result "$RESULTS" "$obj"
      echo "    $variant N=$N -> ${ms}ms" >&2
    done
  done
  # capture before/after explain of the cascade delete at the largest child size
  seed_fk "$CHILD_ROWS" >/dev/null
  q "DROP INDEX IF EXISTS p09_child_fk;" >/dev/null
  explain_capture "DELETE FROM p09_parent WHERE id <= 100" "$HERE/explain-before.txt"
  seed_fk "$CHILD_ROWS" >/dev/null
  q "CREATE INDEX p09_child_fk ON p09_child (parent_id);" >/dev/null
  explain_capture "DELETE FROM p09_parent WHERE id <= 100" "$HERE/explain-after.txt"
}

# 09 does not use the orders dataset; it manages its own tables.
rm -f "$RESULTS"
if [ -n "${CHILD_LABEL:-}" ]; then
  : "${CHILD_ROWS:?}"; run_one
else
  for t in "${CHILD_SIZES[@]}"; do
    CHILD_LABEL="${t%%:*}"; CHILD_ROWS="${t##*:}"; run_one
  done
fi
echo "  [09] done" >&2
