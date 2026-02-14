#!/usr/bin/env python3
import json
import math
import os
import sys
from datetime import datetime, timezone

DEFAULT_FPS_TOLERANCE = 0.97  # Max allowed FPS drop: 3%
DEFAULT_CPU_TOLERANCE = 1.20  # Current CPU time must be at most 120% of baseline
MAX_HISTORY_ENTRIES = 20

SCENARIO_EXPLANATIONS = {
    "saturation_end": "Sustained heavy load after multiple systems are active together.",
    "spawning_end": "Mass instantiation burst; measures scene/object creation pressure.",
    "pathfinding_end": "Navigation/path queries under stress to expose AI/path overhead.",
    "hierarchy_end": "Deep/wide scene-tree traversal and transform propagation costs.",
    "physics_box_end": "Physics-heavy interactions/collisions with many rigid bodies.",
}

SCENARIO_COMPONENTS = {
    "saturation_end": "Mixed systems / frame budget",
    "spawning_end": "Entity/scene instantiation pipeline",
    "pathfinding_end": "Navigation/pathfinding system",
    "hierarchy_end": "Scene tree / transform propagation",
    "physics_box_end": "Physics broadphase + solver",
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


def _env_float(name, default):
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
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
    offenders = []
    fps_tolerance = _env_float("ODISEA_FPS_TOLERANCE", DEFAULT_FPS_TOLERANCE)
    cpu_tolerance = _env_float("ODISEA_CPU_TOLERANCE", DEFAULT_CPU_TOLERANCE)
    print("\n## Performance Comparison")
    print(f"Thresholds: FPS >= {fps_tolerance * 100:.1f}% of baseline, CPU <= {cpu_tolerance * 100:.1f}% of baseline.")
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
        fps_ok = fps_ratio >= fps_tolerance
        failed = failed or not fps_ok
        if not fps_ok:
            offenders.append(
                {
                    "scenario": tag,
                    "component": SCENARIO_COMPONENTS.get(tag, "Unknown"),
                    "metric": "FPS",
                    "breach_pct": (fps_tolerance - fps_ratio) * 100.0,
                    "current": fps_curr,
                    "baseline": fps_base,
                }
            )
        print(
            f"| `{tag}` | FPS | {fps_curr:.1f} | {fps_base:.1f} | {(fps_ratio - 1.0) * 100:+.1f}% | "
            f"{'✅' if fps_ok else '❌'} |"
        )

        proc_curr = to_num(curr.get("process_time_ms"))
        proc_base = to_num(base.get("process_time_ms"), 0.001)
        proc_ratio = proc_curr / max(proc_base, 0.001)
        proc_ok = proc_ratio <= cpu_tolerance
        failed = failed or not proc_ok
        if not proc_ok:
            offenders.append(
                {
                    "scenario": tag,
                    "component": SCENARIO_COMPONENTS.get(tag, "Unknown"),
                    "metric": "CPU (process ms)",
                    "breach_pct": (proc_ratio - cpu_tolerance) * 100.0,
                    "current": proc_curr,
                    "baseline": proc_base,
                }
            )
        print(
            f"| `{tag}` | CPU (ms) | {proc_curr:.2f} | {proc_base:.2f} | {(proc_ratio - 1.0) * 100:+.1f}% | "
            f"{'✅' if proc_ok else '❌'} |"
        )
    return failed, offenders


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

    fps_min_series = []
    cpu_max_series = []
    physics_max_series = []
    for entry in history:
        metrics = entry.get("metrics", {})
        fps_vals = [to_num(metrics.get(tag, {}).get("fps")) for tag in tags if tag in metrics]
        cpu_vals = [to_num(metrics.get(tag, {}).get("process_time_ms")) for tag in tags if tag in metrics]
        phy_vals = [to_num(metrics.get(tag, {}).get("physics_time_ms")) for tag in tags if tag in metrics]
        fps_min_series.append(min(fps_vals) if fps_vals else 0.0)
        cpu_max_series.append(max(cpu_vals) if cpu_vals else 0.0)
        physics_max_series.append(max(phy_vals) if phy_vals else 0.0)

    fps_max = _chart_y_max(fps_min_series, 60)
    cpu_max = _chart_y_max(cpu_max_series, 10)
    physics_max = _chart_y_max(physics_max_series, 10)

    print(f"\n## Historic Trend (Last {len(history)} Runs)")
    print("```mermaid")
    print("xychart-beta")
    print('  title "Worst-Case FPS Trend (minimum FPS across scenarios)"')
    print(f"  x-axis [{label_list}]")
    print(f'  y-axis "FPS" 0 --> {fps_max}')
    joined = ", ".join(f"{v:.1f}" for v in fps_min_series)
    print(f'  line "min_fps" [{joined}]')
    print("```")
    print("\n---\n")

    print("```mermaid")
    print("xychart-beta")
    print('  title "Worst-Case CPU Trend (max process ms across scenarios)"')
    print(f"  x-axis [{label_list}]")
    print(f'  y-axis "Process ms" 0 --> {cpu_max}')
    joined = ", ".join(f"{v:.2f}" for v in cpu_max_series)
    print(f'  line "max_process_ms" [{joined}]')
    print("```")
    print("\n---\n")

    print("```mermaid")
    print("xychart-beta")
    print('  title "Worst-Case Physics Trend (max physics ms across scenarios)"')
    print(f"  x-axis [{label_list}]")
    print(f'  y-axis "Physics ms" 0 --> {physics_max}')
    joined = ", ".join(f"{v:.2f}" for v in physics_max_series)
    print(f'  line "max_physics_ms" [{joined}]')
    print("```")


def print_offender_summary(offenders):
    print("\n## Likely Offending Components")
    if not offenders:
        print("No offending component detected from threshold checks.")
        return

    offenders = sorted(offenders, key=lambda x: x["breach_pct"], reverse=True)
    print("| Scenario | Component | Metric | Threshold Breach | Current | Baseline |")
    print("|---|---|---|---:|---:|---:|")
    for item in offenders:
        print(
            f"| `{item['scenario']}` | {item['component']} | {item['metric']} | "
            f"{item['breach_pct']:+.1f}% | {item['current']:.2f} | {item['baseline']:.2f} |"
        )

    top = offenders[0]
    print(
        f"\nPrimary suspect: **{top['component']}** (`{top['scenario']}`, {top['metric']}, "
        f"{top['breach_pct']:+.1f}% over threshold)."
    )


def apply_simulated_regression(current_data):
    scenario = os.environ.get("ODISEA_SIM_REGRESSION_SCENARIO", "spawning_end")
    if scenario not in current_data and current_data:
        scenario = sorted(current_data.keys())[0]

    if scenario in current_data:
        target = current_data[scenario]
        target["fps"] = max(1.0, to_num(target.get("fps")) * 0.55)
        target["process_time_ms"] = to_num(target.get("process_time_ms")) * 1.9
        target["physics_time_ms"] = to_num(target.get("physics_time_ms")) * 1.6

    return current_data, scenario


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
    baseline_source = "baseline file"

    if not current_data:
        print("No current data found. (Empty JSON or missing file).")
        sys.exit(1)

    pristine_current_data = json.loads(json.dumps(current_data))
    simulate_regression = os.environ.get("ODISEA_SIMULATE_REGRESSION", "").strip().lower() in {"1", "true", "yes", "on"}
    simulated_scenario = ""
    if simulate_regression:
        current_data, simulated_scenario = apply_simulated_regression(current_data)
        print(f"\n> Regression simulation enabled for scenario `{simulated_scenario}`.")
        if not baseline_data:
            baseline_data = pristine_current_data
            baseline_source = "pre-simulation snapshot"
            print("> Baseline was missing, using pre-simulation snapshot to force a validation failure.")
    elif not baseline_data and history:
        # PR runs may not have a persisted baseline file; use latest historical run as moving baseline.
        previous = history[-1]
        prev_metrics = previous.get("metrics", {}) if isinstance(previous, dict) else {}
        if isinstance(prev_metrics, dict) and prev_metrics:
            baseline_data = prev_metrics
            baseline_source = f"history run {short_sha(previous.get('sha', 'unknown'))}"

    if not simulate_regression:
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
        print(f"\nBaseline source: {baseline_source}.")
        failed, offenders = print_comparison_table(current_data, baseline_data, tags)
        print_offender_summary(offenders)

    if history:
        print_mermaid_trends(history, tags)
    else:
        print("\n## Historic Trend")
        print("History update skipped for this run (simulation mode).")
    print_scenario_guide(tags)

    if failed:
        print("\n**❌ PERFORMANCE REGRESSION DETECTED**")
        sys.exit(1)

    print("\n**✅ Performance within tolerances**")
    sys.exit(0)


if __name__ == "__main__":
    main()
