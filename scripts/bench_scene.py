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
BENCH_SCRIPT = "res://core_v2/tests/perf/bench_runner.gd"

def _resolve_godot(windowed: bool = False) -> str:
    """Motor pinneado del release, via godot_bin.sh (editor GLES3 si windowed, server si no)."""
    env = dict(os.environ)
    if not windowed:
        env["ODISEA_GODOT_FLAVOR"] = "headless"
    try:
        out = subprocess.check_output(
            ["sh", str(PROJECT_ROOT / "tools" / "godot_bin.sh")],
            cwd=PROJECT_ROOT, env=env, text=True, stderr=subprocess.DEVNULL,
        ).strip()
        if out:
            return out.splitlines()[-1]
    except (subprocess.CalledProcessError, OSError):
        pass
    return str(PROJECT_ROOT / "tools" / "godot")

GODOT_BIN = _resolve_godot()
WINDOWED_BIN = _resolve_godot(windowed=True)

SCENES = {
    "OdiseaExterior": "res://core_v2/levels/OdiseaExterior.tscn",
    "Dome_Crio": "res://core_v2/levels/interiors/Dome_Crio.tscn",
    "ScaffoldOrbit": "res://core_v2/tests/TestScaffoldOrbit.tscn",
    "ArkRunSlice": "res://core_v2/levels/ark_run/ArkRunSlice.tscn",
}

def run_bench(scene_path: str, seconds: float = 5, timeout: int = 180,
              windowed: bool = False, size: str = "1280x720") -> dict:
    """Run benchmark on one scene, return parsed results.

    Headless (default) mide física/FPS de simulación sin renderer. `windowed` usa el
    editor GLES3 con ventana real de `size` para FPS y draw calls medibles.
    """
    label = Path(scene_path).stem
    if windowed:
        cmd = [WINDOWED_BIN, "-s", BENCH_SCRIPT, scene_path, str(int(seconds)),
               "--resolution", size]
    else:
        cmd = [GODOT_BIN, "--headless", "--no-window", "-s", BENCH_SCRIPT,
               scene_path, str(int(seconds))]
        timeout = timeout - 60

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
    parser.add_argument("--windowed", action="store_true",
                        help="Editor GLES3 con ventana real (FPS/draw calls medibles)")
    parser.add_argument("--size", default="1280x720", help="Window size for --windowed")
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
        result = run_bench(path, args.seconds, windowed=args.windowed, size=args.size)
        result["_scene"] = name
        results[name] = result
        if result:
            print(f"  [{name}] RAW {json.dumps(result)}")

    print("\n" + "=" * 70)
    print("BENCHMARK RESULTS")
    print("=" * 70)
    header = (f"{'Scene':<25} {'AvgFPS':>8} {'MinFPS':>8} {'<30':>5} "
              f"{'DrawCalls':>10} {'PhysMs':>8} {'Nodes':>7}")
    print(header)
    print("-" * len(header))
    for name, r in results.items():
        dc = r.get("avg_draw_calls", r.get("draw_calls", 0))
        print(f"{name:<25} {r.get('avg_fps', 0):8.1f} {r.get('min_fps', 0):8.1f} "
              f"{r.get('frames_lt30', 0):5d} {dc:10.1f} {r.get('physics_ms', 0):8.2f} "
              f"{r.get('node_count', 0):7d}")

if __name__ == "__main__":
    main()
