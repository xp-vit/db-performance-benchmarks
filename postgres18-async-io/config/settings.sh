#!/usr/bin/env bash
# Shared configuration for the async I/O benchmark sweep.
# Sourced by load.sh and the bench/*.sh drivers.

# ---- connection ----
export PGHOST=127.0.0.1
export PGPORT=5445
export PGUSER=postgres
export PGDATABASE=bench
export PGPASSWORD=bench
export COMPOSE_PROJECT="asyncio"
COMPOSE="docker compose"          # invoked from the suite root
CONTAINER="pgbench-asyncio"

# ---- dataset size (chosen for the 40G-free disk; ~9-12G on disk) ----
: "${BIG_ROWS:=30000000}"         # big multi-tenant table: 30M rows
: "${TENANTS:=500}"               # skewed multi-tenant distribution
: "${CUSTOMERS:=2000000}"         # related table
: "${LOAD_BATCH:=5000000}"        # rows per resumable load batch

# ---- the variable under test ----
# io_method: PGC_POSTMASTER -> requires container restart to change.
IO_METHODS=(sync worker io_uring)
# io_workers: only meaningful for io_method=worker (PGC_SIGHUP -> reload).
IO_WORKERS_SWEEP=(3 6 12)
# effective_io_concurrency: PGC_USERSET -> per-session SET, cheap to sweep.
EIC_SWEEP=(0 1 16 64 256)

# ---- run counts (variance) ----
: "${COLD_RUNS:=3}"               # each cold run = drop caches + restart PG + 1 op
: "${WARM_RUNS:=5}"               # warm runs reuse cache

# ---- paths ----
SUITE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RESULTS_DIR="$SUITE_ROOT/results"
RAW_DIR="$RESULTS_DIR/raw"
mkdir -p "$RAW_DIR"

export IO_METHODS IO_WORKERS_SWEEP EIC_SWEEP COLD_RUNS WARM_RUNS
export SUITE_ROOT RESULTS_DIR RAW_DIR COMPOSE CONTAINER
