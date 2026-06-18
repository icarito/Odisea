#!/usr/bin/env python3
"""Odisea scene performance benchmark runner.

Uses a headless Godot SceneTree script (-s) to load a scene,
measure idle FPS for N seconds, and output a JSON capture line.

Usage:
    python3 scripts/bench_scene.py --scene Dome_Crio --seconds 5
    python3 scripts/bench_scene.py --all
    python3 scripts/bench_scene.py --list
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
GODOT_BIN = "godot3-bin"
BENCH_SCRIPT = "res://core_v2/tests/perf/bench_runner.gd"

SCENES = {
    "OdiseaExterior": "res://core_v2/levels/OdiseaExterior.tscn",
    "Dome_Crio": "res://core_v2/levels/interiors/Dome_Crio.tscn",
    "ScaffoldOrbit": "res://core_v2/tests/TestScaffoldOrbit.tscn",
}

def run_bench(scene_path: str, seconds: float = 5, timeout: int = 120) -> dict:
    """Run benchmark on one scene, return parsed results."""
    label = Path(scene_path).stem
    cmd = [
        GODOT_BIN, "--no-window",
        "-s", BENCH_SCRIPT,
        scene_path,
        str(int(seconds))
    ]

    print(f"  [{label}] Starting benchmark ({seconds}s)...")

    proc = subprocess.Popen(
        cmd,
        cwd=PROJECT_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    result = {}
    try:
        stdout, _ = proc.communicate(timeout=timeout)
        for line in stdout.splitlines():
            line = line.strip()
            if line.startswith("CAPTURE:"):
                json_str = line[len("CAPTURE:"):]
                result = json.loads(json_str)
            elif "[bench_runner]" in line and "avg_fps" in line:
                print(f"  [{label}] {line.split('[bench_runner]',1)[-1].strip()}")
            elif "[bench_runner]" in line:
                print(f"  [{label}] {line.split('[bench_runner]',1)[-1].strip()}")
    except subprocess.TimeoutExpired:
        proc.kill()
        print(f"  [{label}] TIMEOUT!")

    return result

def main():
    parser = argparse.ArgumentParser(description="Odisea Scene FPS Benchmark")
    parser.add_argument("--scene", help="Scene name (OdiseaExterior, Dome_Crio, ScaffoldOrbit)")
    parser.add_argument("--seconds", type=float, default=5, help="Measurement duration (default: 5s)")
    parser.add_argument("--all", action="store_true", help="Run all scenes")
    parser.add_argument("--list", action="store_true", help="List available scenes")
    args = parser.parse_args()

    if args.list:
        for name, path in SCENES.items():
            print(f"  {name}: {path}")
        return

    targets = SCENES if args.all else ({args.scene: SCENES.get(args.scene, "")} if args.scene else {})
    if not targets:
        print("Specify --scene <name> or --all")
        sys.exit(1)

    results = {}
    for name, path in targets.items():
        result = run_bench(path, args.seconds)
        result["_scene"] = name
        results[name] = result

    print("\n" + "=" * 70)
    print("BENCHMARK RESULTS")
    print("=" * 70)
    header = f"{'Scene':<25} {'Avg FPS':>8} {'Min FPS':>8} {'<30fps':>7} {'DrawCalls':>9} {'Nodes':>7}"
    print(header)
    print("-" * len(header))
    for name, r in results.items():
        avg = r.get("avg_fps", 0)
        mn = r.get("min_fps", 0)
        lt30 = r.get("frames_lt30", 0)
        dc = r.get("draw_calls", 0)
        nc = r.get("node_count", 0)
        print(f"{name:<25} {avg:8.1f} {mn:8.1f} {lt30:7d} {dc:9d} {nc:7d}")

if __name__ == "__main__":
    main()
