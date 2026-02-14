#!/usr/bin/env python3
import sys
import json
import os

def load_snapshots(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, 'r') as f:
            data = json.load(f)
            # Convert list to dict keyed by tag
            return {item['tag']: item for item in data}
    except Exception as e:
        print(f"Error loading {path}: {e}")
        return {}

def main():
    if len(sys.argv) < 3:
        print("Usage: python check_regression.py <current.json> <baseline.json>")
        sys.exit(1)

    current_path = sys.argv[1]
    baseline_path = sys.argv[2]

    current_data = load_snapshots(current_path)
    baseline_data = load_snapshots(baseline_path)

    if not current_data:
        print("No current data found. (Empty JSON or missing file).")
        # In CI, if the stress test failed (exit code 1), we might have empty JSON.
        # But if the file exists and is empty, it means no snapshots were saved.
        # We should fail if we expected data.
        sys.exit(1)

    if not baseline_data:
        print("No baseline data found. Skipping regression check (First run?).")
        # Write markdown summary anyway
        print("## Performance Summary (New Baseline)")
        print("| Test | FPS | Process (ms) | Physics (ms) | Nodes |")
        print("|---|---|---|---|---|")
        for tag, data in current_data.items():
            print(f"| {tag} | {data['fps']:.1f} | {data['process_time_ms']:.2f} | {data['physics_time_ms']:.2f} | {data['node_count']} |")
        sys.exit(0)

    # Thresholds (allowable degradation)
    FPS_TOLERANCE = 0.90 # Current FPS must be at least 90% of baseline
    CPU_TOLERANCE = 1.20 # Current CPU time must be at most 120% of baseline

    failed = False
    print("## Performance Comparison")
    print("| Test | Metric | Current | Baseline | Diff | Status |")
    print("|---|---|---|---|---|---|")

    for tag, curr in current_data.items():
        if tag not in baseline_data:
            print(f"| {tag} | N/A | New Test | - | - | 🆕 |")
            continue

        base = baseline_data[tag]

        # Check FPS
        fps_curr = curr['fps']
        fps_base = base['fps']
        fps_ratio = fps_curr / fps_base if fps_base > 0 else 1.0
        fps_icon = "✅"
        if fps_ratio < FPS_TOLERANCE:
            fps_icon = "❌"
            failed = True

        print(f"| {tag} | FPS | {fps_curr:.1f} | {fps_base:.1f} | {(fps_ratio-1)*100:+.1f}% | {fps_icon} |")

        # Check Process Time
        proc_curr = curr['process_time_ms']
        proc_base = base['process_time_ms']
        # Avoid division by zero
        proc_base = max(proc_base, 0.001)
        proc_ratio = proc_curr / proc_base
        proc_icon = "✅"
        if proc_ratio > CPU_TOLERANCE:
            proc_icon = "❌"
            failed = True

        print(f"| {tag} | CPU (ms) | {proc_curr:.2f} | {proc_base:.2f} | {(proc_ratio-1)*100:+.1f}% | {proc_icon} |")

    if failed:
        print("\n**❌ PERFORMANCE REGRESSION DETECTED**")
        sys.exit(1)
    else:
        print("\n**✅ Performance within tolerances**")
        sys.exit(0)

if __name__ == "__main__":
    main()
