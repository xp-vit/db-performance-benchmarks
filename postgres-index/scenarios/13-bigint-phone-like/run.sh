#!/usr/bin/env bash
# Scenario 13 - prefix phone search, type vs index.
#   A: phone bigint, B-tree on the bigint  -> phone::text LIKE 'p%' seq-scans (cast, numeric index useless)
#   B: phone text (non-C ICU collation), plain B-tree -> LIKE still cannot use it -> seq scan
#   C: phone text, B-tree with text_pattern_ops -> LIKE 'p%' range-scans -> fast
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="13-bigint-phone-like"
PREFIX="150000"                       # 6 digits -> ~1e-5 of the key space
QA="SELECT count(*) FROM phones13 WHERE phone_bi::text LIKE '${PREFIX}%'"
QV="SELECT count(*) FROM phones13 WHERE phone_vc LIKE '${PREFIX}%'"
RESULTS="$HERE/results.json"

seed_phones() {                       # $1 = rows
  q "DROP TABLE IF EXISTS phones13;
     CREATE TABLE phones13 (
       id       bigint PRIMARY KEY,
       phone_bi bigint NOT NULL,
       phone_vc text COLLATE \"en-US-x-icu\" NOT NULL
     );
     INSERT INTO phones13 (id, phone_bi, phone_vc)
     SELECT g,
            10000000000 + ((g * 2654435761) % 10000000000),
            (10000000000 + ((g * 2654435761) % 10000000000))::text
     FROM generate_series(1, $1) g;
     ANALYZE phones13;" >/dev/null
}

run_one() {
  echo "  [13] size=$SIZE_LABEL rows=$ROWS  seeding ..." >&2
  seed_phones "$ROWS"
  local matches; matches="$(q "$QV")"

  # --- A: bigint + numeric B-tree (the original) ---
  q "DROP INDEX IF EXISTS p13_bi, p13_vc_plain, p13_vc_pat;
     CREATE INDEX p13_bi ON phones13 (phone_bi); ANALYZE phones13;" >/dev/null
  local exA="$HERE/explains/A-bigint-${SIZE_LABEL}.txt"
  explain_capture "$QA" "$exA"; local sA; sA="$(bench_stats_json "$QA")"
  cp "$exA" "$HERE/explain-before.txt"

  # --- B: text, non-C collation, plain B-tree (the "switched to varchar, still slow" trap) ---
  q "DROP INDEX IF EXISTS p13_bi, p13_vc_plain, p13_vc_pat;
     CREATE INDEX p13_vc_plain ON phones13 (phone_vc); ANALYZE phones13;" >/dev/null
  local exB="$HERE/explains/B-varchar-plain-${SIZE_LABEL}.txt"
  explain_capture "$QV" "$exB"; local sB; sB="$(bench_stats_json "$QV")"

  # --- C: text, B-tree with text_pattern_ops (the real fix) ---
  q "DROP INDEX IF EXISTS p13_bi, p13_vc_plain, p13_vc_pat;
     CREATE INDEX p13_vc_pat ON phones13 (phone_vc text_pattern_ops); ANALYZE phones13;" >/dev/null
  local exC="$HERE/explains/C-varchar-patternops-${SIZE_LABEL}.txt"
  explain_capture "$QV" "$exC"; local sC; sC="$(bench_stats_json "$QV")"
  cp "$exC" "$HERE/explain-after.txt"
  local cSize; cSize="$(index_size_bytes p13_vc_pat)"

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$ROWS" \
    --argjson matches "$matches" \
    --argjson a "$sA" --argjson b "$sB" --argjson c "$sC" \
    --arg aseq "$(has_node "$exA" 'Seq Scan')" \
    --arg bseq "$(has_node "$exB" 'Seq Scan')" \
    --arg cidx "$(has_node "$exC" 'p13_vc_pat')" \
    --argjson isize "$cSize" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows, prefix_matches:$matches,
      a_bigint_p50_ms:$a.p50_ms,        a_bigint_p95_ms:$a.p95_ms,
      b_varchar_plain_p50_ms:$b.p50_ms, b_varchar_plain_p95_ms:$b.p95_ms,
      c_pattern_ops_p50_ms:$c.p50_ms,   c_pattern_ops_p95_ms:$c.p95_ms,
      speedup_a_over_c:(($a.p50_ms)/($c.p50_ms)),
      a_seq_scan:($aseq=="true"), b_seq_scan:($bseq=="true"),
      c_index_used:($cidx=="true"), c_index_size_bytes:$isize, pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    A(bigint)=$(echo "$sA"|jq .p50_ms)ms  B(plain)=$(echo "$sB"|jq .p50_ms)ms  C(pattern_ops)=$(echo "$sC"|jq .p50_ms)ms  matches=$matches" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${ROWS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; ROWS="${t##*:}"; run_one
  done
fi
echo "  [13] done" >&2
