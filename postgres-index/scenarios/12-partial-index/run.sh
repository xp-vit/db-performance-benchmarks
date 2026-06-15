#!/usr/bin/env bash
# Scenario 12 - partial vs full index: size, latency, and the planner skipping the
# partial index when the query predicate does not match its WHERE.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="12-partial-index"
RESULTS="$HERE/results.json"
Q_PENDING="SELECT * FROM orders WHERE status = 'pending' ORDER BY created_at DESC LIMIT 50"
Q_PAID="SELECT * FROM orders WHERE status = 'paid' ORDER BY created_at DESC LIMIT 50"

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [12] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2

  # full index only
  q "DROP INDEX IF EXISTS o12_partial; CREATE INDEX IF NOT EXISTS o12_full ON orders (status, created_at); ANALYZE orders;" >/dev/null
  local full_sz; full_sz="$(index_size_bytes o12_full)"
  local ex_full="$HERE/explains/full-pending-${SIZE_LABEL}.txt"
  explain_capture "$Q_PENDING" "$ex_full"; local s_full; s_full="$(bench_stats_json "$Q_PENDING")"
  cp "$ex_full" "$HERE/explain-before.txt"

  # partial index only
  q "DROP INDEX IF EXISTS o12_full; CREATE INDEX IF NOT EXISTS o12_partial ON orders (created_at) WHERE status='pending'; ANALYZE orders;" >/dev/null
  local part_sz; part_sz="$(index_size_bytes o12_partial)"
  local ex_part="$HERE/explains/partial-pending-${SIZE_LABEL}.txt"
  explain_capture "$Q_PENDING" "$ex_part"; local s_part; s_part="$(bench_stats_json "$Q_PENDING")"
  cp "$ex_part" "$HERE/explain-after.txt"

  # skip demo: partial present, query on 'paid' (predicate mismatch -> cannot use partial)
  local ex_skip="$HERE/explains/partial-skip-paid-${SIZE_LABEL}.txt"
  explain_capture "$Q_PAID" "$ex_skip"

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" \
    --argjson full "$s_full" --argjson part "$s_part" \
    --argjson fsz "$full_sz" --argjson psz "$part_sz" \
    --arg partused "$(has_node "$ex_part" 'o12_partial')" \
    --arg skipseq "$(has_node "$ex_skip" 'Seq Scan')" \
    --arg skipusedpartial "$(has_node "$ex_skip" 'o12_partial')" \
    --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows,
      full_p50_ms:$full.p50_ms, partial_p50_ms:$part.p50_ms,
      full_index_bytes:$fsz, partial_index_bytes:$psz,
      size_ratio_full_over_partial:(($fsz)/($psz)),
      partial_used_on_match:($partused=="true"),
      partial_skipped_on_mismatch:($skipusedpartial=="false"),
      mismatch_seqscan:($skipseq=="true"), pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    full=${full_sz}B partial=${part_sz}B | pending: full=$(echo "$s_full"|jq .p50_ms)ms partial=$(echo "$s_part"|jq .p50_ms)ms" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [12] done" >&2
