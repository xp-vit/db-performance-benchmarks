#!/usr/bin/env bash
# Reproduce the whole postgres-index campaign from a clean clone:
#   ./run-all.sh            full size sweep (1M..30M orders, 1M..100M events)
#   QUICK=1 ./run-all.sh    fast dev pass (small tiers)
#
# Brings up the pinned PG18.4 container, installs schema+harness, runs all 12 scenarios
# across the size sweep, then regenerates every chart. Honest-metrics: each number is
# backed by a committed EXPLAIN and results.json under scenarios/NN-*/.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
source "$HERE/lib/bench.sh"
source "$HERE/config/sizes.sh"

echo "== bring up pinned PG18.4 =="
docker compose up -d
for _ in $(seq 1 40); do
  [ "$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)" = healthy ] && break
  sleep 1
done

echo "== install extensions, schema, harness =="
pg < sql/00-extensions-helpers.sql >/dev/null
pg < sql/10-schema-core.sql        >/dev/null
pg < sql/20-schema-events.sql      >/dev/null
pg < sql/30-schema-typesize.sql    >/dev/null
pg < sql/90-bench-harness.sql      >/dev/null
q "TRUNCATE bench_state;" 2>/dev/null || q "CREATE TABLE IF NOT EXISTS bench_state(k text PRIMARY KEY, v text);" >/dev/null

SR() { bash "scenarios/$1/run.sh"; }

# ---- orders-backed scenarios, swept over ORDER_TIERS (seed once per tier) ----
# 03 mutates orders, so it runs last in each tier and invalidates the seed afterwards.
ORDERS_SCENARIOS=(01-composite-order 02-covering-include 04-gin-jsonb 07-index-ignored 08-trigram-like 12-partial-index 03-covering-visibility-map)
for s in "${ORDERS_SCENARIOS[@]}"; do rm -f "scenarios/$s/results.json"; done

echo "== orders scenarios over tiers: ${ORDER_TIERS[*]} =="
for t in "${ORDER_TIERS[@]}"; do
  export SIZE_LABEL="${t%%:*}" ORDERS_ROWS="${t##*:}"
  export CUSTOMERS="$(customers_for "$ORDERS_ROWS")"
  ensure_core "$ORDERS_ROWS" "$CUSTOMERS"
  for s in "${ORDERS_SCENARIOS[@]}"; do
    drop_secondary_indexes orders          # isolate each scenario's plan
    echo "-- tier=$SIZE_LABEL scenario=$s"
    SR "$s"
  done
done
unset SIZE_LABEL ORDERS_ROWS CUSTOMERS

# ---- typesize scenario (06), swept over ORDER_TIERS row counts ----
echo "== scenario 06 (type/index size) over tiers =="
rm -f scenarios/06-type-index-size/results.json
for t in "${ORDER_TIERS[@]}"; do
  export SIZE_LABEL="${t%%:*}" TS_ROWS="${t##*:}"
  ensure_typesize "$TS_ROWS"
  SR 06-type-index-size
done
unset SIZE_LABEL TS_ROWS

# ---- events scenario (05), swept over EVENT_TIERS ----
echo "== scenario 05 (BRIN) over tiers: ${EVENT_TIERS[*]} =="
rm -f scenarios/05-brin-timeseries/results.json
for t in "${EVENT_TIERS[@]}"; do
  export SIZE_LABEL="${t%%:*}" EVENT_ROWS="${t##*:}"
  ensure_events "$EVENT_ROWS"
  SR 05-brin-timeseries
done
unset SIZE_LABEL EVENT_ROWS

# ---- self-contained scenarios (own sweep dimension) ----
echo "== scenario 09 (unindexed FK), 10 (write amp), 11 (HOT) =="
SR 09-unindexed-fk
SR 10-write-amplification
SR 11-hot-update

echo "== regenerate charts =="
python3 charts/gen.py

echo "== done. Results in scenarios/NN-*/results.json, charts in charts/*.svg =="
