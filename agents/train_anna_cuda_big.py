#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path


def _parse_int_list(raw: str) -> list[int]:
    vals = []
    for tok in str(raw).split(","):
        tok = tok.strip()
        if not tok:
            continue
        vals.append(int(tok))
    if not vals:
        raise argparse.ArgumentTypeError("net arch cannot be empty")
    return vals


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train a large ANNA PPO model with curriculum on CUDA (or CPU fallback)."
    )
    parser.add_argument("--scene-stage1", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--scene-stage2", default="core_v2/tests/TestScene_RL_2.tscn")
    parser.add_argument("--scene-stage3", default="core_v2/tests/TestScene_RL_3.tscn")
    parser.add_argument("--timesteps-stage1", type=int, default=100000)
    parser.add_argument("--timesteps-stage2", type=int, default=400000)
    parser.add_argument("--timesteps-stage3", type=int, default=500000)
    parser.add_argument("--port-stage1", type=int, default=5000)
    parser.add_argument("--port-stage2", type=int, default=5001)
    parser.add_argument("--port-stage3", type=int, default=5002)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=8)
    parser.add_argument("--device", choices=["auto", "cuda", "cpu"], default="auto")
    parser.add_argument("--cuda-device-id", type=int, default=0)
    parser.add_argument("--learning-rate", type=float, default=2.5e-4)
    parser.add_argument("--entropy-coef", type=float, default=0.015)
    parser.add_argument("--gamma", type=float, default=0.995)
    parser.add_argument("--gae-lambda", type=float, default=0.98)
    parser.add_argument("--clip-range", type=float, default=0.2)
    parser.add_argument("--n-steps", type=int, default=4096)
    parser.add_argument("--batch-size", type=int, default=1024)
    parser.add_argument("--n-epochs", type=int, default=10)
    parser.add_argument("--net-arch", type=_parse_int_list, default="1024,1024,512")
    parser.add_argument("--checkpoint-every", type=int, default=50000)
    parser.add_argument("--render", action="store_true", help="Launch Godot with window.")
    parser.add_argument("--no-launch", action="store_true", help="Do not auto-launch Godot.")
    parser.add_argument("--model-out", default="agents/models/anna_ppo_cuda_big.zip")
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
    from stable_baselines3.common.callbacks import CheckpointCallback  # type: ignore
    import numpy as np  # type: ignore
    import torch  # type: ignore
    from torch import nn  # type: ignore

    return AnnaGymEnv, PPO, CheckpointCallback, np, torch, nn


def _scene_rel(repo_root: Path, scene_path: str) -> str:
    if scene_path.startswith("res://"):
        return scene_path
    return os.path.relpath(str((repo_root / scene_path).resolve()), str(repo_root))


def _resolve_device(args: argparse.Namespace, torch_mod) -> str:
    if args.device == "cpu":
        return "cpu"
    if args.device == "cuda":
        if not torch_mod.cuda.is_available():
            raise RuntimeError("CUDA requested but torch.cuda.is_available() is False.")
        return "cuda:%d" % int(args.cuda_device_id)
    if torch_mod.cuda.is_available():
        return "cuda:%d" % int(args.cuda_device_id)
    return "cpu"


def _open_stage_env(AnnaGymEnv, scene: str, port: int, render: bool, no_launch: bool):
    return AnnaGymEnv(
        scene_path=scene,
        port=int(port),
        launch_godot=not no_launch,
        headless=not render,
    )


def _run_stage(model, stage_name: str, timesteps: int, env, callback, reset_num_timesteps: bool) -> None:
    print("[train_anna_cuda_big] %s: timesteps=%d" % (stage_name, int(timesteps)))
    model.set_env(env)
    model.learn(
        total_timesteps=int(timesteps),
        reset_num_timesteps=reset_num_timesteps,
        callback=callback,
        progress_bar=True,
    )


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)

    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv, PPO, CheckpointCallback, np, torch, nn = _prepare_imports(repo_root)

    torch.set_num_threads(max(1, int(args.cpu_threads)))
    try:
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    device = _resolve_device(args, torch)
    if device.startswith("cuda"):
        cuda_id = int(args.cuda_device_id)
        if cuda_id >= torch.cuda.device_count():
            raise RuntimeError("Requested cuda device id %d but only %d devices detected." % (cuda_id, torch.cuda.device_count()))
        torch.cuda.set_device(cuda_id)
        torch.cuda.manual_seed_all(args.seed)
        print("[train_anna_cuda_big] using CUDA: %s (%s)" % (device, torch.cuda.get_device_name(cuda_id)))
    else:
        print("[train_anna_cuda_big] using device: %s" % device)

    scene_stage1 = _scene_rel(repo_root, args.scene_stage1)
    scene_stage2 = _scene_rel(repo_root, args.scene_stage2)
    scene_stage3 = _scene_rel(repo_root, args.scene_stage3)

    steps_stage1 = max(0, int(args.timesteps_stage1))
    steps_stage2 = max(0, int(args.timesteps_stage2))
    steps_stage3 = max(0, int(args.timesteps_stage3))
    total_timesteps = steps_stage1 + steps_stage2 + steps_stage3
    if total_timesteps <= 0:
        raise RuntimeError("Total timesteps must be > 0.")

    model_out = (repo_root / args.model_out).resolve()
    model_out.parent.mkdir(parents=True, exist_ok=True)
    model_stem = model_out.with_suffix("").name

    tb_log = (repo_root / args.tensorboard_log).resolve()
    tb_log.mkdir(parents=True, exist_ok=True)

    checkpoint_dir = model_out.parent / (model_stem + "_ckpt")
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_cb = CheckpointCallback(
        save_freq=max(1, int(args.checkpoint_every)),
        save_path=str(checkpoint_dir),
        name_prefix=model_stem,
    )

    policy_kwargs = {
        "net_arch": dict(pi=list(args.net_arch), vf=list(args.net_arch)),
        "activation_fn": nn.ReLU,
        "ortho_init": False,
    }

    print("[train_anna_cuda_big] stage1=%s (%d)" % (scene_stage1, steps_stage1))
    print("[train_anna_cuda_big] stage2=%s (%d)" % (scene_stage2, steps_stage2))
    print("[train_anna_cuda_big] stage3=%s (%d)" % (scene_stage3, steps_stage3))
    print("[train_anna_cuda_big] total=%d cpu_threads=%d n_steps=%d batch=%d net_arch=%s" % (
        total_timesteps,
        args.cpu_threads,
        int(args.n_steps),
        int(args.batch_size),
        args.net_arch,
    ))

    started_at = time.time()

    env1 = _open_stage_env(AnnaGymEnv, scene_stage1, args.port_stage1, args.render, args.no_launch)
    try:
        model = PPO(
            "MlpPolicy",
            env1,
            verbose=int(args.verbose),
            tensorboard_log=str(tb_log),
            seed=int(args.seed),
            learning_rate=float(args.learning_rate),
            ent_coef=float(args.entropy_coef),
            gamma=float(args.gamma),
            gae_lambda=float(args.gae_lambda),
            clip_range=float(args.clip_range),
            n_steps=int(args.n_steps),
            batch_size=int(args.batch_size),
            n_epochs=int(args.n_epochs),
            policy_kwargs=policy_kwargs,
            device=device,
        )
        if steps_stage1 > 0:
            _run_stage(model, "stage1", steps_stage1, env1, checkpoint_cb, True)
    finally:
        env1.close()

    if steps_stage2 > 0:
        env2 = _open_stage_env(AnnaGymEnv, scene_stage2, args.port_stage2, args.render, args.no_launch)
        try:
            _run_stage(model, "stage2", steps_stage2, env2, checkpoint_cb, False)
        finally:
            env2.close()

    if steps_stage3 > 0:
        env3 = _open_stage_env(AnnaGymEnv, scene_stage3, args.port_stage3, args.render, args.no_launch)
        try:
            _run_stage(model, "stage3", steps_stage3, env3, checkpoint_cb, False)
        finally:
            env3.close()

    model.save(str(model_out.with_suffix("")))

    metadata = {
        "model": str(model_out),
        "device": device,
        "cuda_available": bool(torch.cuda.is_available()),
        "cuda_device_name": torch.cuda.get_device_name(int(args.cuda_device_id)) if device.startswith("cuda") else None,
        "seed": int(args.seed),
        "cpu_threads": int(args.cpu_threads),
        "learning_rate": float(args.learning_rate),
        "entropy_coef": float(args.entropy_coef),
        "gamma": float(args.gamma),
        "gae_lambda": float(args.gae_lambda),
        "clip_range": float(args.clip_range),
        "n_steps": int(args.n_steps),
        "batch_size": int(args.batch_size),
        "n_epochs": int(args.n_epochs),
        "net_arch": list(args.net_arch),
        "scene_stage1": scene_stage1,
        "scene_stage2": scene_stage2,
        "scene_stage3": scene_stage3,
        "timesteps_stage1": steps_stage1,
        "timesteps_stage2": steps_stage2,
        "timesteps_stage3": steps_stage3,
        "timesteps_total": total_timesteps,
        "timesteps": total_timesteps,
        "port_stage1": int(args.port_stage1),
        "port_stage2": int(args.port_stage2),
        "port_stage3": int(args.port_stage3),
        "checkpoint_dir": str(checkpoint_dir),
        "checkpoint_every": int(args.checkpoint_every),
        "duration_sec": round(time.time() - started_at, 3),
        "created_at_unix": int(time.time()),
    }
    meta_path = model_out.with_suffix(".meta.json")
    meta_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    print("[train_anna_cuda_big] saved model: %s" % model_out)
    print("[train_anna_cuda_big] saved metadata: %s" % meta_path)
    print("[train_anna_cuda_big] checkpoints: %s" % checkpoint_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
