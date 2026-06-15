#!/usr/bin/env bash
# Scenario 06 - index size by column type + uuid insert-locality (v4 vs v7 vs bigint).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/lib/bench.sh"
source "$ROOT/config/sizes.sh"

SCEN="06-type-index-size"
RESULTS="$HERE/results.json"
COLS=(status_enum status_vc_short status_vc_long status_smallint key_bigint key_uuid4 key_uuid7)

# server-side wall time of one statement, in ms
time_stmt() { q "SELECT round((extract(epoch FROM clock_timestamp()) - $1)*1000.0)::bigint;"; }

run_one() {
  ensure_typesize "$TS_ROWS"
  echo "  [06] size=$SIZE_LABEL rows=$TS_ROWS" >&2

  # --- index size per column type ---
  local sizes='{}'
  for c in "${COLS[@]}"; do
    q "DROP INDEX IF EXISTS ts06_idx; CREATE INDEX ts06_idx ON typesize ($c);" >/dev/null
    local b; b="$(index_size_bytes ts06_idx)"
    sizes="$(echo "$sizes" | jq --arg k "$c" --argjson v "$b" '. + {($k):$v}')"
  done
  q "DROP INDEX IF EXISTS ts06_idx;" >/dev/null

  # --- uuid insert-locality: bulk-insert N keys, measure time + final pk index size ---
  local N=$(( TS_ROWS < 2000000 ? TS_ROWS : 2000000 ))
  local loc='{}'
  for kind in bigint uuid4 uuid7; do
    case "$kind" in
      bigint) col="g::bigint"  ; typ="bigint" ;;
      uuid4)  col="uuidv4()"   ; typ="uuid"   ;;   # PG18 builtin, random layout
      uuid7)  col="uuidv7()"   ; typ="uuid"   ;;   # PG18 builtin, time-ordered
    esac
    q "DROP TABLE IF EXISTS t06_$kind; CREATE UNLOGGED TABLE t06_$kind (id $typ PRIMARY KEY);" >/dev/null
    local t0; t0="$(q "SELECT extract(epoch FROM clock_timestamp());")"
    q "INSERT INTO t06_$kind SELECT $col FROM generate_series(1,$N) g;" >/dev/null
    local ms; ms="$(time_stmt "$t0")"
    local idxb; idxb="$(q "SELECT pg_relation_size((SELECT indexrelid FROM pg_index WHERE indrelid='t06_$kind'::regclass LIMIT 1));")"
    q "DROP TABLE IF EXISTS t06_$kind;" >/dev/null
    loc="$(echo "$loc" | jq --arg k "$kind" --argjson ms "$ms" --argjson b "$idxb" \
            '. + {($k):{insert_ms:$ms, pk_index_bytes:$b, rows:'"$N"'}}')"
  done

  local obj; obj="$(jq -n --arg sc "$SCEN" --arg size "$SIZE_LABEL" --argjson rows "$TS_ROWS" \
    --argjson sizes "$sizes" --argjson loc "$loc" --arg pgv "$(pg_version)" \
    '{scenario:$sc, size_label:$size, rows:$rows, index_size_bytes:$sizes, uuid_locality:$loc, pg_version:$pgv}')"
  append_result "$RESULTS" "$obj"
  echo "    enum=$(echo "$sizes"|jq .status_enum) vc_short=$(echo "$sizes"|jq .status_vc_short) vc_long=$(echo "$sizes"|jq .status_vc_long) bigint=$(echo "$sizes"|jq .key_bigint) uuid4=$(echo "$sizes"|jq .key_uuid4)" >&2
}

if [ -n "${SIZE_LABEL:-}" ]; then
  : "${TS_ROWS:?}"; run_one
else
  rm -f "$RESULTS"
  for t in "${ORDER_TIERS[@]}"; do
    SIZE_LABEL="${t%%:*}"; TS_ROWS="${t##*:}"; run_one
  done
fi
echo "  [06] done" >&2
