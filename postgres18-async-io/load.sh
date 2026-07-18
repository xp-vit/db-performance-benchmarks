#!/usr/bin/env bash
# Reproducible + resumable load of the async I/O benchmark dataset.
# Safe to re-run: it resumes from the last committed batch (load_progress).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$ROOT/config/settings.sh"
cd "$ROOT"

adm() { docker exec -i -e PGPASSWORD=bench "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 "$@"; }
bench() { docker exec -i -e PGPASSWORD=bench "$CONTAINER" psql -U postgres -d bench -v ON_ERROR_STOP=1 "$@"; }
wait_ready(){ for _ in $(seq 1 40); do docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && return 0; sleep 1; done; echo "pg not ready">&2; exit 1; }
disk_guard(){ local avail; avail=$(df --output=avail -k /home | tail -1); if [ "$avail" -lt 3000000 ]; then echo "ABORT: <3G free on /home, stopping load to protect the box" >&2; exit 1; fi; }

echo "[load] bringing up container..."
$COMPOSE up -d
wait_ready

echo "[load] ensure database 'bench' exists"
adm -tAc "SELECT 1 FROM pg_database WHERE datname='bench'" | grep -q 1 || adm -c "CREATE DATABASE bench"

echo "[load] apply schema"
bench < sql/00-schema.sql >/dev/null

# --- customers (once) ---
cust_done=$(bench -tAc "SELECT max_id FROM load_progress WHERE table_name='customers'" || echo "")
if [ "${cust_done:-0}" != "$CUSTOMERS" ]; then
  echo "[load] seeding customers = $CUSTOMERS"
  bench -v customers="$CUSTOMERS" -v tenants="$TENANTS" < sql/01-seed-customers.sql >/dev/null
fi

# --- events (resumable batches) ---
resume=$(bench -tAc "SELECT COALESCE(max_id,0) FROM load_progress WHERE table_name='events'" || echo 0)
resume=${resume:-0}
echo "[load] events target=$BIG_ROWS resume-from=$((resume+1)) batch=$LOAD_BATCH"
lo=$((resume+1))
while [ "$lo" -le "$BIG_ROWS" ]; do
  disk_guard
  hi=$((lo + LOAD_BATCH - 1)); [ "$hi" -gt "$BIG_ROWS" ] && hi=$BIG_ROWS
  t0=$(date +%s)
  bench -v lo="$lo" -v hi="$hi" -v tenants="$TENANTS" -v customers="$CUSTOMERS" \
        < sql/02-seed-events-batch.sql >/dev/null
  t1=$(date +%s)
  echo "  [load] events [$lo..$hi] in $((t1-t0))s  (free: $(df -h /home|tail -1|awk '{print $4}'))"
  lo=$((hi+1))
done

# --- finalize (indexes) once the full range is loaded ---
fin=$(bench -tAc "SELECT COALESCE(max_id,0) FROM load_progress WHERE table_name='events_finalized'" || echo 0)
cnt=$(bench -tAc "SELECT count(*) FROM events")
if [ "$cnt" -ge "$BIG_ROWS" ] && [ "${fin:-0}" != "1" ]; then
  echo "[load] finalize: building indexes + ANALYZE"
  bench < sql/03-finalize.sql >/dev/null
fi

echo "[load] done. sizes:"
bench -c "SELECT 'events rows' k, to_char(count(*),'FM999,999,999') v FROM events
          UNION ALL SELECT 'events heap', pg_size_pretty(pg_relation_size('events'))
          UNION ALL SELECT 'events total (heap+idx)', pg_size_pretty(pg_total_relation_size('events'))
          UNION ALL SELECT 'customers total', pg_size_pretty(pg_total_relation_size('customers'));"
