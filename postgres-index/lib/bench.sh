#!/usr/bin/env bash
# Shared benchmark helpers. Source this from a scenario run.sh:
#   source "$(git rev-parse --show-toplevel)/postgres-index/lib/bench.sh"
# Honest-metrics contract: latency comes from the server-side bench harness (sql/90),
# buffers + plan shape come from a committed EXPLAIN (ANALYZE, BUFFERS).

set -euo pipefail

CONTAINER="${CONTAINER:-pgbench-index}"
DBUSER="${DBUSER:-bench}"
DBNAME="${DBNAME:-bench}"
RUNS="${RUNS:-12}"          # timed runs per query (>=10 per methodology)
WARMUP="${WARMUP:-3}"       # warmup executions before timing (warm-cache measurement)

PG_IMAGE="postgres:18.4"
PG_IMAGE_DIGEST="sha256:29ee7bb30d804447dc9a91fd0d74322ae1dc3a4072cc6346f70a5ed6e783b565"

# ---- raw psql access -------------------------------------------------------
pg()  { docker exec -i "$CONTAINER" psql -U "$DBUSER" -d "$DBNAME" -v ON_ERROR_STOP=1 "$@"; }
q()   { pg -tAc "$1"; }                       # single scalar / tab rows, no headers
qf()  { pg "$@"; }                            # run a file via stdin redirection by caller

pg_version() { q "show server_version;"; }

# ---- timing ----------------------------------------------------------------
# bench_stats_json "<SQL>" -> {"p50_ms":..,"p95_ms":..,"min_ms":..,"n":..}
# Uses dollar-quoting ($BENCH$) so the inner SQL needs no escaping.
bench_stats_json() {
  local sql="$1" runs="${2:-$RUNS}" warm="${3:-$WARMUP}"
  q "SELECT json_build_object('p50_ms',p50_ms,'p95_ms',p95_ms,'min_ms',min_ms,'n',n)
       FROM bench_stats(\$BENCH\$ ${sql} \$BENCH\$, ${runs}, ${warm});"
}

# ---- EXPLAIN capture -------------------------------------------------------
# explain_capture "<SQL>" "<outfile>"  -> writes EXPLAIN (ANALYZE, BUFFERS) text
explain_capture() {
  local sql="$1" out="$2"
  {
    echo "-- $(date -u +%Y-%m-%dT%H:%M:%SZ)  PG ${PG_IMAGE}@${PG_IMAGE_DIGEST}"
    echo "-- query:"
    echo "$sql" | sed 's/^/--   /'
    echo "--"
    pg -X -c "EXPLAIN (ANALYZE, BUFFERS, VERBOSE) ${sql}"
  } > "$out"
}

# ---- parse helpers (read a committed explain .txt) -------------------------
# First "Buffers:" line is the root node => cumulative totals for the whole plan.
buffers_hit()  { grep -m1 -oE 'shared hit=[0-9]+'  "$1" | grep -oE '[0-9]+' || echo 0; }
buffers_read() { grep -m1 -oE 'shared read=[0-9]+' "$1" | grep -oE '[0-9]+' || echo 0; }
heap_fetches() { grep -m1 -oE 'Heap Fetches: [0-9]+' "$1" | grep -oE '[0-9]+' || echo 0; }
has_node()     { grep -qE "$2" "$1" && echo true || echo false; }   # has_node FILE 'Seq Scan'
exec_time_ms() { grep -m1 -oE 'Execution Time: [0-9.]+' "$1" | grep -oE '[0-9.]+' || echo 0; }

# ---- sizes -----------------------------------------------------------------
rel_size_bytes()   { q "SELECT pg_relation_size('$1');"; }              # heap only / index only
total_size_bytes() { q "SELECT pg_total_relation_size('$1');"; }
index_size_bytes() { q "SELECT pg_relation_size('$1');"; }
pretty_size()      { q "SELECT pg_size_pretty(pg_relation_size('$1'));"; }

# ---- cache control ---------------------------------------------------------
# Warm: handled by WARMUP in bench harness. Cold: restart container (clears
# shared_buffers). True OS-cache drop needs host privileges; we record which we got.
cold_restart() {
  docker restart "$CONTAINER" >/dev/null
  for _ in $(seq 1 30); do
    [ "$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" = healthy ] && break
    sleep 1
  done
}

# ---- idempotent seeding (marker table avoids redundant re-seeds per tier) --
if [ -n "${BASH_SOURCE:-}" ]; then
  SQL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/sql"
else
  SQL_DIR="$(git rev-parse --show-toplevel)/postgres-index/sql"   # zsh / interactive fallback
fi

_ensure_state_table() {
  q "CREATE TABLE IF NOT EXISTS bench_state(k text PRIMARY KEY, v text);" >/dev/null
}
_state_get() { q "SELECT v FROM bench_state WHERE k='$1';"; }
_state_set() { q "INSERT INTO bench_state(k,v) VALUES('$1','$2')
                  ON CONFLICT(k) DO UPDATE SET v=excluded.v;" >/dev/null; }

# ensure_core <orders_rows> <customers_rows>
ensure_core() {
  _ensure_state_table
  local want="$1:$2"
  if [ "$(_state_get core)" != "$want" ]; then
    echo "  seeding core: orders=$1 customers=$2 ..." >&2
    pg -v customers="$2" -v orders="$1" < "$SQL_DIR/11-seed-core.sql" >/dev/null
    _state_set core "$want"
  fi
}
# mutating scenarios call this so the next ensure_core re-seeds a clean dataset
invalidate_core() { _ensure_state_table; _state_set core "dirty"; }

# ensure_events <rows>
ensure_events() {
  _ensure_state_table
  if [ "$(_state_get events)" != "$1" ]; then
    echo "  seeding events=$1 ..." >&2
    pg -v events="$1" < "$SQL_DIR/21-seed-events.sql" >/dev/null
    _state_set events "$1"
  fi
}
# ensure_typesize <rows>
ensure_typesize() {
  _ensure_state_table
  if [ "$(_state_get typesize)" != "$1" ]; then
    echo "  seeding typesize=$1 ..." >&2
    pg -v rows="$1" < "$SQL_DIR/31-seed-typesize.sql" >/dev/null
    _state_set typesize "$1"
  fi
}

# drop every non-primary index on a table (TRUNCATE keeps indexes, so reseed is not enough)
drop_secondary_indexes() {
  q "DO \$\$ DECLARE r record; BEGIN
       FOR r IN SELECT indexrelid::regclass AS i FROM pg_index
                WHERE indrelid='$1'::regclass AND NOT indisprimary LOOP
         EXECUTE 'DROP INDEX IF EXISTS '||r.i; END LOOP; END \$\$;" >/dev/null
}

# append a JSON object into a results.json array (creates [] if absent)
append_result() {
  local f="$1" obj="$2" cur='[]'
  [ -f "$f" ] && cur="$(cat "$f")"
  echo "$cur" | jq --argjson o "$obj" '. + [$o]' > "$f"
}

# results dir helper
results_meta_json() {
  # $1 = scenario id, prints common metadata fields (no braces)
  printf '"scenario":"%s","pg_version":"%s","pg_image":"%s","pg_image_digest":"%s"' \
    "$1" "$(pg_version)" "$PG_IMAGE" "$PG_IMAGE_DIGEST"
}
