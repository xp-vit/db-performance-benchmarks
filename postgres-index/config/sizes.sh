#!/usr/bin/env bash
# Size sweep tiers (decision: full sweep, all 12 scenarios).
# Format "LABEL:ROWS". Override with QUICK=1 for a fast dev pass (small tiers only).

if [ "${QUICK:-0}" = "1" ]; then
  ORDER_TIERS=( "100k:100000" "300k:300000" )
  EVENT_TIERS=( "100k:100000" "1M:1000000" )
else
  ORDER_TIERS=( "1M:1000000" "3M:3000000" "10M:10000000" "30M:30000000" )
  EVENT_TIERS=( "1M:1000000" "10M:10000000" "100M:100000000" )
fi

# customers scale with orders (FK fan-out), floored so small tiers still have spread.
customers_for() {           # customers_for <orders_rows>
  local o="$1" c=$(( $1 / 10 ))
  [ "$c" -lt 50000 ] && c=$(( o < 50000 ? o : 50000 ))
  echo "$c"
}
