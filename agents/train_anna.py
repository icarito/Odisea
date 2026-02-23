#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train PPO agent for Odisea ANNA RL scene.")
    parser.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--timesteps", type=int, default=200000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=4)
    parser.add_argument("--render", action="store_true", help="Launch Godot with window.")
    parser.add_argument("--no-launch", action="store_true", help="Do not auto-launch Godot.")
    parser.add_argument("--model-out", default="agents/models/anna_ppo.zip")
    parser.add_argument("--tensorboard-log", default="agents/runs/tensorboard")
    parser.add_argument("--verbose", type=int, default=1)
    return parser.parse_args()


def _set_cpu_limits(threads: int) -> None:
    threads = max(1, int(threads))
    value = str(threads)
    os.environ["OMP_NUM_THREADS"] = value
    os.environ["MKL_NUM_THREADS"] = value
    os.environ["OPENBLAS_NUM_THREADS"] = value
    os.environ["NUMEXPR_NUM_THREADS"] = value


def _prepare_imports(repo_root: Path):
    client_dir = repo_root / "core_v2" / "anna" / "client"
    if str(client_dir) not in sys.path:
        sys.path.insert(0, str(client_dir))

    from anna_gym import AnnaGymEnv  # type: ignore
    from stable_baselines3 import PPO  # type: ignore
    import numpy as np  # type: ignore
    import torch  # type: ignore

    return AnnaGymEnv, PPO, np, torch


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)

    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv, PPO, np, torch = _prepare_imports(repo_root)

    torch.set_num_threads(max(1, int(args.cpu_threads)))
    try:
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    model_out = (repo_root / args.model_out).resolve()
    model_out.parent.mkdir(parents=True, exist_ok=True)
    tb_log = (repo_root / args.tensorboard_log).resolve()
    tb_log.mkdir(parents=True, exist_ok=True)

    scene_path = args.scene
    if not scene_path.startswith("res://"):
        scene_path = os.path.relpath(str((repo_root / scene_path).resolve()), str(repo_root))

    print("[train_anna] scene=%s" % scene_path)
    print("[train_anna] timesteps=%d seed=%d cpu_threads=%d render=%s launch=%s" % (
        args.timesteps,
        args.seed,
        args.cpu_threads,
        args.render,
        not args.no_launch,
    ))

    env = AnnaGymEnv(
        scene_path=scene_path,
        port=args.port,
        launch_godot=not args.no_launch,
        headless=not args.render,
    )

    started_at = time.time()
    try:
        model = PPO(
            "MlpPolicy",
            env,
            verbose=args.verbose,
            tensorboard_log=str(tb_log),
            seed=args.seed,
            device="cpu",
        )
        model.learn(total_timesteps=args.timesteps, progress_bar=True)
        model.save(str(model_out.with_suffix("")))
    finally:
        env.close()

    metadata = {
        "model": str(model_out),
        "timesteps": args.timesteps,
        "seed": args.seed,
        "cpu_threads": args.cpu_threads,
        "render": args.render,
        "scene": scene_path,
        "port": args.port,
        "duration_sec": round(time.time() - started_at, 3),
        "created_at_unix": int(time.time()),
    }
    meta_path = model_out.with_suffix(".meta.json")
    meta_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("[train_anna] saved model: %s" % model_out)
    print("[train_anna] saved metadata: %s" % meta_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
