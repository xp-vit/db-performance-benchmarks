# Reproduce

Local verify (free, no root), from `postgres18-async-io/` on branch `hq/pg18-async-io-results`:

    python3 make_charts.py

It recomputes the cold-scan table from `results/raw/*.jsonl`. The chart from the CSV: `python3 -I lab-entry/make_chart.py lab-entry/cold-scans.csv cold-scans.svg`.

Full re-run is local (0 EUR). It needs Linux, Docker Compose, root for `drop_caches`, ~12 GB disk:

    ./load.sh && ./bench/run-warm.sh && sudo -v && ./bench/run-cold.sh && python3 aggregate.py

Note: `bench/run-cold.sh` writes `mb_per_s` with a truncation bug (up to +5%). Use the recomputed MB/s.
