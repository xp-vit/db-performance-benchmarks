#!/usr/bin/env python3
"""Generate brand-palette SVG charts from each scenario's results.json.

Hand-emitted SVG (no matplotlib) so the brand palette, Inter font, gradient
background and the no-dash rule are exact. One chart (or a few) per scenario.
Re-runs deterministically from committed results.json.
"""
import json, os, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCEN = os.path.join(ROOT, "scenarios")
OUT  = os.path.join(ROOT, "charts")

# ---- brand palette ----
BG1, BG2   = "#0c1117", "#11202b"
TEAL       = "#14b89c"   # optimized / good
TEAL2      = "#0d6e5f"
TEAL3      = "#109882"
AMBER      = "#f59e0b"   # callout
TXT        = "#e7ece9"
BODY       = "#c8d1cd"
MUTED      = "#8aa0a8"
GRID       = "#2a3b44"
RED        = "#c65b5b"   # "bad" bar (kept off-brand-warm, still muted)
W, H       = 1200, 630
PADL, PADR, PADT, PADB = 90, 60, 110, 90

def _load(name):
    p = os.path.join(SCEN, name, "results.json")
    if not os.path.exists(p): return None
    with open(p) as f:
        try: return json.load(f)
        except Exception: return None

def esc(s):  # no em/en dashes anywhere in labels
    return str(s).replace("—", "-").replace("–", "-").replace("&", "&amp;").replace("<", "&lt;")

def fmtv(v):  # human-readable, never scientific notation, thousands separators
    if v is None: return "-"
    a = abs(v)
    if a == 0:        return "0"
    if a >= 1000:     return f"{v:,.0f}"
    if a >= 100:      return f"{v:.0f}"
    if a >= 10:       return f"{v:.1f}".rstrip("0").rstrip(".")
    if a >= 1:        return f"{v:.2f}".rstrip("0").rstrip(".")
    if a >= 0.01:     return f"{v:.3f}".rstrip("0").rstrip(".")
    return f"{v:.4f}".rstrip("0").rstrip(".")

def _fmt(value_fmt, v):  # value_fmt may be a callable or a str format spec
    return value_fmt(v) if callable(value_fmt) else value_fmt.format(v)

def _gridlines(yv, allv, vmax, x0, x1, y0, y1, log):
    # log axes get one labelled line per decade so the chart reads as log,
    # not as a linear chart whose bars look out of proportion.
    s = ""
    if log:
        dmin = int(math.floor(math.log10(min(allv))))
        dmax = int(math.ceil(math.log10(vmax)))
        for d in range(dmin, dmax + 1):
            gy = yv(10.0 ** d)
            if gy < y0 - 1 or gy > y1 + 1: continue
            s += f'<line x1="{x0}" y1="{gy:.1f}" x2="{x1}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="1"/>'
            s += f'<text x="{x0-8:.1f}" y="{gy+4:.1f}" fill="{MUTED}" font-size="11" text-anchor="end">{fmtv(10.0**d)}</text>'
    else:
        for i in range(5):
            gy = y0 + (y1 - y0) * i / 4
            s += f'<line x1="{x0}" y1="{gy:.1f}" x2="{x1}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="1"/>'
    return s

def head(title, subtitle):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" font-family="Inter, system-ui, sans-serif">
<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{BG1}"/><stop offset="1" stop-color="{BG2}"/></linearGradient></defs>
<rect width="{W}" height="{H}" fill="url(#bg)"/>
<text x="{PADL}" y="52" fill="{TXT}" font-size="30" font-weight="700">{esc(title)}</text>
<text x="{PADL}" y="82" fill="{MUTED}" font-size="17">{esc(subtitle)}</text>'''

def foot(note=""):
    n = f'<text x="{PADL}" y="{H-22}" fill="{MUTED}" font-size="13">{esc(note)}</text>' if note else ""
    return n + "\n</svg>"

def save(name, body):
    with open(os.path.join(OUT, name), "w") as f: f.write(body)
    print("wrote", name)

# ---- generic grouped bar chart (linear or log) ----
def grouped_bars(title, subtitle, groups, series, note="", log=False, unit="ms", value_fmt=fmtv):
    # groups: list of group labels (x). series: list of (label,color,[values per group])
    x0, x1 = PADL, W - PADR
    y0, y1 = PADT, H - PADB
    allv = [v for _,_,vals in series for v in vals if v is not None and v > 0]
    if not allv: return head(title, subtitle) + foot("no data")
    vmax = max(allv)
    def yv(v):
        if v is None or v <= 0: v = (min(allv) if log else 0) or 1e-6
        if log:
            lo = math.log10(min(allv)); hi = math.log10(vmax)
            if hi - lo < 0.5: hi = lo + 1
            lo -= (hi - lo) * 0.12  # baseline headroom so the smallest bar stays visible
            return y1 - (y1 - y0) * (math.log10(max(v, min(allv))) - lo) / (hi - lo)
        return y1 - (y1 - y0) * (v / (vmax * 1.12))
    s = head(title, subtitle)
    s += _gridlines(yv, allv, vmax, x0, x1, y0, y1, log)
    ng = len(groups); ns = len(series)
    gw = (x1 - x0) / ng
    bw = gw * 0.74 / ns
    for gi, g in enumerate(groups):
        gx = x0 + gw * gi + gw * 0.13
        for si, (lbl, col, vals) in enumerate(series):
            v = vals[gi]
            bx = gx + bw * si
            by = yv(v); bh = y1 - by
            if v is None: continue
            s += f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw*0.92:.1f}" height="{bh:.1f}" rx="3" fill="{col}"/>'
            if v and v > 0:
                s += f'<text x="{bx+bw*0.46:.1f}" y="{by-7:.1f}" fill="{BODY}" font-size="12" text-anchor="middle">{_fmt(value_fmt, v)}</text>'
        s += f'<text x="{gx+ (bw*ns)/2:.1f}" y="{y1+26:.1f}" fill="{BODY}" font-size="15" text-anchor="middle">{esc(g)}</text>'
    # legend
    lx = x0
    for lbl, col, _ in series:
        s += f'<rect x="{lx}" y="{H-58}" width="14" height="14" rx="2" fill="{col}"/>'
        s += f'<text x="{lx+20}" y="{H-46}" fill="{BODY}" font-size="14">{esc(lbl)}</text>'
        lx += 40 + len(lbl) * 8.5
    s += f'<text x="{x0-12}" y="{y0-12}" fill="{MUTED}" font-size="13" text-anchor="start">{esc(unit)}{" (log)" if log else ""}</text>'
    return s + foot(note)

# ---- single-series bar (e.g. sizes, hot rate) ----
def simple_bars(title, subtitle, labels, values, colors, note="", unit="", value_fmt=fmtv, log=False):
    return grouped_bars(title, subtitle, labels,
                        [("", None, None)] and [(unit, c, [v]) for c, v in []] or
                        [("v", TEAL, values)], note, log, unit, value_fmt) if False else \
        _simple(title, subtitle, labels, values, colors, note, unit, value_fmt, log)

def _simple(title, subtitle, labels, values, colors, note="", unit="", value_fmt=fmtv, log=False):
    x0, x1 = PADL, W - PADR; y0, y1 = PADT, H - PADB
    vv = [v for v in values if v and v > 0]
    if not vv: return head(title, subtitle) + foot("no data")
    vmax = max(vv)
    def yv(v):
        if not v or v <= 0: return y1
        if log:
            lo = math.log10(min(vv)); hi = math.log10(vmax)
            if hi-lo < 0.5: hi = lo+1
            lo -= (hi - lo) * 0.12  # baseline headroom so the smallest bar stays visible
            return y1-(y1-y0)*(math.log10(v)-lo)/(hi-lo)
        return y1-(y1-y0)*(v/(vmax*1.12))
    s = head(title, subtitle)
    s += _gridlines(yv, vv, vmax, x0, x1, y0, y1, log)
    n = len(labels); gw = (x1-x0)/n; bw = gw*0.6
    for i,(lab,v) in enumerate(zip(labels, values)):
        bx = x0+gw*i+(gw-bw)/2; by=yv(v); bh=y1-by
        col = colors[i] if i < len(colors) else TEAL
        s += f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="{bh:.1f}" rx="3" fill="{col}"/>'
        s += f'<text x="{bx+bw/2:.1f}" y="{by-8:.1f}" fill="{BODY}" font-size="13" text-anchor="middle">{_fmt(value_fmt, v) if v else "-"}</text>'
        s += f'<text x="{bx+bw/2:.1f}" y="{y1+26:.1f}" fill="{BODY}" font-size="14" text-anchor="middle">{esc(lab)}</text>'
    s += f'<text x="{x0-12}" y="{y0-12}" fill="{MUTED}" font-size="13">{esc(unit)}{" (log)" if log else ""}</text>'
    return s + foot(note)

# ---- line chart (curves) ----
def line_chart(title, subtitle, xlabels, series, note="", unit="ms", log=False, xtitle="", value_fmt=fmtv):
    # series: list of (label,color,[y values aligned to xlabels])
    x0,x1=PADL,W-PADR; y0,y1=PADT,H-PADB
    allv=[v for _,_,ys in series for v in ys if v is not None and v>0]
    if not allv: return head(title,subtitle)+foot("no data")
    vmax=max(allv); vmin=min(allv)
    def yv(v):
        if v is None or v<=0: v=vmin
        if log:
            lo=math.log10(vmin); hi=math.log10(vmax)
            if hi-lo<0.5: hi=lo+1
            return y1-(y1-y0)*(math.log10(max(v,vmin))-lo)/(hi-lo)
        return y1-(y1-y0)*(v/(vmax*1.12))
    n=len(xlabels)
    def xv(i): return x0+(x1-x0)*(i/(max(n-1,1)))
    s=head(title,subtitle)
    s += _gridlines(yv, allv, vmax, x0, x1, y0, y1, log)
    for i,lab in enumerate(xlabels):
        s+=f'<text x="{xv(i):.1f}" y="{y1+26:.1f}" fill="{BODY}" font-size="14" text-anchor="middle">{esc(lab)}</text>'
    for lbl,col,ys in series:
        pts=[]
        for i,v in enumerate(ys):
            if v is None: continue
            pts.append(f"{xv(i):.1f},{yv(v):.1f}")
        if pts:
            s+=f'<polyline points="{" ".join(pts)}" fill="none" stroke="{col}" stroke-width="3"/>'
            for i,v in enumerate(ys):
                if v is None: continue
                s+=f'<circle cx="{xv(i):.1f}" cy="{yv(v):.1f}" r="4" fill="{col}"/>'
    lx=x0
    for lbl,col,_ in series:
        s+=f'<rect x="{lx}" y="{H-58}" width="14" height="14" rx="2" fill="{col}"/>'
        s+=f'<text x="{lx+20}" y="{H-46}" fill="{BODY}" font-size="14">{esc(lbl)}</text>'
        lx+=40+len(lbl)*8.5
    s+=f'<text x="{x0-12}" y="{y0-12}" fill="{MUTED}" font-size="13">{esc(unit)}{" (log)" if log else ""}</text>'
    if xtitle: s+=f'<text x="{(x0+x1)/2:.0f}" y="{H-46}" fill="{MUTED}" font-size="13" text-anchor="middle">{esc(xtitle)}</text>'
    return s+foot(note)

def by_size(rows):
    """ordered unique size labels as they appear"""
    seen=[]
    for r in rows:
        if r.get("size_label") not in seen: seen.append(r["size_label"])
    return seen

# ============================ per-scenario ============================
def chart_01():
    d=_load("01-composite-order");
    if not d: return
    sizes=by_size(d)
    def val(size,variant):
        return next((r["p50_ms"] for r in d if r["size_label"]==size and r["variant"]==variant), None)
    series=[("no index (Seq Scan + Sort)", RED, [val(s,"baseline") for s in sizes]),
            ("wrong order", AMBER, [val(s,"wrong") for s in sizes]),
            ("right order", TEAL, [val(s,"right") for s in sizes])]
    save("01-composite-order.svg", grouped_bars(
        "Composite column order: latency vs table size",
        "WHERE tenant_id=? AND status=? ORDER BY created_at DESC LIMIT 20  -  p50, warm cache, log scale",
        sizes, series, log=True, unit="ms",
        note="Right order = (tenant_id, status, created_at DESC). On PG18 the wrong order still scans the index in created_at order (no Sort)."))

def chart_02():
    d=_load("02-covering-include")
    if not d: return
    sizes=by_size(d)
    def val(size,variant,k): return next((r[k] for r in d if r["size_label"]==size and r["variant"]==variant), None)
    series=[("plain index (heap fetch)", AMBER, [val(s,"plain","buffers_total") for s in sizes]),
            ("INCLUDE (index-only)", TEAL, [val(s,"include","buffers_total") for s in sizes])]
    save("02-covering-include.svg", grouped_bars(
        "Covering index: shared buffers touched",
        "SELECT sum(amount_cents) WHERE tenant_id=? AND status=?  -  buffers, log scale",
        sizes, series, log=True, unit="buffers", value_fmt=fmtv,
        note="INCLUDE (amount_cents) turns Index Scan + heap fetch into Index Only Scan."))

def chart_03():
    d=_load("03-covering-visibility-map")
    if not d: return
    # use the largest size
    sizes=by_size(d); big=sizes[-1]
    rows=[r for r in d if r["size_label"]==big]
    order=["post-vacuum","post-update","post-revacuum"]
    labs=["post-VACUUM","post mass-UPDATE","post re-VACUUM"]
    vals=[next((r["heap_fetches"] for r in rows if r["state"]==st),0) for st in order]
    cols=[TEAL, RED, TEAL]
    save("03-covering-visibility-map.svg", _simple(
        "Covering index caveat: Heap Fetches track the visibility map",
        f"Index Only Scan, {big} rows  -  Heap Fetches per query across VM states",
        labs, vals, cols, unit="heap fetches", value_fmt=fmtv,
        note="An index-only scan stays heap-free only while VACUUM keeps the visibility map current."))

def chart_04():
    d=_load("04-gin-jsonb")
    if not d: return
    sizes=by_size(d)
    def g(s,pred,k): return next((r[pred][k] for r in d if r["size_label"]==s), None)
    # rare predicate (~0.02%) is the dramatic, selectivity-driven win
    series=[("Seq Scan", RED, [g(s,"rare","seq_p50_ms") for s in sizes]),
            ("GIN jsonb_path_ops", TEAL, [g(s,"rare","gin_p50_ms") for s in sizes])]
    big=sizes[-1]
    mod_sp=g(big,"moderate","speedup"); rare_sp=g(big,"rare","speedup")
    save("04-gin-jsonb.svg", grouped_bars(
        "GIN on jsonb vs sequential scan (rare predicate, ~0.02% of rows)",
        "WHERE payload @> '{\"sku\":\"RARE-NEEDLE\"}'  -  p50, log scale",
        sizes, series, log=True, unit="ms",
        note="GIN's win is selectivity-driven: %.0fx on this rare needle at %s, but only %.1fx on a ~1%% predicate." % (
            (rare_sp or 0), big, (mod_sp or 0))))

def chart_05():
    d=_load("05-brin-timeseries")
    if not d: return
    sizes=by_size(d)
    # size chart
    series=[("B-tree", AMBER, [next((r["btree_bytes"]/1048576 for r in d if r["size_label"]==s),None) for s in sizes]),
            ("BRIN", TEAL, [next((r["brin_bytes"]/1048576 for r in d if r["size_label"]==s),None) for s in sizes])]
    save("05-brin-size.svg", grouped_bars(
        "BRIN vs B-tree index size on a time-ordered table",
        "index on events(ts)  -  megabytes, log scale",
        sizes, series, log=True, unit="MB", value_fmt=fmtv,
        note="BRIN stores min/max per block range, not per row."))
    # latency ordered vs shuffled
    series2=[("Seq Scan", RED, [next((r["seqscan_ordered_p50_ms"] for r in d if r["size_label"]==s),None) for s in sizes]),
             ("BRIN, ordered", TEAL, [next((r["brin_ordered_p50_ms"] for r in d if r["size_label"]==s),None) for s in sizes]),
             ("BRIN, shuffled", AMBER, [next((r["brin_shuffled_p50_ms"] for r in d if r["size_label"]==s),None) for s in sizes])]
    save("05-brin-latency.svg", grouped_bars(
        "BRIN range scan: ordered data vs shuffled data",
        "0.5% time-window range scan  -  p50, log scale",
        sizes, series2, log=True, unit="ms",
        note="On shuffled (low-correlation) data the planner abandons BRIN and the scan collapses toward seq-scan time."))

def chart_06():
    d=_load("06-type-index-size")
    if not d: return
    big=by_size(d)[-1]
    r=next((x for x in d if x["size_label"]==big), None)
    if not r: return
    sz=r["index_size_bytes"]
    order=["status_smallint","status_enum","status_vc_short","status_vc_long","key_bigint","key_uuid4","key_uuid7"]
    labs=["smallint","enum","varchar short","varchar long","bigint","uuid v4","uuid v7"]
    vals=[sz[k]/1048576 for k in order]
    cols=[TEAL3,TEAL3,TEAL3,TEAL,AMBER,RED,TEAL2]
    save("06-type-index-size.svg", _simple(
        "Index size by column type",
        f"one index per column, {big} rows  -  megabytes",
        labs, vals, cols, unit="MB", value_fmt=fmtv,
        note="Low-cardinality status columns dedup to the same size; uuid vs bigint is the real gap (per-tuple overhead dilutes it below 2x)."))

def chart_07():
    d=_load("07-index-ignored")
    if not d: return
    big=by_size(d)[-1]
    r=next((x for x in d if x["size_label"]==big), None)
    if not r: return
    save("07-index-ignored.svg", grouped_bars(
        "Why the index was ignored: function wrap and implicit cast",
        f"{big} rows  -  p50, log scale",
        ["WHERE lower(email)=$1","WHERE id='42'"],
        [("index ignored", RED, [r["a_lower_plain_p50_ms"], r["b_cast_p50_ms"]]),
         ("correct index used", TEAL, [r["a_lower_expr_p50_ms"], r["b_typed_p50_ms"]])],
        log=True, unit="ms",
        note="Left: plain email index vs expression index on lower(email). Right: '42'::numeric forces a per-row cast + Seq Scan."))

def chart_08():
    d=_load("08-trigram-like")
    if not d: return
    sizes=by_size(d)
    series=[("Seq Scan", RED, [next((r["seqscan_p50_ms"] for r in d if r["size_label"]==s),None) for s in sizes]),
            ("trigram GIN", TEAL, [next((r["trigram_p50_ms"] for r in d if r["size_label"]==s),None) for s in sizes])]
    save("08-trigram-like.svg", grouped_bars(
        "Leading-wildcard LIKE: seq scan vs trigram GIN",
        "WHERE search_text LIKE '%term%'  -  p50, log scale",
        sizes, series, log=True, unit="ms",
        note="A B-tree cannot serve a leading wildcard; a pg_trgm GIN index turns the full scan into a lookup."))

def chart_09():
    d=_load("09-unindexed-fk")
    if not d: return
    sizes=by_size(d); big=sizes[-1]
    rows=[r for r in d if r["size_label"]==big]
    ns=sorted({r["delete_n"] for r in rows})
    def curve(variant): return [next((r["delete_ms"] for r in rows if r["variant"]==variant and r["delete_n"]==n), None) for n in ns]
    save("09-unindexed-fk.svg", line_chart(
        "Unindexed foreign key: cascade delete cost",
        f"child table {big} rows  -  delete time vs number of parents deleted, log scale",
        [str(n) for n in ns],
        [("no index on FK (O(n^2))", RED, curve("noindex")),
         ("FK indexed (flat)", TEAL, curve("indexed"))],
        log=True, unit="ms", xtitle="parents deleted (cascading)",
        note="Without an index on child(parent_id) each parent delete seq-scans the whole child table."))

def chart_10():
    d=_load("10-write-amplification")
    if not d: return
    d=sorted(d, key=lambda r:r["index_count"])
    ks=[r["index_count"] for r in d]
    rps=[r["rows_per_sec"] for r in d]
    wal=[r["wal_bytes"]/1048576 for r in d]
    save("10-write-amplification.svg", line_chart(
        "Write amplification: insert throughput vs number of indexes",
        "bulk insert  -  rows/sec (higher is better)",
        [str(k) for k in ks],
        [("rows/sec", TEAL, rps)],
        unit="rows/sec", value_fmt=fmtv, xtitle="number of indexes on the table",
        note="WAL generated grows in step: %0.0f MB at 0 indexes to %0.0f MB at %d indexes." % (wal[0], wal[-1], ks[-1])))
    save("10-write-amp-wal.svg", line_chart(
        "Write amplification: WAL generated vs number of indexes",
        "bulk insert  -  WAL megabytes (lower is better)",
        [str(k) for k in ks], [("WAL MB", AMBER, wal)],
        unit="MB", value_fmt=fmtv, xtitle="number of indexes on the table"))

def chart_11():
    d=_load("11-hot-update")
    if not d: return
    order=["no_index_ff100","no_index_ff70","indexed_ff100","indexed_ff70"]
    labs=["no index ff100","no index ff70","indexed ff100","indexed ff70"]
    vals=[next((r["hot_pct"] for r in d if r["config"]==c),0) for c in order]
    cols=[TEAL3,TEAL,RED,RED]
    save("11-hot-update.svg", _simple(
        "HOT update rate: indexing a hot column vs fillfactor",
        "repeated UPDATE of column h  -  percent of updates that stayed HOT",
        labs, vals, cols, unit="% HOT", value_fmt=fmtv,
        note="Fillfactor restores HOT only when the updated column is NOT indexed; indexing it blocks HOT at any fillfactor."))

def chart_12():
    d=_load("12-partial-index")
    if not d: return
    sizes=by_size(d)
    series=[("full: (status, created_at), all rows", AMBER, [next((r["full_index_bytes"]/1048576 for r in d if r["size_label"]==s),None) for s in sizes]),
            ("partial: same columns, WHERE status='pending'", TEAL, [next((r["partial_index_bytes"]/1048576 for r in d if r["size_label"]==s),None) for s in sizes])]
    save("12-partial-index.svg", grouped_bars(
        "Partial index vs full index size",
        "hot slice is ~5% of rows (status='pending')  -  megabytes",
        sizes, series, log=False, unit="MB", value_fmt=fmtv,
        note="The partial index is a fraction of the full size and at least as fast; the planner only uses it when the predicate matches."))

def chart_13():
    d=_load("13-bigint-phone-like")
    if not d: return
    sizes=by_size(d)
    series=[("bigint + cast (Seq Scan)",        RED,   [next((r["a_bigint_p50_ms"]        for r in d if r["size_label"]==s),None) for s in sizes]),
            ("varchar, plain index (Seq Scan)",  AMBER, [next((r["b_varchar_plain_p50_ms"]  for r in d if r["size_label"]==s),None) for s in sizes]),
            ("varchar, text_pattern_ops",        TEAL,  [next((r["c_pattern_ops_p50_ms"]     for r in d if r["size_label"]==s),None) for s in sizes])]
    save("13-bigint-phone-like.svg", grouped_bars(
        "Prefix phone search: column type vs the index",
        "WHERE phone LIKE '150000%'  -  p50, warm cache, log scale",
        sizes, series, log=True, unit="ms",
        note="bigint forces a per-row cast; a non-C plain text index still cannot serve LIKE; text_pattern_ops can."))

for fn in [chart_01,chart_02,chart_03,chart_04,chart_05,chart_06,chart_07,chart_08,chart_09,chart_10,chart_11,chart_12,chart_13]:
    try: fn()
    except Exception as e: print("WARN", fn.__name__, e)
