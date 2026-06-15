#!/usr/bin/env bash
# Scenario 10 - insert throughput + WAL vs number of indexes (K = 0,1,2,3,5,8).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="10-write-amplification"
RESULTS="$HERE/results.json"
INDEX_COUNTS=(0 1 2 3 5 8)
IDX_DDL=(
  "CREATE INDEX t10_a ON t10 (a)"   "CREATE INDEX t10_b ON t10 (b)"
  "CREATE INDEX t10_c ON t10 (c)"   "CREATE INDEX t10_d ON t10 (d)"
  "CREATE INDEX t10_e ON t10 (e)"   "CREATE INDEX t10_f ON t10 (f)"
  "CREATE INDEX t10_g ON t10 (g)"   "CREATE INDEX t10_ab ON t10 (a,b)"
)
M="${M:-1000000}"; [ "${QUICK:-0}" = "1" ] && M=200000

INSERT_SQL="INSERT INTO t10 SELECT g, (u01(g,1)*1e9)::bigint, (u01(g,2)*1e9)::bigint,
  timestamptz '2024-01-01' + (g*interval '1 second'), md5(g::text), (u01(g,3)*1e9)::bigint,
  (u01(g,4)*1000)::int, left(md5((g*7)::text),12) FROM generate_series(1,$M) g"

run_one() {
  echo "  [10] M=$M rows per insert" >&2
  for K in "${INDEX_COUNTS[@]}"; do
    pg < "$HERE/setup.sql" >/dev/null
    for ((i=0; i<K; i++)); do q "${IDX_DDL[$i]};" >/dev/null; done
    # measure
    local lsn0; lsn0="$(q "SELECT pg_current_wal_lsn();")"
    local t0;   t0="$(q "SELECT extract(epoch FROM clock_timestamp());")"
    q "$INSERT_SQL;" >/dev/null
    local ms;   ms="$(q "SELECT round((extract(epoch FROM clock_timestamp()) - $t0)*1000.0, 1);")"
    local wal;  wal="$(q "SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '$lsn0');")"
    local rps;  rps="$(q "SELECT round($M / ($ms/1000.0))::bigint;")"
    local obj; obj="$(jq -n --arg sc "$SCEN" --argjson k "$K" --argjson m "$M" \
      --argjson ms "$ms" --argjson wal "$wal" --argjson rps "$rps" --arg pgv "$(pg_version)" \
      '{scenario:$sc, size_label:("\($k) idx"), index_count:$k, insert_rows:$m,
        insert_ms:$ms, rows_per_sec:$rps, wal_bytes:$wal, pg_version:$pgv}')"
    append_result "$RESULTS" "$obj"
    echo "    K=$K  ${ms}ms  ${rps} rows/s  WAL=${wal}B" >&2
  done
  # representative plan: insert with 0 vs 8 indexes
  pg < "$HERE/setup.sql" >/dev/null
  explain_capture "$INSERT_SQL" "$HERE/explain-before.txt"
  pg < "$HERE/setup.sql" >/dev/null
  for d in "${IDX_DDL[@]}"; do q "$d;" >/dev/null; done
  explain_capture "$INSERT_SQL" "$HERE/explain-after.txt"
  q "DROP TABLE IF EXISTS t10;" >/dev/null
}

rm -f "$RESULTS"
run_one     # single representative M (index count is the swept dimension)
echo "  [10] done" >&2
