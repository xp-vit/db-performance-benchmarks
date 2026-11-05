#!/usr/bin/env python3
"""Cold-scan grouped bars from cold-scans.csv. Stdlib only.
Usage: python3 -I make_chart.py cold-scans.csv cold-scans.svg
"""
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1])))
M = ["sync", "worker", "io_uring"]; C = {"sync": "#8a8985", "worker": "#2a78d6", "io_uring": "#eb6834"}
get = lambda op, eic, m: next(r for r in rows if r["workload"] == op and r["effective_io_concurrency"] == str(eic) and r["io_method"] == m)
W, H, L, T, PH, GAP, YMAX = 760, 560, 64, 90, 160, 84, 18000
s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="system-ui,sans-serif" font-size="12">',
     '<style>text{fill:#222}.g{stroke:#e2e2e2}.m{fill:#666}@media (prefers-color-scheme:dark){text{fill:#eee}.g{stroke:#3a3a3a}.m{fill:#aaa}}</style>',
     '<text x="20" y="26" font-size="15" font-weight="600">PostgreSQL 18.4 cold scans, 30M rows: median execution time (lower is better)</text>',
     '<text class="m" x="20" y="46">Median of 3 cold runs per bar. Label = speedup vs sync. Ryzen 9 7950X3D, local NVMe (990 PRO).</text>']
for i, m in enumerate(M):
    s.append(f'<rect x="{W-250+i*80}" y="58" width="10" height="10" rx="2" fill="{C[m]}"/><text x="{W-236+i*80}" y="67">{m}</text>')
for p, op in enumerate(["seqscan", "bitmap"]):
    top = T + 10 + p * (PH + GAP); by = top + PH
    s.append(f'<text x="20" y="{top-10}" font-weight="600">Cold {"sequential scan" if op == "seqscan" else "bitmap heap scan (~5% scattered rows)"}</text>')
    for t in range(0, YMAX + 1, 4000):
        y = by - t / YMAX * PH
        s.append(f'<line class="g" x1="{L}" x2="{W-20}" y1="{y:.1f}" y2="{y:.1f}"/><text class="m" x="{L-6}" y="{y+4:.1f}" text-anchor="end">{t//1000} s</text>')
    gw = (W - 20 - L) / 3
    for g, eic in enumerate([1, 16, 64]):
        gx = L + g * gw; bw = 36; x0 = gx + gw / 2 - (3 * bw + 4) / 2
        s.append(f'<text x="{gx+gw/2:.1f}" y="{by+18}" text-anchor="middle">effective_io_concurrency = {eic}</text>')
        for i, m in enumerate(M):
            r = get(op, eic, m); ms = float(r["median_exec_ms"]); h = ms / YMAX * PH; x = x0 + i * (bw + 2)
            s.append(f'<rect x="{x:.1f}" y="{by-h:.1f}" width="{bw}" height="{h:.1f}" fill="{C[m]}"/>')
            s.append(f'<text x="{x+bw/2:.1f}" y="{by-h-4:.1f}" text-anchor="middle" font-size="11">{r["speedup_vs_sync"]}x</text>')
s.append("</svg>")
open(sys.argv[2], "w").write("\n".join(s) + "\n")
print(sys.argv[2], len(rows), "rows")
