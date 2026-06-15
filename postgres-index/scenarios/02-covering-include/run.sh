#!/usr/bin/env bash
# Scenario 02 - covering index (INCLUDE) turns Index Scan + heap fetch into Index Only Scan.
# The story is in buffers (shared hit/read), so we report those alongside latency.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="02-covering-include"
QUERY="SELECT sum(amount_cents) FROM orders WHERE tenant_id = 3 AND status = 'paid'"
RESULTS="$HERE/results.json"

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [02] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2
  for variant in plain include; do
    if [ "$variant" = include ]; then
      q "DROP INDEX IF EXISTS o02_plain; CREATE INDEX IF NOT EXISTS o02_include ON orders (tenant_id, status) INCLUDE (amount_cents);" >/dev/null
      idx=o02_include
    else
      q "DROP INDEX IF EXISTS o02_include; CREATE INDEX IF NOT EXISTS o02_plain ON orders (tenant_id, status);" >/dev/null
      idx=o02_plain
    fi
    q "VACUUM (ANALYZE) orders;" >/dev/null     # set visibility map so index-only can be heap-free

    local exf="$HERE/explains/${variant}-${SIZE_LABEL}.txt"
    explain_capture "$QUERY" "$exf"
    local stats; stats="$(bench_stats_json "$QUERY")"
    local obj; obj="$(jq -n \
      --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" --arg variant "$variant" \
      --argjson stats "$stats" \
      --argjson hit "$(buffers_hit "$exf")" --argjson read "$(buffers_read "$exf")" \
      --argjson hf "$(heap_fetches "$exf")" \
      --arg ios "$(has_node "$exf" 'Index Only Scan')" \
      --argjson isize "$(index_size_bytes "$idx")" --arg pgv "$(pg_version)" \
      '{scenario:$sc, size_label:$size, rows:$rows, variant:$variant,
        p50_ms:$stats.p50_ms, p95_ms:$stats.p95_ms, min_ms:$stats.min_ms, runs:$stats.n,
        buffers_shared_hit:$hit, buffers_shared_read:$read, buffers_total:($hit+$read),
        heap_fetches:$hf, index_only_scan:($ios=="true"),
        index_size_bytes:$isize, pg_version:$pgv}')"
    append_result "$RESULTS" "$obj"
    [ "$variant" = plain ]   && cp "$exf" "$HERE/explain-before.txt"
    [ "$variant" = include ] && cp "$exf" "$HERE/explain-after.txt"
  done
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [02] done" >&2
