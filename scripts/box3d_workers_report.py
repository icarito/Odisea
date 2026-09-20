#!/usr/bin/env python3
"""Reporte del benchmark de Box3D workers para el workflow Stress & Performance.

Lee reports/box3d_workers_*.json (uno por worker count), escribe
box3d_workers_current.json, imprime una tabla y la agrega al step summary.
Si existe box3d_workers_baseline.json (artifact de la corrida previa) reporta
el delta del speedup, para seguir la evolucion sin romper por ruido de CI.
"""
import glob
import json
import os
import sys


def main() -> int:
    rows = []
    for path in sorted(glob.glob("reports/box3d_workers_*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                rows.append(json.load(f))
        except Exception as exc:  # noqa: BLE001
            print("warn: no pude leer %s: %s" % (path, exc), file=sys.stderr)
    if not rows:
        print("ERROR: no hay resultados de box3d_workers_bench", file=sys.stderr)
        return 1
    rows.sort(key=lambda r: r.get("workers", 0))

    current = {"metrics": rows}
    base = next((r for r in rows if r.get("workers") == 1), rows[0])
    top = next((r for r in rows if r.get("workers") != 1), rows[-1])
    if base.get("phys_avg_ms", 0) > 0:
        current["speedup"] = round(base["phys_avg_ms"] / top["phys_avg_ms"], 3)

    with open("box3d_workers_current.json", "w", encoding="utf-8") as f:
        json.dump(current, f, indent=2)
        f.write("\n")

    delta = ""
    try:
        with open("box3d_workers_baseline.json", encoding="utf-8") as f:
            previous = json.load(f)
        if "speedup" in previous and "speedup" in current:
            delta = " (baseline previo: %.3f)" % previous["speedup"]
    except Exception:  # noqa: BLE001
        pass

    lines = [
        "## Box3D workers benchmark",
        "",
        "| workers | phys_avg (ms) | phys_max (ms) | cores |",
        "|---|---|---|---|",
    ]
    for row in rows:
        lines.append("| %s | %s | %s | %s |" % (
            row.get("workers"), row.get("phys_avg_ms"), row.get("phys_max_ms"), row.get("cores")))
    if "speedup" in current:
        lines += ["", "speedup (1 worker / %s workers): **%s**%s" % (
            top.get("workers"), current["speedup"], delta)]
    lines.append("")
    report = "\n".join(lines)
    print(report)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("\n" + report + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
