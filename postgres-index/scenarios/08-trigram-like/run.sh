#!/usr/bin/env bash
# Scenario 08 - substring LIKE '%term%': seq scan vs trigram GIN.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="08-trigram-like"
QUERY="SELECT count(*) FROM orders WHERE search_text LIKE '%zfornax%'"
RESULTS="$HERE/results.json"

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [08] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2

  q "DROP INDEX IF EXISTS o08_trgm;" >/dev/null
  local exf="$HERE/explains/seqscan-${SIZE_LABEL}.txt"
  explain_capture "$QUERY" "$exf"; local s_seq; s_seq="$(bench_stats_json "$QUERY")"
  cp "$exf" "$HERE/explain-before.txt"

  q "CREATE INDEX o08_trgm ON orders USING gin (search_text gin_trgm_ops); ANALYZE orders;" >/dev/null
  local exg="$HERE/explains/trigram-${SIZE_LABEL}.txt"
  explain_capture "$QUERY" "$exg"; local s_trgm; s_trgm="$(bench_stats_json "$QUERY")"
  cp "$exg" "$HERE/explain-after.txt"

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" \
    --argjson seq "$s_seq" --argjson trgm "$s_trgm" \
    --arg ginused "$(has_node "$exg" 'o08_trgm')" --arg seqnode "$(has_node "$exf" 'Seq Scan')" \
    --argjson isize "$(index_size_bytes o08_trgm)" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows,
      seqscan_p50_ms:$seq.p50_ms, seqscan_p95_ms:$seq.p95_ms,
      trigram_p50_ms:$trgm.p50_ms, trigram_p95_ms:$trgm.p95_ms,
      speedup_p50:(($seq.p50_ms)/($trgm.p50_ms)),
      trigram_used:($ginused=="true"), seq_confirmed:($seqnode=="true"),
      index_size_bytes:$isize, pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    seq=$(echo "$s_seq"|jq .p50_ms)ms trgm=$(echo "$s_trgm"|jq .p50_ms)ms" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [08] done" >&2
