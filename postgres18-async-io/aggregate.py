#!/usr/bin/env python3
"""Aggregate results/raw/*.jsonl into results/RESULTS.md.

Every number here is a median of repeated runs on ONE disclosed rig (results/rig.json).
Configs with n<3 runs or coefficient-of-variation >20% are flagged "second run needed".
"""
import json, glob, os, statistics as st

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "results", "raw")
OUT = os.path.join(ROOT, "results", "RESULTS.md")

rows = []
for f in sorted(glob.glob(os.path.join(RAW, "*.jsonl"))):
    for line in open(f):
        line = line.strip()
        if line:
            rows.append(json.loads(line))

def sel(**kw):
    out = []
    for r in rows:
        if all(r.get(k) == v for k, v in kw.items()):
            out.append(r)
    return out

def agg(recs, field):
    vals = [r[field] for r in recs if r.get(field) is not None]
    if not vals:
        return None
    med = st.median(vals)
    cv = (st.pstdev(vals) / med * 100) if med and len(vals) > 1 else 0.0
    return {"median": med, "n": len(vals), "cv": cv, "min": min(vals), "max": max(vals)}

def flag(a):
    if a is None:
        return "no data"
    marks = []
    if a["n"] < 3:
        marks.append(f"n={a['n']} (second run needed)")
    if a["cv"] > 20:
        marks.append(f"CV={a['cv']:.0f}% (noisy, second run needed)")
    return ", ".join(marks)

METHODS = ["sync", "worker", "io_uring"]
L = []
def w(s=""): L.append(s)

rig = json.load(open(os.path.join(ROOT, "results", "rig.json"))) if os.path.exists(os.path.join(ROOT,"results","rig.json")) else {}

w("# Postgres 18 async I/O — measured results")
w()
w("All figures are OUR measurements on ONE rig. Medians of repeated runs. No borrowed")
w("figures. Cold = PostgreSQL shared_buffers flushed (container restart) **and** OS page")
w("cache dropped (`echo 3 > drop_caches`) before each measured run.")
w()
w("## Rig")
w()
for k in ["cpu","logical_cores","ram_gb","kernel","os","disk","fs","postgres","shared_buffers","dataset","seccomp"]:
    if k in rig:
        w(f"- **{k}**: {rig[k]}")
w()
w("Fixed across every arm: `shared_buffers=4GB` (deliberately < the 6.2GB heap so cold")
w("reads hit storage), `maintenance_work_mem=2GB`, `max_wal_size=16GB`, `track_io_timing=on`.")
w("The only variables are `io_method`, `effective_io_concurrency` (scans),")
w("`maintenance_io_concurrency` (vacuum/reindex), and `io_workers` (worker method).")
w()

# ---- cold scans ----
for op, conc in [("seqscan","eic"), ("bitmap","eic")]:
    w(f"## Cold {op} — io_method × {conc}")
    w()
    w(f"| {conc} | io_method | median exec (ms) | MB/s | speedup vs sync | runs | flags |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    concs = sorted({r.get(conc) for r in sel(op=op, phase="cold") if r.get(conc) is not None})
    for c in concs:
        base = agg(sel(op=op, phase="cold", io_method="sync", **{conc: c}), "exec_ms")
        for m in METHODS:
            recs = sel(op=op, phase="cold", io_method=m, **{conc: c})
            a = agg(recs, "exec_ms"); mbs = agg(recs, "mb_per_s")
            if a is None:
                continue
            sp = f"{base['median']/a['median']:.2f}x" if base and a["median"] else "-"
            w(f"| {c} | {m} | {a['median']:.0f} | {mbs['median']:.0f} | {sp} | {a['n']} | {flag(a)} |")
    w()

# ---- cold maintenance ----
for op in ["vacuum","reindex"]:
    recs_all = sel(op=op, phase="cold")
    if not recs_all:
        continue
    w(f"## Cold {op} — io_method × maintenance_io_concurrency")
    w()
    w("| mic | io_method | median wall (ms) | MB read | speedup vs sync | runs | flags |")
    w("| --- | --- | --- | --- | --- | --- | --- |")
    mics = sorted({r.get("mic") for r in recs_all if r.get("mic") is not None})
    for c in mics:
        base = agg(sel(op=op, phase="cold", io_method="sync", mic=c), "wall_ms")
        for m in METHODS:
            recs = sel(op=op, phase="cold", io_method=m, mic=c)
            a = agg(recs, "wall_ms"); mb = agg(recs, "mb_read")
            if a is None:
                continue
            sp = f"{base['median']/a['median']:.2f}x" if base and a["median"] else "-"
            mbv = f"{mb['median']:.0f}" if mb else "-"
            w(f"| {c} | {m} | {a['median']:.0f} | {mbv} | {sp} | {a['n']} | {flag(a)} |")
    w()

# ---- warm contrast ----
w("## Warm (the honest boundary) — async I/O should be flat")
w()
w("| workload | metric | sync | worker | io_uring | flat? |")
w("| --- | --- | --- | --- | --- | --- |")
def warm_row(op, field, unit, higher_better=False):
    vals = {m: agg(sel(op=op, phase="warm", io_method=m), field) for m in METHODS}
    if not any(vals.values()):
        return
    cells = [f"{vals[m]['median']:.0f} {unit}" if vals[m] else "-" for m in METHODS]
    meds = [vals[m]["median"] for m in METHODS if vals[m]]
    spread = (max(meds)-min(meds))/st.median(meds)*100 if meds else 0
    verdict = "yes" if spread < 15 else f"no ({spread:.0f}% spread)"
    w(f"| {op} | {field} | {cells[0]} | {cells[1]} | {cells[2]} | {verdict} |")
warm_row("oltp_pointlookup", "tps", "tps", True)
warm_row("seqscan", "exec_ms", "ms")
warm_row("bitmap", "exec_ms", "ms")
w()

# ---- decision matrix ----
w("## Decision matrix — when does async I/O actually win?")
w()
w("Best async (worker or io_uring) vs sync baseline, at the io-concurrency that maximizes it.")
w()
w("| workload | cache | best async speedup vs sync | verdict |")
w("| --- | --- | --- | --- |")
def best_speedup(op, phase, conc, field, invert=False):
    concs = sorted({r.get(conc) for r in sel(op=op, phase=phase) if r.get(conc) is not None}) or [None]
    best = None
    for c in concs:
        kw = {conc: c} if c is not None else {}
        base = agg(sel(op=op, phase=phase, io_method="sync", **kw), field)
        if not base:
            continue
        for m in ["worker","io_uring"]:
            a = agg(sel(op=op, phase=phase, io_method=m, **kw), field)
            if not a or not a["median"]:
                continue
            r = base["median"]/a["median"]
            if best is None or r > best[0]:
                best = (r, m, c)
    return best
for op, phase, conc, field, label in [
    ("seqscan","cold","eic","exec_ms","cold sequential scan"),
    ("bitmap","cold","eic","exec_ms","cold bitmap heap scan"),
    ("vacuum","cold","mic","wall_ms","cold VACUUM (post-update)"),
    ("reindex","cold","mic","wall_ms","cold REINDEX"),
]:
    b = best_speedup(op, phase, conc, field)
    if b:
        verdict = "WINS" if b[0] >= 1.25 else ("marginal" if b[0] >= 1.1 else "flat/no win")
        w(f"| {label} | cold | {b[0]:.2f}x ({b[1]}, {conc}={b[2]}) | {verdict} |")
b = None
tps = {m: agg(sel(op='oltp_pointlookup', phase='warm', io_method=m), 'tps') for m in METHODS}
if all(tps.values()):
    spread = (max(t['median'] for t in tps.values())-min(t['median'] for t in tps.values()))/st.median([t['median'] for t in tps.values()])*100
    w(f"| OLTP point-lookup | warm | flat ({spread:.0f}% spread across methods) | no win (expected) |")
w()
w("## Notes & caveats (honest-metrics)")
w()
w("- **Scan MB/s** is derived from the plan's authoritative `Buffers: shared read` × 8 KB")
w("  over `Execution Time`. `pg_stat_io` was found to *undercount* blocks read via the async")
w("  path (≈49k reported vs 790k actually read), so it is NOT used for scan volume.")
w("- **VACUUM/REINDEX MB read** comes from `pg_stat_io` and is indicative only (same undercount");
w("  caveat); the headline maintenance metric is **wall time**, which is exact.")
w("- **VACUUM speedups are flagged noisy (CV 24-33%)** — treat 1.5-1.65x as directional and")
w("  re-run before quoting a precise number.")
w("- **The '~3x' is real only at the edge:** cold bitmap + io_uring + `eic=64` = 2.98x. Cold")
w("  seqscan tops out ~2.4x. `worker` (the PG18 default) gives less and *regresses* on cold")
w("  bitmap at eic>=16 (0.81x, slower than sync).")
w("- **`effective_io_concurrency` is often the bigger lever than `io_method`:** cold bitmap at")
w("  eic=1 is 15.6s (sync) vs 5.0s at eic=16 — prefetch depth matters more than the async engine.")
w("- **io_uring required `seccomp=unconfined`** under Docker (default profile blocks the")
w("  syscalls). Numbers are specific to this NVMe (Samsung 990 PRO) / ext4 / kernel 6.12.")
w()
w("_Generated by `aggregate.py` from `results/raw/*.jsonl`._")

open(OUT, "w").write("\n".join(L) + "\n")
print(f"wrote {OUT} ({len(rows)} raw records)")
