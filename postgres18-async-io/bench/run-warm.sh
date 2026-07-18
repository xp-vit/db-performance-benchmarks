#!/usr/bin/env bash
# WARM sweep. No cache dropping, no sudo. Two purposes:
#   - OLTP point-lookup throughput (pgbench) across io_method -> the honest
#     boundary where async I/O should be flat (data served from cache).
#   - warm seq/bitmap scans across io_method -> also expected flat.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
source "$ROOT/lib/bench.sh"
OUT="warm-$(date +%Y%m%d-%H%M%S).jsonl"
STAMP="$(date -u +%FT%TZ)"
: "${OLTP_SECONDS:=20}" ; : "${OLTP_CLIENTS:=8}"

emit(){ jq -nc --arg stamp "$STAMP" "$@" '$ARGS.named' >> "$RAW_DIR/$OUT"; }

# install the pgbench OLTP script into the container
docker exec -i "$CONTAINER" bash -c 'cat > /tmp/oltp.sql' <<'SQL'
\set id random(1, 30000000)
SELECT id, tenant_id, amount_cents, status FROM events WHERE id = :id;
SQL

SEQ="SELECT count(*), sum(amount_cents), avg(amount_cents) FROM events"
BITMAP="SELECT count(*), sum(amount_cents) FROM events WHERE event_type IN (2,5) AND status = 3"

echo "=== WARM sweep -> $RAW_DIR/$OUT ==="
for IOM in "${IO_METHODS[@]}"; do
  echo "--- io_method=$IOM ---"
  set_io_method "$IOM" >/dev/null

  # warm both scans first (prime cache), then measure warm runs
  q -c "SET max_parallel_workers_per_gather=0; $SEQ" >/dev/null
  for r in $(seq 1 "$WARM_RUNS"); do
    for pair in "seqscan:$SEQ" "bitmap:$BITMAP"; do
      op="${pair%%:*}"; sql="${pair#*:}"
      ms="$(q -c "SET max_parallel_workers_per_gather=0; EXPLAIN (ANALYZE, BUFFERS, TIMING) $sql" \
            | awk -F': ' '/Execution Time/{gsub(/ ms/,"",$2);print $2}')"
      emit --arg op "$op" --arg phase warm --arg io_method "$IOM" --argjson exec_ms "$ms"
      printf "    warm %-8s method=%-8s %8.1f ms\n" "$op" "$IOM" "$ms" >&2 || true
    done
  done

  # OLTP point-lookup throughput (warm)
  tps="$(docker exec -e PGPASSWORD=bench "$CONTAINER" pgbench -U postgres -d bench -n \
          -T "$OLTP_SECONDS" -c "$OLTP_CLIENTS" -j "$OLTP_CLIENTS" -f /tmp/oltp.sql 2>/dev/null \
          | awk '/tps/{print $3; exit}')"
  emit --arg op oltp_pointlookup --arg phase warm --arg io_method "$IOM" \
       --argjson tps "${tps:-0}" --argjson clients "$OLTP_CLIENTS" --argjson seconds "$OLTP_SECONDS"
  printf "    OLTP     method=%-8s %10.1f tps\n" "$IOM" "${tps:-0}" >&2 || true
done
echo "=== warm sweep done: $RAW_DIR/$OUT ==="
