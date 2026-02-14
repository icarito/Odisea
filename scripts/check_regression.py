#!/usr/bin/env python3
import json
import math
import os
import sys
from datetime import datetime, timezone

FPS_TOLERANCE = 0.90  # Current FPS must be at least 90% of baseline
CPU_TOLERANCE = 1.20  # Current CPU time must be at most 120% of baseline
MAX_HISTORY_ENTRIES = 20

SCENARIO_EXPLANATIONS = {
    "saturation_end": "Sustained heavy load after multiple systems are active together.",
    "spawning_end": "Mass instantiation burst; measures scene/object creation pressure.",
    "pathfinding_end": "Navigation/path queries under stress to expose AI/path overhead.",
    "hierarchy_end": "Deep/wide scene-tree traversal and transform propagation costs.",
    "physics_box_end": "Physics-heavy interactions/collisions with many rigid bodies.",
}

PREFERRED_ORDER = [
    "saturation_end",
    "spawning_end",
    "pathfinding_end",
    "hierarchy_end",
    "physics_box_end",
]


def load_snapshots(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error loading {path}: {e}")
        return {}

    if not isinstance(data, list):
        return {}

    out = {}
    for item in data:
        if not isinstance(item, dict):
            continue
        tag = item.get("tag")
        if not tag:
            continue
        out[tag] = item
    return out


def load_history(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
    except Exception as e:
        print(f"Error loading history {path}: {e}")
    return []


def save_history(path, history):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(history, f, indent=2, sort_keys=True)
        f.write("\n")


def ordered_tags(current_data):
    tags = list(current_data.keys())
    preferred = [tag for tag in PREFERRED_ORDER if tag in tags]
    remaining = sorted(tag for tag in tags if tag not in preferred)
    return preferred + remaining


def to_num(value, default=0.0):
    try:
        return float(value)
    except Exception:
        return default


def short_sha(value):
    if not value:
        return "unknown"
    if value == "baseline":
        return value
    return value[:7]


def print_current_snapshot_table(current_data, tags):
    print("## Current Stress Snapshot")
    print("| Scenario | FPS | Process (ms) | Physics (ms) | Nodes |")
    print("|---|---:|---:|---:|---:|")
    for tag in tags:
        d = current_data[tag]
        print(
            f"| `{tag}` | {to_num(d.get('fps')):.1f} | {to_num(d.get('process_time_ms')):.2f} | "
            f"{to_num(d.get('physics_time_ms')):.2f} | {int(to_num(d.get('node_count')))} |"
        )


def print_comparison_table(current_data, baseline_data, tags):
    failed = False
    print("\n## Performance Comparison")
    print("| Scenario | Metric | Current | Baseline | Diff | Status |")
    print("|---|---|---:|---:|---:|---|")

    for tag in tags:
        curr = current_data[tag]
        if tag not in baseline_data:
            print(f"| `{tag}` | N/A | New scenario | - | - | 🆕 |")
            continue

        base = baseline_data[tag]
        fps_curr = to_num(curr.get("fps"))
        fps_base = to_num(base.get("fps"), 1.0)
        fps_ratio = fps_curr / max(fps_base, 0.001)
        fps_ok = fps_ratio >= FPS_TOLERANCE
        failed = failed or not fps_ok
        print(
            f"| `{tag}` | FPS | {fps_curr:.1f} | {fps_base:.1f} | {(fps_ratio - 1.0) * 100:+.1f}% | "
            f"{'✅' if fps_ok else '❌'} |"
        )

        proc_curr = to_num(curr.get("process_time_ms"))
        proc_base = to_num(base.get("process_time_ms"), 0.001)
        proc_ratio = proc_curr / max(proc_base, 0.001)
        proc_ok = proc_ratio <= CPU_TOLERANCE
        failed = failed or not proc_ok
        print(
            f"| `{tag}` | CPU (ms) | {proc_curr:.2f} | {proc_base:.2f} | {(proc_ratio - 1.0) * 100:+.1f}% | "
            f"{'✅' if proc_ok else '❌'} |"
        )
    return failed


def print_scenario_guide(tags):
    print("\n## Scenario Guide")
    print("| Scenario | Meaning |")
    print("|---|---|")
    for tag in tags:
        meaning = SCENARIO_EXPLANATIONS.get(tag, "Stress scenario captured by the test harness.")
        print(f"| `{tag}` | {meaning} |")


def _chart_y_max(values, minimum):
    if not values:
        return minimum
    v = max(values)
    if v <= minimum:
        return minimum
    # round up to clean axis marks
    return int(math.ceil(v / 10.0) * 10)


def print_mermaid_trends(history, tags):
    if len(history) < 2:
        print("\n## Historic Trend")
        print("Need at least 2 runs to draw a trend chart. History has been initialized and will accumulate from now on.")
        return

    labels = [short_sha(entry.get("sha")) for entry in history]
    label_list = ", ".join(f'"{label}"' for label in labels)

    all_fps = []
    all_cpu = []
    for entry in history:
        metrics = entry.get("metrics", {})
        for tag in tags:
            if tag in metrics:
                all_fps.append(to_num(metrics[tag].get("fps")))
                all_cpu.append(to_num(metrics[tag].get("process_time_ms")))

    fps_max = _chart_y_max(all_fps, 60)
    cpu_max = _chart_y_max(all_cpu, 10)

    print(f"\n## Historic Trend (Last {len(history)} Runs)")
    print("```mermaid")
    print("xychart-beta")
    print('  title "FPS Trend by Commit"')
    print(f"  x-axis [{label_list}]")
    print(f'  y-axis "FPS" 0 --> {fps_max}')
    for tag in tags:
        vals = [to_num(entry.get("metrics", {}).get(tag, {}).get("fps")) for entry in history]
        if any(v > 0 for v in vals):
            joined = ", ".join(f"{v:.1f}" for v in vals)
            print(f'  line "{tag}" [{joined}]')
    print("```")

    print("```mermaid")
    print("xychart-beta")
    print('  title "CPU Process Time Trend by Commit (lower is better)"')
    print(f"  x-axis [{label_list}]")
    print(f'  y-axis "Process ms" 0 --> {cpu_max}')
    for tag in tags:
        vals = [to_num(entry.get("metrics", {}).get(tag, {}).get("process_time_ms")) for entry in history]
        if any(v > 0 for v in vals):
            joined = ", ".join(f"{v:.2f}" for v in vals)
            print(f'  line "{tag}" [{joined}]')
    print("```")


def update_history(history, current_data):
    sha = os.environ.get("GITHUB_SHA", "")[:40]
    ref_name = os.environ.get("GITHUB_REF_NAME", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    now = datetime.now(timezone.utc).isoformat()

    entry = {
        "sha": sha,
        "ref_name": ref_name,
        "run_id": run_id,
        "timestamp_utc": now,
        "metrics": current_data,
    }

    # Replace by run_id if rerun, otherwise append.
    if run_id:
        history = [h for h in history if str(h.get("run_id", "")) != str(run_id)]
    history.append(entry)
    return history[-MAX_HISTORY_ENTRIES:]


def main():
    if len(sys.argv) < 4:
        print("Usage: python check_regression.py <current.json> <baseline.json> <history.json>")
        sys.exit(1)

    current_path = sys.argv[1]
    baseline_path = sys.argv[2]
    history_path = sys.argv[3]

    current_data = load_snapshots(current_path)
    baseline_data = load_snapshots(baseline_path)
    history = load_history(history_path)

    if not current_data:
        print("No current data found. (Empty JSON or missing file).")
        sys.exit(1)

    history = update_history(history, current_data)
    if len(history) == 1 and baseline_data:
        history.insert(
            0,
            {
                "sha": "baseline",
                "ref_name": os.environ.get("GITHUB_REF_NAME", ""),
                "run_id": "baseline-seed",
                "timestamp_utc": "baseline",
                "metrics": baseline_data,
            },
        )
        history = history[-MAX_HISTORY_ENTRIES:]
    save_history(history_path, history)

    tags = ordered_tags(current_data)

    print_current_snapshot_table(current_data, tags)
    failed = False

    if not baseline_data:
        print("\nNo baseline data found. Skipping regression check (first run or cache miss).")
    else:
        failed = print_comparison_table(current_data, baseline_data, tags)

    print_mermaid_trends(history, tags)
    print_scenario_guide(tags)

    if failed:
        print("\n**❌ PERFORMANCE REGRESSION DETECTED**")
        sys.exit(1)

    print("\n**✅ Performance within tolerances**")
    sys.exit(0)


if __name__ == "__main__":
    main()
