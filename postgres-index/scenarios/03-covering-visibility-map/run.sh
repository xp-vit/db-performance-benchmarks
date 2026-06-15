#!/usr/bin/env bash
# Scenario 03 - Heap Fetches across three visibility-map states:
#   post-vacuum -> mass-update -> re-vacuum.  Counters "covering index = never touches heap".
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="03-covering-visibility-map"
QUERY="SELECT sum(amount_cents) FROM orders WHERE tenant_id = 3 AND status = 'paid'"
RESULTS="$HERE/results.json"

measure() {  # $1 = state label
  local state="$1"
  local exf="$HERE/explains/${state}-${SIZE_LABEL}.txt"
  explain_capture "$QUERY" "$exf"
  local stats; stats="$(bench_stats_json "$QUERY")"
  local obj; obj="$(jq -n \
    --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" --arg state "$state" \
    --argjson stats "$stats" --argjson hf "$(heap_fetches "$exf")" \
    --argjson hit "$(buffers_hit "$exf")" --argjson read "$(buffers_read "$exf")" \
    --arg ios "$(has_node "$exf" 'Index Only Scan')" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows, state:$state,
      p50_ms:$stats.p50_ms, p95_ms:$stats.p95_ms, min_ms:$stats.min_ms, runs:$stats.n,
      heap_fetches:$hf, buffers_shared_hit:$hit, buffers_shared_read:$read,
      index_only_scan:($ios=="true"), pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    $state: heap_fetches=$(heap_fetches "$exf") p50=$(echo "$stats" | jq .p50_ms)ms" >&2
}

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [03] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2
  q "DROP INDEX IF EXISTS o03_cov; CREATE INDEX o03_cov ON orders (tenant_id, status) INCLUDE (amount_cents);" >/dev/null

  q "VACUUM (ANALYZE) orders;" >/dev/null
  measure post-vacuum
  cp "$HERE/explains/post-vacuum-${SIZE_LABEL}.txt" "$HERE/explain-before.txt"   # heap-free state

  # mass UPDATE the queried slice: dirties pages, clears VM all-visible bits
  q "UPDATE orders SET amount_cents = amount_cents + 1 WHERE tenant_id = 3;" >/dev/null
  q "ANALYZE orders;" >/dev/null
  measure post-update
  cp "$HERE/explains/post-update-${SIZE_LABEL}.txt" "$HERE/explain-after.txt"    # degraded state

  q "VACUUM (ANALYZE) orders;" >/dev/null
  measure post-revacuum

  invalidate_core   # we mutated orders (mass UPDATE); force a clean re-seed for the next scenario
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [03] done" >&2
