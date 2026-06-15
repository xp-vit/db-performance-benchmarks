# Agent Instructions: db-performance-benchmarks

You are an engineering agent. Your job is to **write, run, and collect data from PostgreSQL benchmarks** that back the claims in a blog post. The output is real, reproducible numbers and charts. This repo is published on GitHub and linked from the post, so every number must survive a hostile reader cloning the repo and re-running it.

## What this repo is

A public benchmark suite. Each subfolder is one benchmark campaign tied to one blog post.

- `postgres-index/` — backs the flagship post **"Database Indexes That Actually Help (and the Ones Quietly Hurting You)"**. **This is your current target.** Start here.
- Future subfolders (`postgres-sharding/`, `redis-caching/`, `db-type-choice/`) come later. Ignore them for now.

The post draft lives in the sibling repo: `../patotski.com/src/data/post/database-indexing-that-actually-helps.md`. The full research/hypothesis matrix lives at `../patotski.com/content-research/DB-INDEX-MASTER-COVERAGE.md`. Read both before starting. The matrix has ~50 items spanning four future posts; **you only build the ~12 scenarios listed in `postgres-index/SCENARIOS.md`** (the subset that maps to the flagship post). Do not build the other 38.

## Hard constraints

1. **Run everything LOCALLY.** Docker + PostgreSQL on this box (32 cores, 93Gi RAM, local PG 18.4 available). **Do NOT spawn research sub-agents, do NOT invoke the `deep-research` skill, do NOT fan out parallel agents** — a prior fan-out hit the org monthly spend limit. All work here is shell + SQL + a chart script. Zero model fan-out.
2. **Pin the PostgreSQL version.** Use one Docker image tag (`postgres:18.x`, pick the exact patch and record it). Every result must name the exact version + image digest.
3. **Honest metrics — non-negotiable.** Report what the benchmark actually produced, including null results. If a hypothesis is wrong on modern PG (e.g. "hash index beats B-tree"), the post needs the real finding, not a faked confirmation. Never cherry-pick the one run that looked good. If a number depends on a caveat (cold cache, fresh VACUUM, specific row count), state the caveat next to the number.
4. **No invented data.** Every chart value traces to a committed `EXPLAIN (ANALYZE, BUFFERS)` and a committed results file. A reader must be able to reproduce it.

## Methodology (apply to every scenario)

- **Seed deterministically.** Use a fixed seed (`setseed()`, or a fixed-seed generator script) so the dataset is reproducible. Record row counts.
- **Dataset size:** large enough that the effect is real, not noise. Default 10M rows for the multi-tenant table; 100M for the BRIN/time-series scenario; size others per `SCENARIOS.md`. Document actual sizes.
- **Warm vs cold:** measure both where it matters. Cold = restart container / `pg_prewarm` off / drop OS cache where feasible. Warm = run the query 3× first. Label every number warm or cold.
- **Repeat:** N ≥ 10 timed runs per query. Report **p50 and p95** (and min if useful). Never report a single run.
- **Capture the plan:** commit `EXPLAIN (ANALYZE, BUFFERS)` output for the "before" and "after" of each scenario as a `.txt` file. Buffers matter as much as time (shared hit/read tells the I/O story).
- **Isolate:** run on a quiet box (nothing else heavy running). Note load in the methodology file.
- **ANALYZE** the tables before measuring, unless the scenario is specifically about stale statistics.
- **Record the config** that matters: `shared_buffers`, `work_mem`, `random_page_cost`, `effective_cache_size`. Keep them constant across a scenario's before/after unless the scenario is about a config knob.

## Per-scenario output (the contract)

For each of the 12 scenarios, produce a folder `postgres-index/scenarios/NN-short-name/` containing:

```
setup.sql          -- schema + index DDL for this scenario
seed.sql or seed.* -- data generation (or reference shared seed)
query.sql          -- the measured query/queries
run.sh             -- runs the scenario end-to-end, emits results
results.json       -- {scenario, pg_version, rows, runs, p50_ms, p95_ms, buffers, index_size_bytes, ...}
explain-before.txt -- EXPLAIN (ANALYZE, BUFFERS) without the optimization
explain-after.txt  -- EXPLAIN (ANALYZE, BUFFERS) with the optimization
NOTES.md           -- one-paragraph finding in plain English + any caveat + whether hypothesis held
```

Then a single chart per scenario (or per metric) as **brand-palette SVG** in `postgres-index/charts/NN-short-name.svg`.

## Chart style (match the blog brand)

SVG, `viewBox="0 0 1200 630"` for hero charts (or a sensible smaller box for inline). Inter font. Palette:

- bg: gradient `#0c1117` → `#11202b` (or transparent for inline; ask if unsure)
- primary teal: `#14b89c`  (the "good"/optimized bar)
- secondary teal: `#0d6e5f` / `#109882`
- accent amber: `#f59e0b`  (callout number)
- text: `#e7ece9` (headings) / `#c8d1cd` (body)
- muted: `#8aa0a8` (labels)
- gridline: `#2a3b44`
- **No em-dashes or en-dashes** in any chart text or label. Use `-`, `:`, or `&#8594;` for an arrow.

Generate charts from `results.json` with a small script (Python matplotlib → SVG, or hand-emitted SVG). Keep the generator in `postgres-index/charts/gen.*` so charts regenerate from data.

## Top-level files you must create

- `postgres-index/docker-compose.yml` — pinned PG18, tuned for the box, reproducible.
- `postgres-index/Makefile` or `run-all.sh` — one command to seed + run all scenarios + emit all results + regenerate all charts.
- `postgres-index/METHODOLOGY.md` — hardware, PG version + digest, config values, run count, cache handling, date. This is what a skeptic reads first.
- `postgres-index/README.md` — what the suite proves, how to run it, link back to the post.
- Root `README.md` — repo overview, list of campaigns, the honest-metrics statement.

## Workflow

1. Read the post draft + the master coverage doc + `postgres-index/SCENARIOS.md`.
2. Stand up `docker-compose.yml` with pinned PG18. Verify it boots.
3. Build the shared schema + seed (most scenarios share a few tables; see `SCENARIOS.md`).
4. Implement scenarios one at a time, lowest number first. Commit after each (data + explain + chart).
5. After all 12: write `METHODOLOGY.md`, regenerate all charts, write a `RESULTS-SUMMARY.md` with the 12 findings as a table (hypothesis, measured, held?).
6. Report back: which hypotheses held, which surprised, which charts are post-ready. **Do not edit the blog post** — the human folds charts in after reviewing the data.

## Reporting back

When done (or blocked), summarize: scenarios complete, the headline number from each, any hypothesis that did NOT hold (these are often the most valuable for the post), and the list of chart SVGs ready to embed. Flag anything where the real number is less dramatic than the draft post implies, so the copy can be corrected to stay honest.
