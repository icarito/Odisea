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
    parser = argparse.ArgumentParser(
        description="Evaluate/watch a trained PPO agent in ANNA RL scene.",
        formatter_class=argparse.RawTextHelpFormatter,
        epilog=(
            "Quick start:\n"
            "  python agents/eval_anna.py --watch\n"
            "    Opens window (if display is available), picks latest model automatically,\n"
            "    runs forever, and resets only on win/loss.\n\n"
            "  python agents/eval_anna.py --watch --scene TestScene_RL_2\n"
            "    Same behavior but in another RL scene.\n\n"
            "  python agents/eval_anna.py --headless --episodes 5\n"
            "    Short headless evaluation.\n"
        ),
    )
    parser.add_argument("--model", default="", help="Path to model .zip. If omitted, auto-select latest best model.")
    parser.add_argument("--scene", default="TestScene_RL", help="Scene name/path (e.g. TestScene_RL, TestScene_RL_2).")
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--episodes", type=int, default=5)
    parser.add_argument(
        "--max-steps",
        type=int,
        default=None,
        help="Max steps per episode. Default: 800 (normal mode), unlimited in --watch.",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=4)
    view_group = parser.add_mutually_exclusive_group()
    view_group.add_argument("--render", dest="render", action="store_true", help="Launch Godot with a window.")
    view_group.add_argument("--headless", dest="render", action="store_false", help="Run without window.")
    parser.set_defaults(render=None)
    parser.add_argument("--no-launch", action="store_true", help="Do not auto-launch Godot.")
    parser.add_argument("--stochastic", action="store_true", help="Use stochastic actions instead of deterministic.")
    parser.add_argument("--step-delay", type=float, default=0.0, help="Optional delay between steps (seconds).")
    parser.add_argument("--watch", action="store_true", help="Run continuously until Ctrl+C.")
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


def _pick_default_model(repo_root: Path) -> Path | None:
    candidates = []

    patterns = [
        "agents/models_small/*_best.zip",
        "agents/models/*_best.zip",
        "agents/models/anna_ppo_*.zip",
        "agents/models/*.zip",
    ]
    for pat in patterns:
        candidates.extend(sorted(repo_root.glob(pat), key=lambda p: p.stat().st_mtime, reverse=True))

    # Fallback: previous training pointer.
    pointer = repo_root / "agents" / "models" / ".anna_cuda_big_last_model_out"
    if pointer.exists():
        try:
            pointed = (repo_root / pointer.read_text(encoding="utf-8").strip()).resolve()
            if pointed.exists():
                candidates.append(pointed)
        except Exception:
            pass

    seen = set()
    for p in candidates:
        rp = str(p.resolve())
        if rp in seen:
            continue
        seen.add(rp)
        if p.exists() and p.suffix == ".zip":
            return p
    return None


def main() -> int:
    args = _parse_args()
    if args.render is None:
        # Sane default: watch => visual if display exists; otherwise headless.
        args.render = bool(args.watch and (os.environ.get("DISPLAY") or os.name == "nt"))
    if args.max_steps is None:
        args.max_steps = 0 if args.watch else 800
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

    if str(args.model).strip():
        model_path = (repo_root / args.model).resolve()
    else:
        picked = _pick_default_model(repo_root)
        if picked is None:
            print("[eval_anna] model not provided and no default model found in agents/models*")
            return 2
        model_path = picked.resolve()
        print("[eval_anna] auto model: %s" % model_path)
    if not model_path.exists():
        print("[eval_anna] model not found: %s" % model_path)
        return 2
    meta_path = model_path.with_suffix(".meta.json")
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            timesteps = int(meta.get("timesteps", 0))
            if timesteps > 0 and timesteps < 100_000:
                print(
                    "[eval_anna] warning: model timesteps=%d is low; behavior may look random/poor. Train longer (>=100k)."
                    % timesteps
                )
        except Exception:
            pass

    scene_path = args.scene
    if not scene_path.startswith("res://"):
        scene_path = os.path.relpath(str((repo_root / scene_path).resolve()), str(repo_root))

    env = AnnaGymEnv(
        scene_path=scene_path,
        port=args.port,
        launch_godot=not args.no_launch,
        headless=not args.render,
        auto_relaunch_on_disconnect=not args.watch,
    )
    print(
        "[eval_anna] connected_port=%d render=%s watch=%s max_steps=%d auto_relaunch=%s"
        % (env.port, args.render, args.watch, int(args.max_steps), (not args.watch))
    )

    deterministic = not args.stochastic
    model = PPO.load(str(model_path), device="cpu")

    episode_rewards = []
    episode_lengths = []
    successes = 0

    interrupted = False
    stop_all = False
    try:
        episode = 0
        while True:
            if not args.watch and episode >= args.episodes:
                break
            episode += 1
            obs, _ = env.reset()
            total_reward = 0.0
            length = 0
            success = False

            terminated = False
            truncated = False
            step = 0
            while True:
                step += 1
                action, _ = model.predict(obs, deterministic=deterministic)
                obs, reward, terminated, truncated, info = env.step(action)
                total_reward += float(reward)
                length = step

                if args.step_delay > 0:
                    time.sleep(args.step_delay)

                if bool(info.get("bridge_dead", False)):
                    print("[eval_anna] bridge disconnected; stopping without relaunch.")
                    stop_all = True
                    terminated = True
                    break

                if terminated or truncated:
                    if terminated and reward > 0:
                        success = True
                    break
                if args.max_steps > 0 and step >= args.max_steps:
                    truncated = True
                    break

            episode_rewards.append(total_reward)
            episode_lengths.append(length)
            successes += 1 if success else 0
            end_reason = "running"
            if terminated:
                done_reason = str(info.get("done_reason", "")).strip()
                end_reason = "terminated:%s" % (done_reason if done_reason != "" else "unknown")
            elif truncated and args.max_steps > 0 and length >= args.max_steps:
                end_reason = "truncated:max_steps"
            elif truncated:
                end_reason = "truncated"
            print(
                "[eval_anna] episode=%d reward=%.3f length=%d success=%s end=%s"
                % (episode, total_reward, length, success, end_reason)
            )
            if stop_all:
                break
    except KeyboardInterrupt:
        interrupted = True
        print("[eval_anna] interrupted by user (Ctrl+C)")
    finally:
        env.close()

    avg_reward = sum(episode_rewards) / max(1, len(episode_rewards))
    avg_len = sum(episode_lengths) / max(1, len(episode_lengths))
    success_rate = (successes / max(1, len(episode_rewards))) * 100.0

    print(
        "[eval_anna] summary episodes=%d avg_reward=%.3f avg_len=%.2f success_rate=%.1f%% deterministic=%s interrupted=%s"
        % (len(episode_rewards), avg_reward, avg_len, success_rate, deterministic, interrupted)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
