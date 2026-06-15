#!/usr/bin/env bash
# Scenario 04 - jsonb @> containment: seq scan vs GIN(jsonb_path_ops).
# Measures TWO predicates so the chart shows the GIN win is selectivity-driven:
#   moderate (~1% of rows)  vs  rare (~0.02%, the 'RARE-NEEDLE' sku).
# Also records jsonb_ops vs jsonb_path_ops index size.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="04-gin-jsonb"
RESULTS="$HERE/results.json"
Q_MOD="SELECT count(*) FROM orders WHERE payload @> '{\"category\":\"electronics\",\"region\":\"eu\",\"priority\":2}'"
Q_RARE="SELECT count(*) FROM orders WHERE payload @> '{\"sku\":\"RARE-NEEDLE\"}'"

# measure one predicate seq vs gin; sets globals SEQ GIN HITSEQ READSEQ GINUSED MATCHED
measure_pred() {  # $1 label  $2 sql
  local lbl="$1" sql="$2"
  q "DROP INDEX IF EXISTS o04_gin_pathops; DROP INDEX IF EXISTS o04_gin_ops;" >/dev/null
  local exs="$HERE/explains/seqscan-${lbl}-${SIZE_LABEL}.txt"
  explain_capture "$sql" "$exs"; SEQ="$(bench_stats_json "$sql")"
  q "CREATE INDEX o04_gin_pathops ON orders USING gin (payload jsonb_path_ops); ANALYZE orders;" >/dev/null
  local exg="$HERE/explains/gin-${lbl}-${SIZE_LABEL}.txt"
  explain_capture "$sql" "$exg"; GIN="$(bench_stats_json "$sql")"
  GINUSED="$(has_node "$exg" 'o04_gin_pathops')"
  MATCHED="$(q "$sql")"
  PSZ="$(index_size_bytes o04_gin_pathops)"
  # keep canonical before/after on the rare predicate (the dramatic one)
  if [ "$lbl" = rare ]; then cp "$exs" "$HERE/explain-before.txt"; cp "$exg" "$HERE/explain-after.txt"; fi
}

run_one() {
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  echo "  [04] size=$SIZE_LABEL rows=$ORDERS_ROWS" >&2

  measure_pred moderate "$Q_MOD"; local mod_seq="$SEQ" mod_gin="$GIN" mod_used="$GINUSED" mod_n="$MATCHED"
  measure_pred rare     "$Q_RARE"; local rare_seq="$SEQ" rare_gin="$GIN" rare_used="$GINUSED" rare_n="$MATCHED" psz="$PSZ"

  # jsonb_ops size for the comparison note
  q "CREATE INDEX o04_gin_ops ON orders USING gin (payload jsonb_ops);" >/dev/null
  local osz; osz="$(index_size_bytes o04_gin_ops)"
  q "DROP INDEX IF EXISTS o04_gin_ops;" >/dev/null

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ORDERS_ROWS" \
    --argjson ms "$mod_seq" --argjson mg "$mod_gin" --argjson rs "$rare_seq" --argjson rg "$rare_gin" \
    --argjson modn "$mod_n" --argjson raren "$rare_n" \
    --arg modused "$mod_used" --arg rareused "$rare_used" \
    --argjson psz "$psz" --argjson osz "$osz" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows,
      moderate:{matched_rows:$modn, selectivity_pct:(($modn/$rows)*100),
                seq_p50_ms:$ms.p50_ms, gin_p50_ms:$mg.p50_ms, speedup:(($ms.p50_ms)/($mg.p50_ms)), gin_used:($modused=="true")},
      rare:{matched_rows:$raren, selectivity_pct:(($raren/$rows)*100),
            seq_p50_ms:$rs.p50_ms, gin_p50_ms:$rg.p50_ms, speedup:(($rs.p50_ms)/($rg.p50_ms)), gin_used:($rareused=="true")},
      gin_pathops_bytes:$psz, gin_ops_bytes:$osz, pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    moderate: seq=$(echo "$mod_seq"|jq .p50_ms) gin=$(echo "$mod_gin"|jq .p50_ms) (${mod_n} rows) | rare: seq=$(echo "$rare_seq"|jq .p50_ms) gin=$(echo "$rare_gin"|jq .p50_ms) (${rare_n} rows)" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ORDERS_ROWS:?}" "${CUSTOMERS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ORDERS_ROWS="${t##*:}"; CUSTOMERS="$(customers_for "$ORDERS_ROWS")"; run_one
  done
fi
echo "  [04] done" >&2
