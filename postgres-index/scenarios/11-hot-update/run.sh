#!/usr/bin/env bash
# Scenario 11 - HOT update rate. Two independent levers:
#   (1) is the UPDATED column indexed?  Indexing it makes HOT impossible, period.
#   (2) is there free space on the page (fillfactor)?  HOT needs room - but only helps
#       when the update is otherwise HOT-eligible (no indexed column changed).
# We measure all four corners so the data shows that fillfactor does NOT rescue HOT
# once the updated column is indexed (counters the "ff70 restores HOT" oversimplification).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="11-hot-update"
RESULTS="$HERE/results.json"
ROWS="${ROWS:-50000}"; [ "${QUICK:-0}" = "1" ] && ROWS=20000
HOT_ROWS=10000          # repeatedly updated subset (page pruning lets HOT sustain)
PASSES=50

# label | fillfactor | index_on_h(0/1)
CONFIGS=(
  "no_index_ff100:100:0"
  "no_index_ff70:70:0"
  "indexed_ff100:100:1"
  "indexed_ff70:70:1"
)

run_config() {
  local label="$1" ff="$2" idx="$3"
  q "DROP TABLE IF EXISTS t11 CASCADE;
     CREATE TABLE t11 (id bigint PRIMARY KEY, h bigint, pad text) WITH (fillfactor=$ff);
     INSERT INTO t11 SELECT g, 0, repeat('x',20) FROM generate_series(1,$ROWS) g;" >/dev/null
  [ "$idx" = 1 ] && q "CREATE INDEX t11_h ON t11 (h);" >/dev/null
  q "VACUUM (ANALYZE) t11;" >/dev/null
  q "SELECT pg_stat_reset_single_table_counters('t11'::regclass);" >/dev/null

  local t0; t0="$(q "SELECT extract(epoch FROM clock_timestamp());")"
  for ((p=0; p<PASSES; p++)); do q "UPDATE t11 SET h = h + 1 WHERE id <= $HOT_ROWS;" >/dev/null; done
  local ms; ms="$(q "SELECT round((extract(epoch FROM clock_timestamp()) - $t0)*1000.0,1);")"

  read -r upd hot <<<"$(q "SELECT n_tup_upd||' '||n_tup_hot_upd FROM pg_stat_user_tables WHERE relname='t11';")"
  local rate; rate="$(q "SELECT round(100.0 * $hot / NULLIF($upd,0), 1);")"
  local obj; obj="$(jq -n --arg sc "$SCEN" --arg label "$label" --argjson ff "$ff" \
    --argjson idx "$idx" --argjson upd "$upd" --argjson hot "$hot" \
    --argjson rate "${rate:-0}" --argjson ms "$ms" --argjson rows "$ROWS" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$label, config:$label, fillfactor:$ff, index_on_hot:($idx==1),
      n_tup_upd:$upd, n_tup_hot_upd:$hot, hot_pct:$rate, update_ms:$ms,
      rows:$rows, hot_rows:'"$HOT_ROWS"', passes:'"$PASSES"', pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    $label: HOT=${rate}% ($hot/$upd) ${ms}ms" >&2
}

rm -f "$RESULTS"
echo "  [11] rows=$ROWS hot_rows=$HOT_ROWS passes=$PASSES" >&2
for c in "${CONFIGS[@]}"; do
  IFS=: read -r label ff idx <<<"$c"
  run_config "$label" "$ff" "$idx"
done
# explain before/after = update with no hot index vs with hot index (ff70 both)
q "DROP TABLE IF EXISTS t11 CASCADE; CREATE TABLE t11 (id bigint PRIMARY KEY, h bigint, pad text) WITH (fillfactor=70);
   INSERT INTO t11 SELECT g,0,repeat('x',20) FROM generate_series(1,$ROWS) g;" >/dev/null
q "VACUUM (ANALYZE) t11;" >/dev/null
explain_capture "UPDATE t11 SET h = h + 1 WHERE id <= 1000" "$HERE/explain-before.txt"
q "CREATE INDEX t11_h ON t11 (h);" >/dev/null
q "VACUUM (ANALYZE) t11;" >/dev/null
explain_capture "UPDATE t11 SET h = h + 1 WHERE id <= 1000" "$HERE/explain-after.txt"
q "DROP TABLE IF EXISTS t11 CASCADE;" >/dev/null
echo "  [11] done" >&2
