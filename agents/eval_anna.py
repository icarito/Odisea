#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import random
import sys
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate/watch a trained PPO agent in ANNA RL scene.")
    parser.add_argument("--model", required=True, help="Path to .zip model produced by train_anna.py")
    parser.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--episodes", type=int, default=5)
    parser.add_argument("--max-steps", type=int, default=800)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=4)
    parser.add_argument("--render", action="store_true", help="Launch Godot with window.")
    parser.add_argument("--no-launch", action="store_true", help="Do not auto-launch Godot.")
    parser.add_argument("--stochastic", action="store_true", help="Use stochastic actions instead of deterministic.")
    parser.add_argument("--step-delay", type=float, default=0.0, help="Optional delay between steps (seconds).")
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

    model_path = (repo_root / args.model).resolve()
    if not model_path.exists():
        print("[eval_anna] model not found: %s" % model_path)
        return 2

    scene_path = args.scene
    if not scene_path.startswith("res://"):
        scene_path = os.path.relpath(str((repo_root / scene_path).resolve()), str(repo_root))

    env = AnnaGymEnv(
        scene_path=scene_path,
        port=args.port,
        launch_godot=not args.no_launch,
        headless=not args.render,
    )

    deterministic = not args.stochastic
    model = PPO.load(str(model_path), device="cpu")

    episode_rewards = []
    episode_lengths = []
    successes = 0

    try:
        for episode in range(1, args.episodes + 1):
            obs, _ = env.reset()
            total_reward = 0.0
            length = 0
            success = False

            for step in range(1, args.max_steps + 1):
                action, _ = model.predict(obs, deterministic=deterministic)
                obs, reward, terminated, truncated, _info = env.step(action)
                total_reward += float(reward)
                length = step

                if args.step_delay > 0:
                    time.sleep(args.step_delay)

                if terminated or truncated:
                    if terminated and reward > 0:
                        success = True
                    break

            episode_rewards.append(total_reward)
            episode_lengths.append(length)
            successes += 1 if success else 0
            print(
                "[eval_anna] episode=%d reward=%.3f length=%d success=%s"
                % (episode, total_reward, length, success)
            )
    finally:
        env.close()

    avg_reward = sum(episode_rewards) / max(1, len(episode_rewards))
    avg_len = sum(episode_lengths) / max(1, len(episode_lengths))
    success_rate = (successes / max(1, len(episode_rewards))) * 100.0

    print(
        "[eval_anna] summary episodes=%d avg_reward=%.3f avg_len=%.2f success_rate=%.1f%% deterministic=%s"
        % (len(episode_rewards), avg_reward, avg_len, success_rate, deterministic)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
