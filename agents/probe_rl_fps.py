#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Quick RL throughput probe for AnnaGym + godot3-server.")
    p.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    p.add_argument("--port", type=int, default=5799)
    p.add_argument("--steps", type=int, default=2000)
    p.add_argument("--action-count", type=int, default=8)
    p.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot3-server"))
    p.add_argument("--render", action="store_true")
    p.add_argument("--min-sps", type=float, default=0.0, help="If >0, exit non-zero when measured sps < min-sps.")
    p.add_argument("--json-out", default="", help="Optional path to write probe result as JSON.")
    return p.parse_args()


def _set_probe_defaults() -> None:
    os.environ.setdefault("GODOT_BIN", "godot3-server")
    os.environ.setdefault("ANNA_GODOT_PREFER_SERVER", "1")
    os.environ.setdefault("ANNA_GODOT_SERVER_FALLBACK", "0")
    os.environ.setdefault("ANNA_GODOT_DISABLE_RENDER_LOOP", "1")
    os.environ.setdefault("ANNA_GODOT_SERVER_VIDEO_DRIVER", "Dummy")
    os.environ.setdefault("ANNA_GODOT_QUIET", "1")
    os.environ.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "1")
    os.environ.setdefault("ANNA_RL_PHYSICS_FPS", "0")
    os.environ.setdefault("ANNA_RL_POLL_SLEEP_USEC", "0")
    os.environ.setdefault("ANNA_RL_DISABLE_QODOT", "1")
    # In godot3-server, '--max-fps 0' is slower than leaving it unset.
    if os.environ.get("ANNA_GODOT_MAX_FPS", "").strip() == "0":
        os.environ.pop("ANNA_GODOT_MAX_FPS", None)


def _prepare_imports(repo_root: Path):
    client_dir = repo_root / "core_v2" / "anna" / "client"
    if str(client_dir) not in sys.path:
        sys.path.insert(0, str(client_dir))
    from anna_gym import AnnaGymEnv  # type: ignore
    return AnnaGymEnv


def main() -> int:
    args = _parse_args()
    _set_probe_defaults()
    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv = _prepare_imports(repo_root)

    scene_path = args.scene
    if not scene_path.startswith("res://"):
        scene_path = str(Path(scene_path))

    env = AnnaGymEnv(
        scene_path=scene_path,
        port=int(args.port),
        launch_godot=True,
        headless=not args.render,
        godot_bin=args.godot_bin,
    )
    try:
        env.reset()
        start = time.time()
        action_count = max(1, int(args.action_count))
        for i in range(max(1, int(args.steps))):
            _, _, done, truncated, _ = env.step(i % action_count)
            if done or truncated:
                env.reset()
        elapsed = max(1e-9, time.time() - start)
        sps = float(args.steps) / elapsed
        result = {
            "scene": scene_path,
            "steps": int(args.steps),
            "elapsed_sec": round(elapsed, 6),
            "sps": round(sps, 3),
            "port": int(args.port),
            "godot_bin": args.godot_bin,
        }
        print("[probe_rl_fps] scene=%s steps=%d elapsed=%.3fs sps=%.2f" % (
            result["scene"],
            result["steps"],
            result["elapsed_sec"],
            result["sps"],
        ))
        if args.json_out:
            out = Path(args.json_out)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(result, indent=2), encoding="utf-8")
            print("[probe_rl_fps] wrote %s" % out)
        if args.min_sps > 0 and sps < float(args.min_sps):
            print("[probe_rl_fps] FAIL: sps %.2f < min_sps %.2f" % (sps, args.min_sps))
            return 2
        return 0
    finally:
        env.close()


if __name__ == "__main__":
    raise SystemExit(main())
