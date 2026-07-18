#!/usr/bin/env bash
# Shared helpers for the async I/O bench drivers.
set -euo pipefail
export LC_ALL=C   # dot decimals everywhere (host locale uses comma) -> clean printf/bc/jq
HERE_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$HERE_LIB/../config/settings.sh"

CID="$CONTAINER"

# --- psql into the container (no host psql dependency) ---
q()  { docker exec -i -e PGPASSWORD=bench "$CID" psql -U postgres -d bench -v ON_ERROR_STOP=1 "$@"; }
qt() { q -tAc "$1"; }                       # single value / tuples-only
qfile() { docker exec -i -e PGPASSWORD=bench "$CID" psql -U postgres -d bench -v ON_ERROR_STOP=1 "$@"; }

pg_up()      { docker inspect -f '{{.State.Running}}' "$CID" 2>/dev/null | grep -q true; }
wait_ready() { for _ in $(seq 1 40); do docker exec "$CID" pg_isready -U postgres >/dev/null 2>&1 && return 0; sleep 1; done; echo "pg not ready" >&2; return 1; }

# --- io_method swap (PGC_POSTMASTER -> ALTER SYSTEM + container restart) ---
set_io_method() {   # $1 = sync|worker|io_uring
  local m="$1"
  q -c "ALTER SYSTEM SET io_method = '$m';" >/dev/null
  docker restart "$CID" >/dev/null
  wait_ready
  local live; live="$(qt 'SHOW io_method;')"
  [ "$live" = "$m" ] || { echo "io_method mismatch: wanted $m got $live" >&2; return 1; }
  echo "$live"
}

set_io_workers() {  # $1 = N (PGC_SIGHUP -> reload)
  q -c "ALTER SYSTEM SET io_workers = $1;" >/dev/null
  q -c "SELECT pg_reload_conf();" >/dev/null
}

# --- cold cache: flush PG shared_buffers (restart) + OS page cache (needs root) ---
# DROP_CACHES_CMD lets the caller inject how root is obtained. Default uses sudo,
# which will prompt on the user's TTY (run the cold driver via `!` in-session).
: "${DROP_CACHES_CMD:=sudo tee /proc/sys/vm/drop_caches}"
go_cold() {
  q -c "CHECKPOINT;" >/dev/null 2>&1 || true
  docker stop "$CID" >/dev/null
  sync
  echo 3 | ${DROP_CACHES_CMD} >/dev/null
  docker start "$CID" >/dev/null
  wait_ready
  # pg_isready can report ready while the first backend query still races
  # startup -> settle on a real query before measuring.
  local i; for i in $(seq 1 20); do q -c "SELECT 1" >/dev/null 2>&1 && return 0; sleep 0.5; done
  echo "go_cold: db not answering queries after restart" >&2; return 1
}

# --- I/O accounting via pg_stat_io (reset -> op -> read) ---
reset_io() { q -c "SELECT pg_stat_reset_shared('io');" >/dev/null; }
# total blocks read and read_time(ms) across all contexts since reset
io_reads_blocks() { qt "SELECT COALESCE(sum(reads),0)::bigint FROM pg_stat_io WHERE reads IS NOT NULL;"; }
io_read_ms()      { qt "SELECT COALESCE(sum(read_time),0)::double precision FROM pg_stat_io WHERE read_time IS NOT NULL;"; }

# --- timing ---
# server-side execution time (ms) of a query via EXPLAIN ANALYZE; also stash plan
explain_ms() {  # $1 sql ; $2 outfile(optional)
  local sql="$1" out="${2:-/dev/null}"
  q -c "EXPLAIN (ANALYZE, BUFFERS, TIMING, VERBOSE OFF) $sql" | tee "$out" \
    | awk -F': ' '/Execution Time/ {gsub(/ ms/,"",$2); print $2}'
}
# wall time (ms) of an arbitrary statement (for VACUUM/REINDEX/CREATE INDEX)
timed_ms() {  # $1 sql
  local sql="$1" t0 t1
  t0=$(date +%s%N)
  q -c "$sql" >/dev/null
  t1=$(date +%s%N)
  echo "scale=1; ($t1 - $t0)/1000000" | bc
}

# median of numbers on stdin (one per line)
median() { sort -n | awk '{a[NR]=$1} END{ if(NR==0){print 0} else if(NR%2){print a[(NR+1)/2]} else {print (a[NR/2]+a[NR/2+1])/2} }'; }

# append one JSON result object (arg $1) to results/raw/<file>.jsonl (arg $2)
append_raw() { printf '%s\n' "$1" >> "$RAW_DIR/$2"; }

heap_bytes()  { qt "SELECT pg_relation_size('events');"; }
table_bytes() { qt "SELECT pg_total_relation_size('events');"; }
pg_settings_json() {
  qt "SELECT json_build_object(
        'io_method', current_setting('io_method'),
        'io_workers', current_setting('io_workers'),
        'shared_buffers', current_setting('shared_buffers'),
        'effective_io_concurrency', current_setting('effective_io_concurrency'),
        'max_parallel_workers_per_gather', current_setting('max_parallel_workers_per_gather'),
        'version', version());"
}
