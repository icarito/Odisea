#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Dict, Tuple


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Autonomous train/eval harness for ANNA until directional behavior improves."
    )
    parser.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--train-port", type=int, default=5000)
    parser.add_argument("--eval-port", type=int, default=5100)
    parser.add_argument("--rounds", type=int, default=8)
    parser.add_argument("--timesteps-per-round", type=int, default=25000)
    parser.add_argument("--eval-episodes", type=int, default=6)
    parser.add_argument("--eval-max-steps", type=int, default=800)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=6)
    parser.add_argument("--entropy-coef", type=float, default=0.02)
    parser.add_argument("--learning-rate", type=float, default=3e-4)
    parser.add_argument("--output-prefix", default="agents/models/anna_auto")
    parser.add_argument("--success-target", type=float, default=0.5)
    parser.add_argument("--direction-target", type=float, default=0.62)
    parser.add_argument("--min-rounds", type=int, default=2)
    parser.add_argument("--render-eval", action="store_true")
    parser.add_argument("--step-delay", type=float, default=0.0)
    parser.add_argument("--stochastic-eval", action="store_true")
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


def _to_scene_path(repo_root: Path, scene: str) -> str:
    if scene.startswith("res://"):
        return scene
    return os.path.relpath(str((repo_root / scene).resolve()), str(repo_root))


def _evaluate(
    model,
    env,
    episodes: int,
    max_steps: int,
    deterministic: bool,
    step_delay: float,
) -> Dict[str, float]:
    rewards = []
    lengths = []
    successes = 0
    aligned_steps = 0
    improve_steps = 0
    worsen_steps = 0
    total_steps = 0
    angle_delta_abs_sum = 0.0
    action_hist = Counter()

    for _ in range(max(1, episodes)):
        obs, _ = env.reset()
        ep_reward = 0.0
        ep_len = 0
        prev_abs_angle = abs(float(obs[9])) if len(obs) > 9 else 1.0
        success = False

        for step in range(1, max_steps + 1):
            action, _ = model.predict(obs, deterministic=deterministic)
            action_int = int(action)
            action_hist[action_int] += 1

            obs, reward, terminated, truncated, _info = env.step(action_int)
            ep_reward += float(reward)
            ep_len = step

            abs_angle = abs(float(obs[9])) if len(obs) > 9 else 1.0
            delta = prev_abs_angle - abs_angle
            angle_delta_abs_sum += abs(delta)
            if delta > 0.01:
                improve_steps += 1
            elif delta < -0.01:
                worsen_steps += 1
            if abs_angle < 0.10:
                aligned_steps += 1
            total_steps += 1
            prev_abs_angle = abs_angle

            if step_delay > 0:
                time.sleep(step_delay)

            if terminated or truncated:
                if terminated and reward > 0:
                    success = True
                break

        rewards.append(ep_reward)
        lengths.append(ep_len)
        successes += 1 if success else 0

    avg_reward = sum(rewards) / max(1, len(rewards))
    avg_len = sum(lengths) / max(1, len(lengths))
    success_rate = successes / max(1, len(rewards))
    aligned_ratio = aligned_steps / max(1, total_steps)
    improve_ratio = improve_steps / max(1, improve_steps + worsen_steps)
    activity = angle_delta_abs_sum / max(1, total_steps)
    max_action_fraction = (
        (max(action_hist.values()) / float(total_steps)) if total_steps > 0 and action_hist else 1.0
    )
    forward_fraction = (
        sum(action_hist[a] for a in (1, 2, 3)) / float(total_steps) if total_steps > 0 else 1.0
    )

    # Composite directional quality score: prioritize reducing angle and avoiding action collapse.
    direction_score = (
        0.45 * improve_ratio
        + 0.25 * aligned_ratio
        + 0.20 * (1.0 - max_action_fraction)
        + 0.10 * min(1.0, activity / 0.03)
    )
    collapse_forward = forward_fraction > 0.92 and max_action_fraction > 0.88 and improve_ratio < 0.52

    return {
        "avg_reward": avg_reward,
        "avg_len": avg_len,
        "success_rate": success_rate,
        "aligned_ratio": aligned_ratio,
        "improve_ratio": improve_ratio,
        "turn_activity": activity,
        "max_action_fraction": max_action_fraction,
        "forward_fraction": forward_fraction,
        "direction_score": direction_score,
        "collapse_forward": 1.0 if collapse_forward else 0.0,
        "steps": float(total_steps),
    }


def _score(metrics: Dict[str, float]) -> float:
    # Reward scale can be noisy, cap impact so success+direction dominate selection.
    reward_term = max(-1.0, min(1.0, metrics["avg_reward"] / 250.0))
    return (2.0 * metrics["success_rate"]) + metrics["direction_score"] + (0.20 * reward_term)


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)

    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv, PPO, np, torch = _prepare_imports(repo_root)
    scene_path = _to_scene_path(repo_root, args.scene)

    torch.set_num_threads(max(1, int(args.cpu_threads)))
    try:
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)

    out_prefix = (repo_root / args.output_prefix).resolve()
    out_prefix.parent.mkdir(parents=True, exist_ok=True)

    model = None
    best_score = -10e9
    best_metrics: Dict[str, float] = {}
    history = []
    started_at = time.time()

    for rnd in range(1, max(1, args.rounds) + 1):
        round_seed = args.seed + rnd - 1
        np.random.seed(round_seed)
        random.seed(round_seed)
        torch.manual_seed(round_seed)

        train_env = AnnaGymEnv(
            scene_path=scene_path,
            port=args.train_port,
            launch_godot=True,
            headless=True,
        )
        try:
            if model is None:
                model = PPO(
                    "MlpPolicy",
                    train_env,
                    seed=round_seed,
                    verbose=args.verbose,
                    ent_coef=args.entropy_coef,
                    learning_rate=args.learning_rate,
                    device="cpu",
                )
            else:
                model.set_env(train_env)

            model.learn(total_timesteps=args.timesteps_per_round, reset_num_timesteps=False, progress_bar=True)
        finally:
            train_env.close()

        eval_env = AnnaGymEnv(
            scene_path=scene_path,
            port=args.eval_port,
            launch_godot=True,
            headless=not args.render_eval,
        )
        try:
            metrics = _evaluate(
                model=model,
                env=eval_env,
                episodes=args.eval_episodes,
                max_steps=args.eval_max_steps,
                deterministic=not args.stochastic_eval,
                step_delay=args.step_delay,
            )
        finally:
            eval_env.close()

        round_score = _score(metrics)
        record = {
            "round": rnd,
            "seed": round_seed,
            "timesteps_this_round": args.timesteps_per_round,
            "timesteps_total": int(rnd * args.timesteps_per_round),
            "score": round_score,
            **metrics,
        }
        history.append(record)
        print("[auto_train_anna] round=%d score=%.4f metrics=%s" % (rnd, round_score, json.dumps(metrics, sort_keys=True)))

        checkpoint_path = out_prefix.with_name(f"{out_prefix.name}_r{rnd}.zip")
        model.save(str(checkpoint_path.with_suffix("")))

        if round_score > best_score:
            best_score = round_score
            best_metrics = metrics
            best_path = out_prefix.with_name(f"{out_prefix.name}_best.zip")
            model.save(str(best_path.with_suffix("")))
            print("[auto_train_anna] new best model: %s" % best_path)

        stop_by_target = (
            rnd >= args.min_rounds
            and metrics["success_rate"] >= args.success_target
            and metrics["direction_score"] >= args.direction_target
            and metrics["collapse_forward"] < 0.5
        )
        if stop_by_target:
            print("[auto_train_anna] target reached at round %d, stopping early." % rnd)
            break

    summary = {
        "scene": scene_path,
        "rounds_completed": len(history),
        "timesteps_total": int(len(history) * args.timesteps_per_round),
        "best_score": best_score,
        "best_metrics": best_metrics,
        "history": history,
        "config": vars(args),
        "duration_sec": round(time.time() - started_at, 3),
        "created_at_unix": int(time.time()),
    }
    summary_path = out_prefix.with_name(f"{out_prefix.name}_summary.json")
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("[auto_train_anna] summary: %s" % summary_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
