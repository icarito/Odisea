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
    parser = argparse.ArgumentParser(description="Train PPO agent with curriculum: stage1 -> stage2 -> optional stage3.")
    parser.add_argument("--scene-stage1", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--scene-stage2", default="core_v2/tests/TestScene_RL_2.tscn")
    parser.add_argument("--scene-stage3", default="", help="Optional third scene for final curriculum stage.")
    parser.add_argument("--timesteps-stage1", type=int, default=16000)
    parser.add_argument("--timesteps-stage2", type=int, default=16000)
    parser.add_argument("--timesteps-stage3", type=int, default=0, help="Optional third stage timesteps.")
    parser.add_argument("--port-stage1", type=int, default=5000)
    parser.add_argument("--port-stage2", type=int, default=5001)
    parser.add_argument("--port-stage3", type=int, default=5002)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=6)
    parser.add_argument("--entropy-coef", type=float, default=0.02, help="PPO entropy coefficient for exploration.")
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--render", action="store_true", help="Launch Godot with window.")
    parser.add_argument("--no-launch", action="store_true", help="Do not auto-launch Godot.")
    parser.add_argument("--model-out", default="agents/models/anna_ppo_curriculum_32k.zip")
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


def _scene_rel(repo_root: Path, scene_path: str) -> str:
    if scene_path.startswith("res://"):
        return scene_path
    return os.path.relpath(str((repo_root / scene_path).resolve()), str(repo_root))


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

    scene_stage1 = _scene_rel(repo_root, args.scene_stage1)
    scene_stage2 = _scene_rel(repo_root, args.scene_stage2)
    has_stage3 = bool(str(args.scene_stage3).strip()) and int(args.timesteps_stage3) > 0
    total_timesteps = int(args.timesteps_stage1 + args.timesteps_stage2 + (args.timesteps_stage3 if has_stage3 else 0))

    model_out = (repo_root / args.model_out).resolve()
    model_out.parent.mkdir(parents=True, exist_ok=True)
    tb_log = (repo_root / args.tensorboard_log).resolve()
    tb_log.mkdir(parents=True, exist_ok=True)

    print("[train_anna_curriculum] stage1 scene=%s steps=%d" % (scene_stage1, args.timesteps_stage1))
    print("[train_anna_curriculum] stage2 scene=%s steps=%d" % (scene_stage2, args.timesteps_stage2))
    if has_stage3:
        scene_stage3 = _scene_rel(repo_root, args.scene_stage3)
        print("[train_anna_curriculum] stage3 scene=%s steps=%d" % (scene_stage3, args.timesteps_stage3))
    else:
        scene_stage3 = ""
    print("[train_anna_curriculum] total steps=%d cpu_threads=%d render=%s launch=%s" % (
        total_timesteps, args.cpu_threads, args.render, not args.no_launch
    ))

    started_at = time.time()
    env1 = AnnaGymEnv(
        scene_path=scene_stage1,
        port=args.port_stage1,
        launch_godot=not args.no_launch,
        headless=not args.render,
    )

    try:
        model = PPO(
            "MlpPolicy",
            env1,
            verbose=args.verbose,
            tensorboard_log=str(tb_log),
            seed=args.seed,
            ent_coef=float(args.entropy_coef),
            learning_rate=float(args.learning_rate),
            device="cpu",
        )
        model.learn(total_timesteps=int(args.timesteps_stage1), progress_bar=True)
    finally:
        env1.close()

    env2 = AnnaGymEnv(
        scene_path=scene_stage2,
        port=args.port_stage2,
        launch_godot=not args.no_launch,
        headless=not args.render,
    )
    try:
        model.set_env(env2)
        model.learn(total_timesteps=int(args.timesteps_stage2), reset_num_timesteps=False, progress_bar=True)
    finally:
        env2.close()

    if has_stage3:
        env3 = AnnaGymEnv(
            scene_path=scene_stage3,
            port=args.port_stage3,
            launch_godot=not args.no_launch,
            headless=not args.render,
        )
        try:
            model.set_env(env3)
            model.learn(total_timesteps=int(args.timesteps_stage3), reset_num_timesteps=False, progress_bar=True)
        finally:
            env3.close()

    model.save(str(model_out.with_suffix("")))

    metadata = {
        "model": str(model_out),
        "seed": args.seed,
        "cpu_threads": args.cpu_threads,
        "entropy_coef": float(args.entropy_coef),
        "learning_rate": float(args.learning_rate),
        "render": args.render,
        "scene_stage1": scene_stage1,
        "scene_stage2": scene_stage2,
        "scene_stage3": scene_stage3 if has_stage3 else None,
        "timesteps_stage1": int(args.timesteps_stage1),
        "timesteps_stage2": int(args.timesteps_stage2),
        "timesteps_stage3": int(args.timesteps_stage3) if has_stage3 else 0,
        "timesteps_total": total_timesteps,
        "timesteps": total_timesteps,
        "port_stage1": args.port_stage1,
        "port_stage2": args.port_stage2,
        "port_stage3": int(args.port_stage3) if has_stage3 else None,
        "duration_sec": round(time.time() - started_at, 3),
        "created_at_unix": int(time.time()),
    }
    meta_path = model_out.with_suffix(".meta.json")
    meta_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("[train_anna_curriculum] saved model: %s" % model_out)
    print("[train_anna_curriculum] saved metadata: %s" % meta_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
