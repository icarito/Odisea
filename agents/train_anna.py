#!/usr/bin/env python3
"""Train a PPO agent for the Odisea ANNA RL scene (current 13-obs / 8-action bridge).

This is a refreshed version of the archived training scripts, adapted to the current
`core_v2/anna/AnnaBridge.gd` RL protocol (Box(13,), Discrete(8)) and gymnasium API.
It launches one headless Godot process per parallel env, all driven over the ANNA TCP
bridge, and writes checkpoints + a metadata sidecar.

Dev tooling only: it needs stable-baselines3 + torch (see agents/README.md). Nothing it
writes is imported by the Godot export; the exported JSON comes from export_ppo_mlp.py.

Usage:
  python agents/train_anna.py \
      --scene core_v2/tests/TestScene_RL.tscn \
      --timesteps 400000 --num-envs 3 --seed 42 \
      --model-out agents/models/anna_ppo_rl_v2_400k.zip
"""
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train PPO for the Odisea ANNA RL scene.")
    p.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    p.add_argument("--timesteps", type=int, default=400000)
    p.add_argument("--num-envs", type=int, default=3)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--cpu-threads", type=int, default=4)
    p.add_argument("--port-base", type=int, default=15500)
    p.add_argument("--n-steps", type=int, default=2048)
    p.add_argument("--batch-size", type=int, default=512)
    p.add_argument("--n-epochs", type=int, default=10)
    p.add_argument("--learning-rate", type=float, default=3e-4)
    p.add_argument("--ent-coef", type=float, default=0.02)
    p.add_argument("--gamma", type=float, default=0.99)
    p.add_argument("--net-arch", type=int, default=128, help="Hidden width for pi and vf.")
    p.add_argument("--checkpoint-freq", type=int, default=50000)
    p.add_argument("--vec-env", choices=("subproc", "dummy"), default="subproc",
                   help="subproc = parallel Godot processes; dummy = single process, sequential.")
    p.add_argument("--start-method", default="fork", choices=("fork", "forkserver", "spawn"),
                   help="multiprocessing context for subproc vec env.")
    p.add_argument("--model-out", default="agents/models/anna_ppo_rl_v2.zip")
    p.add_argument("--init-from", default="", help="Warm-start PPO from this checkpoint; --timesteps are then ADDITIONAL steps.")
    p.add_argument("--tensorboard-log", default="agents/runs/tensorboard")
    p.add_argument("--verbose", type=int, default=1)
    return p.parse_args()


def _set_cpu_limits(threads: int) -> None:
    v = str(max(1, int(threads)))
    for k in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        os.environ[k] = v


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)

    repo = Path(__file__).resolve().parents[1]
    client_dir = repo / "core_v2" / "anna" / "client"
    if str(client_dir) not in sys.path:
        sys.path.insert(0, str(client_dir))

    import numpy as np
    import torch
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import CheckpointCallback
    from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv, VecMonitor
    from anna_gym import AnnaGymEnv  # type: ignore

    torch.set_num_threads(max(1, int(args.cpu_threads)))
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    scene_path = args.scene
    if not scene_path.startswith("res://"):
        scene_path = os.path.relpath(str((repo / scene_path).resolve()), str(repo))

    width = int(args.net_arch)
    net_arch = dict(pi=[width, width], vf=[width, width])

    def make_env(rank: int):
        def _init():
            return AnnaGymEnv(
                scene_path=scene_path,
                port=args.port_base + rank,
                launch_godot=True,
                headless=True,
            )
        return _init

    model_out = (repo / args.model_out).resolve()
    model_out.parent.mkdir(parents=True, exist_ok=True)
    ckpt_dir = model_out.parent / (model_out.stem + "_checkpoints")
    ckpt_dir.mkdir(parents=True, exist_ok=True)
    tb_log = (repo / args.tensorboard_log).resolve()
    tb_log.mkdir(parents=True, exist_ok=True)

    print(f"[train_anna] scene={scene_path} timesteps={args.timesteps} num_envs={args.num_envs}")
    print(f"[train_anna] seed={args.seed} net_arch={net_arch} n_steps={args.n_steps} "
          f"batch={args.batch_size} epochs={args.n_epochs} lr={args.learning_rate} ent={args.ent_coef}")
    print(f"[train_anna] model_out={model_out} checkpoints={ckpt_dir}")

    n_envs = max(1, args.num_envs)
    if args.vec_env == "subproc":
        vec_env = VecMonitor(SubprocVecEnv([make_env(i) for i in range(n_envs)],
                                           start_method=args.start_method))
    else:
        vec_env = VecMonitor(DummyVecEnv([make_env(i) for i in range(n_envs)]))
    started = time.time()
    try:
        if args.init_from:
            init_path = Path(args.init_from)
            if not init_path.is_absolute():
                init_path = repo / init_path
            model = PPO.load(
                str(init_path),
                env=vec_env,
                device="cpu",
                tensorboard_log=str(tb_log),
                verbose=args.verbose,
                seed=args.seed,
            )
            target = int(model.num_timesteps) + int(args.timesteps)
            # Fine-tune with the (lower) exploration settings passed on the CLI instead of
            # inheriting the warm-start checkpoint's high-entropy PPO config.
            model.learning_rate = args.learning_rate
            model.ent_coef = args.ent_coef
            model.n_epochs = args.n_epochs
            opt = getattr(model.policy, "optimizer", None)
            if opt is not None:
                for group in opt.param_groups:
                    group["lr"] = args.learning_rate
            print(f"[train_anna] warm-start {init_path} at {model.num_timesteps} steps; "
                  f"target absolute {target}; lr={args.learning_rate} ent={args.ent_coef} "
                  f"epochs={args.n_epochs}")
            ckpt = CheckpointCallback(
                save_freq=max(1, args.checkpoint_freq // n_envs),
                save_path=str(ckpt_dir),
                name_prefix=model_out.stem,
            )
            model.learn(total_timesteps=target, callback=ckpt, reset_num_timesteps=False)
        else:
            model = PPO(
                "MlpPolicy",
                vec_env,
                n_steps=args.n_steps,
                batch_size=args.batch_size,
                n_epochs=args.n_epochs,
                learning_rate=args.learning_rate,
                ent_coef=args.ent_coef,
                gamma=args.gamma,
                gae_lambda=0.95,
                clip_range=0.2,
                policy_kwargs=dict(net_arch=net_arch, activation_fn=torch.nn.Tanh),
                verbose=args.verbose,
                tensorboard_log=str(tb_log),
                seed=args.seed,
                device="cpu",
            )
            ckpt = CheckpointCallback(
                save_freq=max(1, args.checkpoint_freq // n_envs),
                save_path=str(ckpt_dir),
                name_prefix=model_out.stem,
            )
            model.learn(total_timesteps=args.timesteps, callback=ckpt)
        model.save(str(model_out.with_suffix("")))
    finally:
        try:
            vec_env.close()
        except Exception:
            pass

    meta = {
        "model": str(model_out),
        "timesteps": args.timesteps,
        "num_envs": args.num_envs,
        "seed": args.seed,
        "cpu_threads": args.cpu_threads,
        "scene": scene_path,
        "obs_dim": 13,
        "num_actions": 8,
        "net_arch": [width, width],
        "n_steps": args.n_steps,
        "batch_size": args.batch_size,
        "n_epochs": args.n_epochs,
        "learning_rate": args.learning_rate,
        "ent_coef": args.ent_coef,
        "gamma": args.gamma,
        "duration_sec": round(time.time() - started, 3),
        "created_at_unix": int(time.time()),
    }
    (model_out.with_suffix(".meta.json")).write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"[train_anna] saved model: {model_out}")
    print(f"[train_anna] saved metadata: {model_out.with_suffix('.meta.json')}")
    print(f"[train_anna] elapsed {meta['duration_sec']}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
