#!/usr/bin/env bash
# Scenario 01 - composite column order. Same query under the right-order index
# vs the wrong-order index, across the size sweep.
#
# Two ways to run:
#   ./run.sh                      standalone: loops all tiers, resets results.json
#   SIZE_LABEL=10M ORDERS_ROWS=10000000 CUSTOMERS=1000000 ./run.sh
#                                 single tier (used by run-all.sh, appends)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="01-composite-order"
QUERY="SELECT * FROM orders WHERE tenant_id = 3 AND status = 'paid' ORDER BY created_at DESC LIMIT 20"
RESULTS="$HERE/results.json"

run_one() {  # env: SIZE_LABEL ORDERS_ROWS CUSTOMERS
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [01] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2

  for variant in baseline wrong right; do
    case "$variant" in
      baseline) q "DROP INDEX IF EXISTS o01_wrong; DROP INDEX IF EXISTS o01_right;" >/dev/null; idx="" ;;
      wrong)    q "DROP INDEX IF EXISTS o01_right; CREATE INDEX IF NOT EXISTS o01_wrong ON orders (created_at, tenant_id, status);" >/dev/null; idx=o01_wrong ;;
      right)    q "DROP INDEX IF EXISTS o01_wrong; CREATE INDEX IF NOT EXISTS o01_right ON orders (tenant_id, status, created_at DESC);" >/dev/null; idx=o01_right ;;
    esac
    q "ANALYZE orders;" >/dev/null

    local exf="$HERE/explains/${variant}-${SIZE_LABEL}.txt"
    explain_capture "$QUERY" "$exf"
    local stats; stats="$(bench_stats_json "$QUERY")"
    local isize=0; [ -n "$idx" ] && isize="$(index_size_bytes "$idx")"

    local obj; obj="$(jq -n \
      --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" \
      --arg variant "$variant" --argjson stats "$stats" \
      --argjson hit "$(buffers_hit "$exf")" --argjson read "$(buffers_read "$exf")" \
      --arg sort "$(has_node "$exf" 'Sort')" --arg seqscan "$(has_node "$exf" 'Seq Scan')" \
      --argjson isize "$isize" --arg pgv "$(pg_version)" \
      '{scenario:$sc, size_label:$size, rows:$rows, variant:$variant,
        p50_ms:$stats.p50_ms, p95_ms:$stats.p95_ms, min_ms:$stats.min_ms, runs:$stats.n,
        buffers_shared_hit:$hit, buffers_shared_read:$read,
        has_sort:($sort=="true"), has_seqscan:($seqscan=="true"),
        index_size_bytes:$isize, pg_version:$pgv}')"
    append_result "$RESULTS" "$obj"
    # canonical before/after contract: before = baseline (no index), after = right order
    [ "$variant" = baseline ] && cp "$exf" "$HERE/explain-before.txt"
    [ "$variant" = right ]    && cp "$exf" "$HERE/explain-after.txt"
  done
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"
  run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"
    run_one
  done
fi
echo "  [01] done -> $RESULTS" >&2
