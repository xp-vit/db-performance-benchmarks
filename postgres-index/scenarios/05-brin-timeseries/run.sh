#!/usr/bin/env bash
# Scenario 05 - BRIN size + range-scan, ordered vs shuffled.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="05-brin-timeseries"
RESULTS="$HERE/results.json"

# build the range query for a table over a ~0.5% middle window
qrange() {  # $1=table $2=lo_seconds $3=hi_seconds
  echo "SELECT count(*), avg(value) FROM $1 WHERE ts >= timestamptz '2020-01-01 00:00:00+00' + $2 * interval '1 second' AND ts < timestamptz '2020-01-01 00:00:00+00' + $3 * interval '1 second'"
}

run_one() {
  ensure_events "$EVENT_ROWS"
  echo "  [05] size=$SIZE_LABEL rows=$EVENT_ROWS" >&2
  local lo=$(( EVENT_ROWS * 40 / 100 ))
  local hi=$(( EVENT_ROWS * 405 / 1000 ))      # 0.5% window
  local Q_ORD;  Q_ORD="$(qrange events "$lo" "$hi")"
  local Q_SHUF; Q_SHUF="$(qrange events_shuffled "$lo" "$hi")"

  # --- sizes (BRIN vs B-tree on ordered events) ---
  q "DROP INDEX IF EXISTS e05_brin_ts; DROP INDEX IF EXISTS e05_btree_ts; DROP INDEX IF EXISTS e05_brin_ts_shuf;" >/dev/null
  q "CREATE INDEX e05_brin_ts  ON events USING brin (ts);
     CREATE INDEX e05_btree_ts ON events USING btree (ts);
     CREATE INDEX e05_brin_ts_shuf ON events_shuffled USING brin (ts);
     ANALYZE events; ANALYZE events_shuffled;" >/dev/null
  local sz_brin;  sz_brin="$(index_size_bytes e05_brin_ts)"
  local sz_btree; sz_btree="$(index_size_bytes e05_btree_ts)"

  # --- ordered: BRIN ---
  q "SET enable_seqscan=on;" >/dev/null
  q "DROP INDEX e05_btree_ts;" >/dev/null         # leave only BRIN so planner must choose it (or seq)
  local ex_brin="$HERE/explains/brin-ordered-${SIZE_LABEL}.txt"
  explain_capture "$Q_ORD" "$ex_brin"; local s_brin; s_brin="$(bench_stats_json "$Q_ORD")"
  cp "$ex_brin" "$HERE/explain-after.txt"

  # --- ordered: B-tree ---
  q "CREATE INDEX e05_btree_ts ON events USING btree (ts); DROP INDEX e05_brin_ts;" >/dev/null
  local ex_bt="$HERE/explains/btree-ordered-${SIZE_LABEL}.txt"
  explain_capture "$Q_ORD" "$ex_bt"; local s_bt; s_bt="$(bench_stats_json "$Q_ORD")"

  # --- ordered: seq scan (no index) ---
  q "DROP INDEX e05_btree_ts;" >/dev/null
  local ex_seq="$HERE/explains/seq-ordered-${SIZE_LABEL}.txt"
  explain_capture "$Q_ORD" "$ex_seq"; local s_seq; s_seq="$(bench_stats_json "$Q_ORD")"
  cp "$ex_seq" "$HERE/explain-before.txt"

  # --- shuffled: BRIN (collapse) ---
  local ex_shuf="$HERE/explains/brin-shuffled-${SIZE_LABEL}.txt"
  explain_capture "$Q_SHUF" "$ex_shuf"; local s_shuf; s_shuf="$(bench_stats_json "$Q_SHUF")"

  # restore canonical indexes
  q "CREATE INDEX IF NOT EXISTS e05_brin_ts ON events USING brin (ts);" >/dev/null

  local obj; obj="$(jq -n \
    --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$EVENT_ROWS" \
    --argjson brin "$s_brin" --argjson bt "$s_bt" --argjson seq "$s_seq" --argjson shuf "$s_shuf" \
    --argjson szb "$sz_brin" --argjson szt "$sz_btree" \
    --arg brinnode "$(has_node "$ex_brin" 'Bitmap Index Scan on e05_brin_ts')" \
    --arg shufnode "$(has_node "$ex_shuf" 'Bitmap Index Scan on e05_brin_ts_shuf')" \
    --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows,
      brin_ordered_p50_ms:$brin.p50_ms, btree_ordered_p50_ms:$bt.p50_ms,
      seqscan_ordered_p50_ms:$seq.p50_ms, brin_shuffled_p50_ms:$shuf.p50_ms,
      brin_bytes:$szb, btree_bytes:$szt, size_ratio_btree_over_brin:(($szt)/($szb)),
      brin_used_ordered:($brinnode=="true"), brin_used_shuffled:($shufnode=="true"),
      pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    brin=$sz_brin B  btree=$sz_btree B  brin_ord p50=$(echo "$s_brin"|jq .p50_ms)ms  brin_shuf p50=$(echo "$s_shuf"|jq .p50_ms)ms" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${EVENT_ROWS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${EVENT_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; EVENT_ROWS="${t##*:}"; run_one
  done
fi
echo "  [05] done" >&2
