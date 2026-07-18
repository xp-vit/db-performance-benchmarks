#!/usr/bin/env bash
# COLD-cache async I/O sweep. Each measured sample flushes PG shared_buffers
# (container restart) AND the OS page cache (drop_caches -> needs root).
#
# Run this in YOUR shell so sudo can prompt on a real TTY, e.g.:
#     ! cd postgres18-async-io && sudo -v && ./bench/run-cold.sh
# or grant a narrow sudoers line for `tee /proc/sys/vm/drop_caches`.
#
# Env knobs:  IO_METHODS, EIC_SWEEP, COLD_RUNS, ONLY_OPS="seqscan bitmap vacuum reindex"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
source "$ROOT/lib/bench.sh"

OUT="cold-$(date +%Y%m%d-%H%M%S).jsonl"     # NOTE: date only for filename, fine here
: "${ONLY_OPS:=seqscan bitmap vacuum reindex}"
: "${EIC_COLD:=1 16 64}"                     # effective_io_concurrency sweep (scans)
: "${MIC_COLD:=16}"                           # maintenance_io_concurrency sweep (vacuum/reindex); set "1 16 64" to expand
: "${SWEEP_WORKERS:=0}"                        # 1 -> sweep io_workers for the worker method
: "${VACUUM_UPD_MOD:=20}"                      # update ~1/N of rows before each cold VACUUM (20 -> 5%)
STAMP="$(date -u +%FT%TZ)"

disk_guard(){ local a; a=$(df --output=avail -k /home|tail -1); [ "$a" -lt 3000000 ] && { echo "ABORT <3G free">&2; exit 1; }; return 0; }

# sanity: sudo works for drop_caches before we burn time
# (SKIP_SUDO_CHECK=1 with a mock DROP_CACHES_CMD is for dry-run plumbing tests only;
#  a real cold run MUST drop the OS page cache, which needs root.)
if [ "${SKIP_SUDO_CHECK:-0}" != 1 ]; then
  echo "checking drop_caches access..."
  if ! echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1; then
    echo "ERROR: cannot drop caches (need sudo). Run under sudo or add a sudoers line." >&2; exit 1
  fi
  echo "ok."
  # keep sudo credentials fresh for the whole (~1h) run from a single prompt
  ( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
else
  echo "WARNING: SKIP_SUDO_CHECK=1 -> OS page cache NOT dropped; numbers are NOT true-cold." >&2
fi

emit() { # kv pairs -> json line
  jq -nc --arg stamp "$STAMP" "$@" '$ARGS.named' >> "$RAW_DIR/$OUT"
}

measure_query_cold() { # $1 op  $2 sql  $3 eic  $4 io_workers
  local op="$1" sql="$2" eic="$3" iow="$4" ms reads t_read mb mbs rows
  echo "  >> ENTER measure op=$op sql_len=${#sql} eic=$eic iow=$iow method=$IOM" >&2
  go_cold
  # single-process for seqscan isolation; bitmap keeps parallel off too for clarity
  local pre="SET max_parallel_workers_per_gather=0; SET effective_io_concurrency=$eic;"
  local exp
  exp="$(q -c "$pre EXPLAIN (ANALYZE, BUFFERS, TIMING) $sql")"
  ms="$(echo "$exp" | awk -F': ' '/Execution Time/{gsub(/ ms/,"",$2);print $2}')"
  if [ -z "$ms" ]; then echo "FATAL $op: no Execution Time parsed (method=$IOM eic=$eic)" >&2; exit 1; fi
  # authoritative physical read volume + I/O wait time from the plan's top node
  # (pg_stat_io undercounts blocks read via the async io_method path).
  reads="$(echo "$exp" | awk '/Buffers: shared/{for(i=1;i<=NF;i++) if($i ~ /^read=/){sub(/read=/,"",$i); print $i; exit}}')"
  t_read="$(echo "$exp" | awk '/I\/O Timings: shared/{for(i=1;i<=NF;i++) if($i ~ /^read=/){sub(/read=/,"",$i); print $i; exit}}')"
  reads="${reads:-0}"; t_read="${t_read:-0}"
  mb="$(echo "scale=1; $reads*8192/1000000" | bc)"
  mbs="$(echo "scale=1; if ($ms>0) $mb/($ms/1000) else 0" | bc)"
  emit --arg op "$op" --arg phase cold --arg io_method "$IOM" --argjson io_workers "$iow" \
       --argjson eic "$eic" --argjson exec_ms "$ms" --argjson reads_blocks "$reads" \
       --argjson read_ms "$t_read" --argjson mb_read "$mb" --argjson mb_per_s "$mbs"
  printf "    %-8s method=%-8s eic=%-3s run: %8.1f ms  %6.1f MB  %7.1f MB/s\n" "$op" "$IOM" "$eic" "$ms" "$mb" "$mbs" >&2 || true
}

measure_maint_cold() { # $1 op  $2 setup_sql(unmeasured)  $3 op_sql  $4 mic
  local op="$1" setup="$2" opsql="$3" mic="$4" ms reads mb
  [ -n "$setup" ] && q -c "$setup" >/dev/null
  go_cold
  reset_io
  # two -c flags -> separate simple queries in ONE connection, so the SET applies
  # but VACUUM does not run inside a transaction block (single -c would wrap both).
  local t0 t1; t0=$(date +%s%N); q -c "SET maintenance_io_concurrency=$mic" -c "$opsql" >/dev/null; t1=$(date +%s%N)
  ms="$(echo "scale=1; ($t1-$t0)/1000000" | bc)"
  reads="$(io_reads_blocks)"; mb="$(echo "scale=1; $reads*8192/1000000" | bc)"
  emit --arg op "$op" --arg phase cold --arg io_method "$IOM" --argjson mic "$mic" \
       --argjson wall_ms "$ms" --argjson reads_blocks "$reads" --argjson mb_read "$mb"
  printf "    %-8s method=%-8s mic=%-3s wall: %9.1f ms  %6.1f MB\n" "$op" "$IOM" "$mic" "$ms" "$mb" >&2 || true
}

SEQ="SELECT count(*), sum(amount_cents), avg(amount_cents) FROM events"
BITMAP="SELECT count(*), sum(amount_cents) FROM events WHERE event_type IN (2,5) AND status = 3"

# allow a single-method (or custom) override without editing settings.sh
[ -n "${METHODS_OVERRIDE:-}" ] && IO_METHODS=($METHODS_OVERRIDE)

echo "=== COLD sweep -> $RAW_DIR/$OUT ==="
echo "=== IO_METHODS=[${IO_METHODS[*]}] ONLY_OPS=[$ONLY_OPS] EIC_COLD=[$EIC_COLD] COLD_RUNS=$COLD_RUNS ===" >&2
for IOM in "${IO_METHODS[@]}"; do
  echo "--- io_method=$IOM ---"
  set_io_method "$IOM" >/dev/null
  # worker method: optionally sweep io_workers (SWEEP_WORKERS=1); else default 3
  workers_list=(3); [ "$IOM" = worker ] && [ "$SWEEP_WORKERS" = 1 ] && workers_list=(${IO_WORKERS_SWEEP[@]})

  for iow in "${workers_list[@]}"; do
    [ "$IOM" = worker ] && set_io_workers "$iow"
    for r in $(seq 1 "$COLD_RUNS"); do
      disk_guard
      for eic in $EIC_COLD; do
        # case (not &&) so set -e stays active inside the measure fns and any
        # failure aborts loudly instead of being silently swallowed.
        case " $ONLY_OPS " in *" seqscan "*) measure_query_cold seqscan "$SEQ"    "$eic" "$iow";; esac
        case " $ONLY_OPS " in *" bitmap "*)  measure_query_cold bitmap  "$BITMAP" "$eic" "$iow";; esac
      done
    done
  done

  # maintenance ops: sweep maintenance_io_concurrency (PG18 vacuum/build use this)
  if [ "$IOM" != worker ] || true; then
    for r in $(seq 1 "$COLD_RUNS"); do
      disk_guard
      for mic in $MIC_COLD; do
        # vacuum after a fresh ~5% scattered update (unmeasured setup)
        case " $ONLY_OPS " in *" vacuum "*)
          measure_maint_cold vacuum "UPDATE events SET status = status WHERE id % $VACUUM_UPD_MOD = $((r-1))" \
            "VACUUM events" "$mic";; esac
        case " $ONLY_OPS " in *" reindex "*)
          measure_maint_cold reindex "" "REINDEX INDEX events_tenant_ts" "$mic";; esac
      done
    done
  fi
done
echo "=== cold sweep done: $RAW_DIR/$OUT ==="
