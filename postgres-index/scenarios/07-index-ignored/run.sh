#!/usr/bin/env bash
# Scenario 07 - planner ignores the index: (a) lower(email), (b) implicit numeric cast.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="07-index-ignored"
RESULTS="$HERE/results.json"
Q_A="SELECT * FROM customers WHERE lower(email) = 'user.500@example.com'"
Q_B_CAST="SELECT * FROM orders WHERE id = '42'::numeric"
Q_B_TYPED="SELECT * FROM orders WHERE id = 42"

measure() {  # $1 label  $2 query  -> echoes json fragment file path stats via globals
  local lbl="$1" sql="$2"
  local exf="$HERE/explains/${lbl}-${SIZE_LABEL}.txt"
  explain_capture "$sql" "$exf"
  M_STATS="$(bench_stats_json "$sql")"
  M_SEQ="$(has_node "$exf" 'Seq Scan')"
  M_EXF="$exf"
}

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [07] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2

  # (a) plain email index present, expression index absent -> lower() cannot use it
  q "CREATE INDEX IF NOT EXISTS c07_email_plain ON customers (email); DROP INDEX IF EXISTS c07_email_lower; ANALYZE customers;" >/dev/null
  measure a_plain "$Q_A"; local a_plain_stats="$M_STATS" a_plain_seq="$M_SEQ"
  cp "$M_EXF" "$HERE/explain-before.txt"

  # (a) add expression index -> used
  q "CREATE INDEX IF NOT EXISTS c07_email_lower ON customers (lower(email)); ANALYZE customers;" >/dev/null
  measure a_expr "$Q_A"; local a_expr_stats="$M_STATS" a_expr_seq="$M_SEQ"
  cp "$M_EXF" "$HERE/explain-after.txt"

  # (b) implicit numeric cast vs correctly typed (orders PK always present)
  measure b_cast  "$Q_B_CAST";  local b_cast_stats="$M_STATS"  b_cast_seq="$M_SEQ"
  measure b_typed "$Q_B_TYPED"; local b_typed_stats="$M_STATS" b_typed_seq="$M_SEQ"

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" \
    --argjson ap "$a_plain_stats" --argjson ae "$a_expr_stats" \
    --argjson bc "$b_cast_stats" --argjson bt "$b_typed_stats" \
    --arg apseq "$a_plain_seq" --arg aeseq "$a_expr_seq" --arg bcseq "$b_cast_seq" --arg btseq "$b_typed_seq" \
    --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows,
      a_lower_plain_p50_ms:$ap.p50_ms, a_lower_expr_p50_ms:$ae.p50_ms,
      a_plain_seqscan:($apseq=="true"), a_expr_seqscan:($aeseq=="true"),
      a_speedup:(($ap.p50_ms)/($ae.p50_ms)),
      b_cast_p50_ms:$bc.p50_ms, b_typed_p50_ms:$bt.p50_ms,
      b_cast_seqscan:($bcseq=="true"), b_typed_seqscan:($btseq=="true"),
      b_speedup:(($bc.p50_ms)/($bt.p50_ms)), pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    (a) plain=$(echo "$a_plain_stats"|jq .p50_ms)ms expr=$(echo "$a_expr_stats"|jq .p50_ms)ms | (b) cast=$(echo "$b_cast_stats"|jq .p50_ms)ms typed=$(echo "$b_typed_stats"|jq .p50_ms)ms" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [07] done" >&2
