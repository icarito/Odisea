#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gc
import json
import os
import random
import socket
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Dict, List, Sequence, Tuple


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Autonomous train/eval curriculum harness for ANNA with fast-target and low-wall-contact selection."
    )
    parser.add_argument("--scene", default="", help="Legacy single-scene override. If set, curriculum stages are ignored.")
    parser.add_argument("--train-port", type=int, default=5000)
    parser.add_argument("--scene-stage1", default="core_v2/tests/TestScene_RL.tscn")
    parser.add_argument("--scene-stage2", default="core_v2/tests/TestScene_RL_2.tscn")
    parser.add_argument("--scene-stage3", default="core_v2/tests/TestScene_RL_3.tscn")
    parser.add_argument("--scene-stage4", default="core_v2/tests/TestScene_RL_3_Door.tscn")
    parser.add_argument("--scene-stage5", default="core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn")
    parser.add_argument("--timesteps-stage1", type=int, default=12000)
    parser.add_argument("--timesteps-stage2", type=int, default=16000)
    parser.add_argument("--timesteps-stage3", type=int, default=22000)
    parser.add_argument("--timesteps-stage4", type=int, default=28000)
    parser.add_argument("--timesteps-stage5", type=int, default=34000)
    parser.add_argument("--stage1-round-steps", default="", help="Optional fixed per-round steps for stage1.")
    parser.add_argument("--stage2-round-steps", default="", help="Optional fixed per-round steps for stage2.")
    parser.add_argument("--stage3-round-steps", default="", help="Optional fixed per-round steps for stage3.")
    parser.add_argument("--stage4-round-steps", default="", help="Optional fixed per-round steps for stage4.")
    parser.add_argument("--stage5-round-steps", default="", help="Optional fixed per-round steps for stage5.")
    parser.add_argument("--train-port-stage1", type=int, default=5000)
    parser.add_argument("--train-port-stage2", type=int, default=5001)
    parser.add_argument("--train-port-stage3", type=int, default=5002)
    parser.add_argument("--train-port-stage4", type=int, default=5003)
    parser.add_argument("--train-port-stage5", type=int, default=5004)
    parser.add_argument("--eval-scene", default="", help="Scene used for evaluation. Defaults to last active training stage.")
    parser.add_argument("--eval-port", type=int, default=5100)
    parser.add_argument("--rounds", type=int, default=40)
    parser.add_argument("--timesteps-per-round", type=int, default=40000, help="Used only in --scene single-scene mode.")
    parser.add_argument("--eval-episodes", type=int, default=20)
    parser.add_argument("--eval-max-steps", type=int, default=1500)
    parser.add_argument(
        "--eval-physics-fps",
        type=int,
        default=60,
        help="Physics FPS used only for evaluation environments (live eval, round eval, stage gate).",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=2)
    parser.add_argument("--num-envs", type=int, default=4, help="Parallel Godot envs for training stages.")
    parser.add_argument(
        "--stage-open-retries",
        type=int,
        default=3,
        help="Retries when opening training stage envs fails (e.g. transient Godot startup timeout).",
    )
    parser.add_argument(
        "--stage-open-retry-sleep",
        type=float,
        default=1.0,
        help="Base sleep seconds between stage env open retries.",
    )
    parser.add_argument("--ppo-n-steps", type=int, default=2048, help="PPO rollout steps per env.")
    parser.add_argument("--ppo-batch-size", type=int, default=2048, help="PPO batch size (throughput-sensitive).")
    parser.add_argument("--ppo-n-epochs", type=int, default=2, help="PPO epochs per update (lower = faster).")
    parser.add_argument("--ppo-device", choices=["cpu", "cuda", "auto"], default="cpu", help="Torch device for PPO updates.")
    parser.add_argument("--entropy-coef", type=float, default=0.03)
    parser.add_argument("--learning-rate", type=float, default=5e-4)
    parser.add_argument("--max-model-mb", type=float, default=3.0, help="Hard cap for resulting .zip model size.")
    parser.add_argument("--policy-widths", default="128,160", help="Comma-separated hidden widths to try.")
    parser.add_argument("--policy-depths", default="2", help="Comma-separated layer depths to try.")
    parser.add_argument("--arch-limit", type=int, default=4, help="Max architecture candidates considered after parsing.")
    parser.add_argument("--stage-growth", type=float, default=0.25, help="Per-round growth factor that shifts time to harder stages.")
    parser.add_argument("--max-stage-scale", type=float, default=2.2, help="Upper bound for dynamic stage scaling.")
    parser.add_argument(
        "--stage-unlock-by-success",
        action="store_true",
        default=True,
        help="Unlock next curriculum stage only when current unlocked stage reaches target success.",
    )
    parser.add_argument(
        "--no-stage-unlock-by-success",
        dest="stage_unlock_by_success",
        action="store_false",
        help="Disable stage unlock gating and train all configured stages each round.",
    )
    parser.add_argument(
        "--stage-unlock-target",
        type=float,
        default=0.5,
        help="Success-rate threshold used for stage unlocking when --stage-unlock-by-success is enabled.",
    )
    parser.add_argument(
        "--stage-unlock-eval-episodes",
        type=int,
        default=4,
        help="Episodes used to evaluate unlocked stage progress.",
    )
    parser.add_argument(
        "--stage-unlock-max-steps",
        type=int,
        default=900,
        help="Max steps for stage unlock evaluation episodes.",
    )
    parser.add_argument("--rl-physics-fps", type=int, default=4000, help="Value for ANNA_RL_PHYSICS_FPS (<=0 uses AnnaBridge uncapped mode).")
    parser.add_argument("--rl-max-steps", type=int, default=1500, help="Default ANNA_RL_MAX_STEPS exported to Godot.")
    parser.add_argument(
        "--rl-disable-cpu-sleep",
        dest="rl_disable_cpu_sleep",
        action="store_true",
        default=True,
        help="Set ANNA_RL_DISABLE_CPU_SLEEP=1 for RL runs (default: on).",
    )
    parser.add_argument(
        "--rl-allow-cpu-sleep",
        dest="rl_disable_cpu_sleep",
        action="store_false",
        help="Allow polling sleep in RL bridge (lower CPU, lower max FPS).",
    )
    parser.add_argument("--output-prefix", default="agents/models/anna_auto")
    parser.add_argument("--init-model", default="", help="Optional PPO .zip to warm-start training.")
    parser.add_argument("--success-target", type=float, default=0.5)
    parser.add_argument("--direction-target", type=float, default=0.62)
    parser.add_argument("--fast-success-target", type=float, default=0.45)
    parser.add_argument("--wall-contact-max", type=float, default=0.18)
    parser.add_argument("--wall-touch-ray-threshold", type=float, default=0.04)
    parser.add_argument("--min-rounds", type=int, default=2)
    parser.add_argument("--render-eval", action="store_true")
    parser.add_argument("--step-delay", type=float, default=0.0)
    parser.add_argument("--stochastic-eval", action="store_true")
    parser.add_argument(
        "--live-report-steps",
        type=int,
        default=20000,
        help="Emit live telemetry every N train steps inside each stage (<=0 disables chunk telemetry).",
    )
    parser.add_argument(
        "--live-eval-episodes",
        type=int,
        default=1,
        help="Quick eval episodes for each live telemetry chunk (0 disables).",
    )
    parser.add_argument(
        "--live-eval-max-steps",
        type=int,
        default=300,
        help="Max steps for quick live eval runs.",
    )
    parser.add_argument(
        "--save-latest-per-live",
        dest="save_latest_per_live",
        action="store_true",
        default=True,
        help="Save <output>_latest.zip after each live telemetry chunk (default: on).",
    )
    parser.add_argument(
        "--no-save-latest-per-live",
        dest="save_latest_per_live",
        action="store_false",
        help="Disable latest checkpoint saves for each live telemetry chunk.",
    )
    parser.add_argument("--verbose", type=int, default=0)
    return parser.parse_args()


def _parse_int_list(raw: str, fallback: Sequence[int]) -> List[int]:
    values: List[int] = []
    for token in str(raw).split(","):
        token = token.strip()
        if not token:
            continue
        try:
            v = int(token)
        except ValueError:
            continue
        if v > 0:
            values.append(v)
    if not values:
        values = list(fallback)
    # Keep stable deterministic order + remove duplicates.
    return sorted(set(values))


def _parse_round_steps(raw: str) -> List[int]:
    values: List[int] = []
    for token in str(raw).split(","):
        token = token.strip()
        if not token:
            continue
        try:
            v = int(token)
        except ValueError:
            continue
        if v > 0:
            values.append(v)
    return values


def _build_arch_candidates(widths: Sequence[int], depths: Sequence[int], limit: int) -> List[List[int]]:
    candidates: List[List[int]] = []
    for depth in depths:
        for width in widths:
            candidates.append([int(width)] * int(depth))
    # Prefer larger models first, but still deterministic.
    candidates.sort(key=lambda arch: (sum(arch), len(arch)), reverse=True)
    if limit > 0:
        candidates = candidates[: int(limit)]
    return candidates


def _probe_arch_size_bytes(
    PPO,
    env,
    out_prefix: Path,
    arch: Sequence[int],
    seed: int,
    ent_coef: float,
    learning_rate: float,
) -> int:
    probe_path = out_prefix.with_name(f"{out_prefix.name}_probe_{'x'.join(str(v) for v in arch)}.zip")
    probe_no_suffix = probe_path.with_suffix("")
    policy_kwargs = {"net_arch": dict(pi=list(arch), vf=list(arch))}
    model = PPO(
        "MlpPolicy",
        env,
        seed=seed,
        verbose=0,
        ent_coef=float(ent_coef),
        learning_rate=float(learning_rate),
        policy_kwargs=policy_kwargs,
        device="cpu",
    )
    try:
        model.save(str(probe_no_suffix), exclude=["policy.optimizer"])
    finally:
        del model
        gc.collect()
    size_bytes = probe_path.stat().st_size if probe_path.exists() else 0
    try:
        probe_path.unlink(missing_ok=True)
    except Exception:
        pass
    return int(size_bytes)


def _pick_best_arch_under_cap(
    PPO,
    env,
    out_prefix: Path,
    arch_candidates: Sequence[Sequence[int]],
    max_model_bytes: int,
    seed: int,
    ent_coef: float,
    learning_rate: float,
) -> Tuple[List[int], List[Dict[str, object]]]:
    probes: List[Dict[str, object]] = []
    selected: List[int] = []
    for arch in arch_candidates:
        size_bytes = _probe_arch_size_bytes(
            PPO=PPO,
            env=env,
            out_prefix=out_prefix,
            arch=arch,
            seed=seed,
            ent_coef=ent_coef,
            learning_rate=learning_rate,
        )
        record = {
            "arch": list(arch),
            "size_bytes": int(size_bytes),
            "size_mb": round(size_bytes / (1024.0 * 1024.0), 4),
            "fits": bool(size_bytes <= max_model_bytes),
        }
        probes.append(record)
        if size_bytes <= max_model_bytes and not selected:
            selected = list(arch)

    if not selected:
        # Fallback to smallest candidate to keep the run alive.
        smallest = min(probes, key=lambda x: int(x["size_bytes"])) if probes else {"arch": [64, 64]}
        selected = list(smallest["arch"])  # type: ignore[index]
    return selected, probes


def _dynamic_stage_steps(
    base_steps: int,
    stage_idx: int,
    stage_count: int,
    round_idx: int,
    rounds_total: int,
    stage_growth: float,
    max_stage_scale: float,
) -> int:
    if base_steps <= 0:
        return 0
    if rounds_total <= 1:
        return int(base_steps)

    progress = float(round_idx - 1) / float(max(1, rounds_total - 1))
    hardness = float(stage_idx) / float(max(1, stage_count - 1))

    # As rounds advance:
    # - easy stages lose part of the budget,
    # - hard stages gain more budget.
    easy_decay = 1.0 - (0.45 * progress * (1.0 - hardness))
    hard_growth = 1.0 + (stage_growth * float(round_idx - 1) * (0.35 + hardness))
    scale = max(0.35, min(float(max_stage_scale), easy_decay * hard_growth))
    return max(512, int(round(float(base_steps) * scale)))


def _set_cpu_limits(threads: int) -> None:
    threads = max(1, int(threads))
    value = str(threads)
    os.environ["OMP_NUM_THREADS"] = value
    os.environ["MKL_NUM_THREADS"] = value
    os.environ["OPENBLAS_NUM_THREADS"] = value
    os.environ["NUMEXPR_NUM_THREADS"] = value


def _set_rl_runtime_tuning(physics_fps: int, disable_cpu_sleep: bool, rl_max_steps: int) -> None:
    os.environ["ANNA_RL_PHYSICS_FPS"] = str(int(physics_fps))
    os.environ["ANNA_RL_MAX_STEPS"] = str(max(100, int(rl_max_steps)))
    os.environ.setdefault("ANNA_GODOT_PREFER_SERVER", "1")
    os.environ.setdefault("ANNA_GODOT_SERVER_FALLBACK", "0")
    os.environ.setdefault("ANNA_GODOT_SERVER_VIDEO_DRIVER", "")
    os.environ.setdefault("ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG", "1")
    os.environ.setdefault("ANNA_GODOT_VIDEO_DRIVER", "GLES2")
    os.environ.setdefault("ODISEA_DISABLE_PERFMON_IN_RL", "1")
    os.environ.setdefault("ODISEA_QUIET_PERFMON", "1")
    os.environ.setdefault("ODISEA_DISABLE_FAKE_SHADOW", "1")
    os.environ.setdefault("ODISEA_DISABLE_SHADER_WARMUP", "1")
    os.environ.setdefault("ODISEA_DISABLE_SHADER_WARMUP_IN_RL", "1")
    os.environ.setdefault("ANNA_RL_TARGET_FPS", "4000")
    if disable_cpu_sleep:
        os.environ["ANNA_RL_DISABLE_CPU_SLEEP"] = "1"
        os.environ.setdefault("ANNA_RL_POLL_SLEEP_USEC", "0")
    else:
        os.environ.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "0")
        os.environ.setdefault("ANNA_RL_POLL_SLEEP_USEC", "1000")


def _set_eval_runtime_tuning(eval_physics_fps: int) -> Dict[str, str | None]:
    keys = [
        "ANNA_RL_TARGET_FPS",
        "ANNA_RL_PHYSICS_FPS",
        "ANNA_RL_PHYSICS_FPS_CAP",
        "ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME",
    ]
    prev = {k: os.environ.get(k) for k in keys}
    fps = max(30, int(eval_physics_fps))
    os.environ["ANNA_RL_TARGET_FPS"] = str(fps)
    os.environ["ANNA_RL_PHYSICS_FPS"] = str(fps)
    os.environ["ANNA_RL_PHYSICS_FPS_CAP"] = str(fps)
    os.environ["ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME"] = "8"
    return prev


def _restore_runtime_tuning(prev: Dict[str, str | None]) -> None:
    for key, value in prev.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def _prepare_imports(repo_root: Path):
    client_dir = repo_root / "core_v2" / "anna" / "client"
    if str(client_dir) not in sys.path:
        sys.path.insert(0, str(client_dir))

    from anna_gym import AnnaGymEnv  # type: ignore
    from stable_baselines3 import PPO  # type: ignore
    from stable_baselines3.common.monitor import Monitor  # type: ignore
    from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv  # type: ignore
    from stable_baselines3.common.utils import get_schedule_fn  # type: ignore
    import numpy as np  # type: ignore
    import torch  # type: ignore

    return AnnaGymEnv, PPO, Monitor, DummyVecEnv, SubprocVecEnv, get_schedule_fn, np, torch


def _is_port_available(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", int(port)))
            return True
        except OSError:
            return False


def _find_available_port_block(start_port: int, block_size: int, max_scan: int = 2000) -> int:
    start = max(1024, int(start_port))
    size = max(1, int(block_size))
    for base in range(start, start + max(1, int(max_scan))):
        ok = True
        for p in range(base, base + size):
            if not _is_port_available(p):
                ok = False
                break
        if ok:
            return base
    raise RuntimeError("No free contiguous port block size=%d from %d." % (size, start))


def _build_env_factory(
    AnnaGymEnv,
    Monitor,
    scene: str,
    port: int,
):
    def _make():
        env = AnnaGymEnv(
            scene_path=scene,
            port=int(port),
            launch_godot=True,
            headless=True,
        )
        return Monitor(env)

    return _make


def _open_stage_env(
    AnnaGymEnv,
    Monitor,
    DummyVecEnv,
    SubprocVecEnv,
    scene: str,
    start_port: int,
    num_envs: int,
    open_retries: int = 3,
    retry_sleep_sec: float = 1.0,
):
    env_count = max(1, int(num_envs))
    attempts = max(1, int(open_retries))
    base_sleep = max(0.1, float(retry_sleep_sec))
    last_exc: Exception | None = None

    for attempt in range(1, attempts + 1):
        env_fns = []
        port_hint = int(start_port) + (attempt - 1) * 20
        try:
            base_port = _find_available_port_block(port_hint, env_count)
            for idx in range(env_count):
                env_fns.append(
                    _build_env_factory(
                        AnnaGymEnv=AnnaGymEnv,
                        Monitor=Monitor,
                        scene=scene,
                        port=base_port + idx,
                    )
                )
            if len(env_fns) > 1:
                return SubprocVecEnv(env_fns, start_method="spawn")
            return DummyVecEnv(env_fns)
        except Exception as exc:
            last_exc = exc
            if attempt >= attempts:
                break
            wait_s = base_sleep * float(attempt)
            print(
                "[auto_train_anna] stage env open retry %d/%d scene=%s reason=%s wait=%.2fs"
                % (attempt, attempts, scene, str(exc), wait_s)
            )
            time.sleep(wait_s)

    if last_exc is not None:
        raise last_exc
    raise RuntimeError("Failed to open stage env for scene=%s" % scene)


def _to_scene_path(repo_root: Path, scene: str) -> str:
    if scene.startswith("res://"):
        return scene
    return os.path.relpath(str((repo_root / scene).resolve()), str(repo_root))


def _build_train_stages(repo_root: Path, args: argparse.Namespace) -> List[Dict[str, object]]:
    if str(args.scene).strip():
        return [
            {
                "name": "single",
                "scene": _to_scene_path(repo_root, args.scene),
                "steps": max(0, int(args.timesteps_per_round)),
                "port": int(args.train_port),
            }
        ]

    stages: List[Dict[str, object]] = []
    raw = [
        ("stage1", args.scene_stage1, args.timesteps_stage1, args.train_port_stage1),
        ("stage2", args.scene_stage2, args.timesteps_stage2, args.train_port_stage2),
        ("stage3", args.scene_stage3, args.timesteps_stage3, args.train_port_stage3),
        ("stage4", args.scene_stage4, args.timesteps_stage4, args.train_port_stage4),
        ("stage5", args.scene_stage5, args.timesteps_stage5, args.train_port_stage5),
    ]
    for name, scene, steps, port in raw:
        steps_i = max(0, int(steps))
        if not str(scene).strip() or steps_i <= 0:
            continue
        stages.append(
            {
                "name": name,
                "scene": _to_scene_path(repo_root, str(scene)),
                "steps": steps_i,
                "port": int(port),
            }
        )

    if not stages:
        raise RuntimeError("No training stages configured. Set --scene or positive --timesteps-stageN values.")
    return stages


def _safe_corr(np, a, b) -> float:
    if len(a) < 3 or len(b) < 3:
        return 0.0
    try:
        corr = float(np.corrcoef(np.asarray(a), np.asarray(b))[0, 1])
    except Exception:
        return 0.0
    if corr != corr:  # NaN guard.
        return 0.0
    return corr


def _evaluate(
    model,
    env,
    np,
    torch,
    episodes: int,
    max_steps: int,
    deterministic: bool,
    step_delay: float,
    wall_touch_ray_threshold: float,
) -> Dict[str, float]:
    rewards = []
    lengths = []
    successes = 0
    success_lengths = []
    aligned_steps = 0
    improve_steps = 0
    worsen_steps = 0
    total_steps = 0
    angle_delta_abs_sum = 0.0
    wall_touch_steps = 0
    speed_sum = 0.0
    dist_sum = 0.0
    min_dist = 1e9
    action_hist = Counter()
    gamma = float(getattr(model, "gamma", 0.99))
    value_preds_all = []
    returns_all = []
    top1_probs = []
    entropies = []
    action_space_n = int(getattr(getattr(model, "action_space", None), "n", 8))
    max_entropy = float(np.log(max(2, action_space_n)))

    for _ in range(max(1, episodes)):
        obs, _ = env.reset()
        ep_reward = 0.0
        ep_len = 0
        prev_abs_angle = abs(float(obs[9])) if len(obs) > 9 else 1.0
        success = False
        ep_rewards = []
        ep_values = []

        for step in range(1, max_steps + 1):
            # Predictive diagnostics from current policy/value outputs.
            obs_tensor, _ = model.policy.obs_to_tensor(obs)
            with torch.no_grad():
                dist = model.policy.get_distribution(obs_tensor)
                probs = dist.distribution.probs.detach().cpu().numpy().reshape(-1)
                top1_probs.append(float(np.max(probs)))
                entropy = -float(np.sum(probs * np.log(np.clip(probs, 1e-8, 1.0))))
                entropies.append(entropy)
                value_pred = float(model.policy.predict_values(obs_tensor).detach().cpu().numpy().reshape(-1)[0])

            action, _ = model.predict(obs, deterministic=deterministic)
            action_int = int(action)
            action_hist[action_int] += 1

            obs, reward, terminated, truncated, _info = env.step(action_int)
            ep_reward += float(reward)
            ep_len = step
            ep_rewards.append(float(reward))
            ep_values.append(value_pred)

            abs_angle = abs(float(obs[9])) if len(obs) > 9 else 1.0
            delta = prev_abs_angle - abs_angle
            angle_delta_abs_sum += abs(delta)
            if len(obs) >= 8:
                front_min = min(float(v) for v in obs[:8])
                if front_min < wall_touch_ray_threshold:
                    wall_touch_steps += 1
            if len(obs) > 11:
                vx = float(obs[10])
                vz = float(obs[11])
                speed_sum += min(1.0, (vx * vx + vz * vz) ** 0.5) * 20.0
            if len(obs) > 8:
                dist_now = max(0.0, float(obs[8])) * 50.0
                dist_sum += dist_now
                if dist_now < min_dist:
                    min_dist = dist_now
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
                    success_lengths.append(step)
                break

        # Critic fit proxy: compare value predictions vs discounted realized returns.
        ret = 0.0
        ep_returns = []
        for r in reversed(ep_rewards):
            ret = float(r) + gamma * ret
            ep_returns.append(ret)
        ep_returns.reverse()
        if ep_returns and ep_values:
            pair_n = min(len(ep_returns), len(ep_values))
            returns_all.extend(ep_returns[:pair_n])
            value_preds_all.extend(ep_values[:pair_n])

        rewards.append(ep_reward)
        lengths.append(ep_len)
        successes += 1 if success else 0

    avg_reward = sum(rewards) / max(1, len(rewards))
    avg_len = sum(lengths) / max(1, len(lengths))
    avg_success_len = (
        sum(success_lengths) / max(1, len(success_lengths)) if success_lengths else float(max_steps)
    )
    success_rate = successes / max(1, len(rewards))
    aligned_ratio = aligned_steps / max(1, total_steps)
    improve_ratio = improve_steps / max(1, improve_steps + worsen_steps)
    activity = angle_delta_abs_sum / max(1, total_steps)
    wall_touch_ratio = wall_touch_steps / max(1, total_steps)
    wall_clear_ratio = 1.0 - wall_touch_ratio
    avg_speed = speed_sum / max(1, total_steps)
    avg_target_dist = dist_sum / max(1, total_steps)
    speed_score = min(1.0, avg_speed / 7.0)
    fast_success_score = 0.0
    if success_lengths:
        fast_success_score = max(0.0, 1.0 - min(1.0, avg_success_len / float(max_steps)))
    max_action_fraction = (
        (max(action_hist.values()) / float(total_steps)) if total_steps > 0 and action_hist else 1.0
    )
    forward_fraction = (
        sum(action_hist[a] for a in (1, 2, 3)) / float(total_steps) if total_steps > 0 else 1.0
    )
    jump_fraction = (
        sum(action_hist[a] for a in (3, 6, 7)) / float(total_steps) if total_steps > 0 else 0.0
    )
    strafe_fraction = (
        sum(action_hist[a] for a in (4, 5, 6, 7)) / float(total_steps) if total_steps > 0 else 0.0
    )

    # Composite directional quality score: prioritize reducing angle and avoiding action collapse.
    direction_score = (
        0.45 * improve_ratio
        + 0.25 * aligned_ratio
        + 0.20 * (1.0 - max_action_fraction)
        + 0.10 * min(1.0, activity / 0.03)
    )
    collapse_forward = forward_fraction > 0.92 and max_action_fraction > 0.88 and improve_ratio < 0.52
    avg_top1_prob = sum(top1_probs) / max(1, len(top1_probs))
    avg_entropy = sum(entropies) / max(1, len(entropies))
    entropy_norm = min(1.0, avg_entropy / max(1e-6, max_entropy))
    value_mae = 0.0
    if value_preds_all:
        value_mae = float(np.mean(np.abs(np.asarray(value_preds_all) - np.asarray(returns_all))))
    value_corr = _safe_corr(np, value_preds_all, returns_all)
    value_fit_score = 1.0 / (1.0 + value_mae)
    predictive_capacity = (
        0.45 * avg_top1_prob
        + 0.35 * max(0.0, value_corr)
        + 0.20 * value_fit_score
    )

    return {
        "avg_reward": avg_reward,
        "avg_len": avg_len,
        "avg_success_len": avg_success_len,
        "success_rate": success_rate,
        "fast_success_score": fast_success_score,
        "wall_touch_ratio": wall_touch_ratio,
        "wall_clear_ratio": wall_clear_ratio,
        "avg_speed": avg_speed,
        "avg_target_dist": avg_target_dist,
        "min_target_dist": (0.0 if min_dist >= 1e8 else float(min_dist)),
        "speed_score": speed_score,
        "aligned_ratio": aligned_ratio,
        "improve_ratio": improve_ratio,
        "turn_activity": activity,
        "max_action_fraction": max_action_fraction,
        "forward_fraction": forward_fraction,
        "jump_fraction": jump_fraction,
        "strafe_fraction": strafe_fraction,
        "direction_score": direction_score,
        "collapse_forward": 1.0 if collapse_forward else 0.0,
        "policy_top1_prob": avg_top1_prob,
        "policy_entropy": avg_entropy,
        "policy_entropy_norm": entropy_norm,
        "value_return_corr": value_corr,
        "value_mae": value_mae,
        "predictive_capacity": predictive_capacity,
        "steps": float(total_steps),
    }


def _score(metrics: Dict[str, float]) -> float:
    # Reward scale can be noisy; prioritize success speed + clean navigation.
    reward_term = max(-1.0, min(1.0, metrics["avg_reward"] / 250.0))
    predictive_term = max(0.0, min(1.0, metrics.get("predictive_capacity", 0.0)))
    return (
        (2.3 * metrics["success_rate"])
        + (1.2 * metrics["fast_success_score"])
        + (1.0 * metrics["wall_clear_ratio"])
        + (0.9 * metrics["direction_score"])
        + (0.35 * metrics["speed_score"])
        + (0.25 * predictive_term)
        + (0.15 * reward_term)
    )


def _format_live_metrics(metrics: Dict[str, float]) -> str:
    return (
        "success={success:.3f} fast={fast:.3f} dir={dir:.3f} wall={wall:.3f} "
        "dist={dist:.2f} min_dist={min_dist:.2f} speed={speed:.2f} "
        "jump={jump:.3f} strafe={strafe:.3f} "
        "pred={pred:.3f} top1={top1:.3f} ent={ent:.3f} v_corr={vcorr:.3f} v_mae={vmae:.3f}"
    ).format(
        success=float(metrics.get("success_rate", 0.0)),
        fast=float(metrics.get("fast_success_score", 0.0)),
        dir=float(metrics.get("direction_score", 0.0)),
        wall=float(metrics.get("wall_touch_ratio", 0.0)),
        dist=float(metrics.get("avg_target_dist", 0.0)),
        min_dist=float(metrics.get("min_target_dist", 0.0)),
        speed=float(metrics.get("avg_speed", 0.0)),
        jump=float(metrics.get("jump_fraction", 0.0)),
        strafe=float(metrics.get("strafe_fraction", 0.0)),
        pred=float(metrics.get("predictive_capacity", 0.0)),
        top1=float(metrics.get("policy_top1_prob", 0.0)),
        ent=float(metrics.get("policy_entropy_norm", 0.0)),
        vcorr=float(metrics.get("value_return_corr", 0.0)),
        vmae=float(metrics.get("value_mae", 0.0)),
    )


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)
    _set_rl_runtime_tuning(
        physics_fps=int(args.rl_physics_fps),
        disable_cpu_sleep=bool(args.rl_disable_cpu_sleep),
        rl_max_steps=int(args.rl_max_steps),
    )

    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv, PPO, Monitor, DummyVecEnv, SubprocVecEnv, get_schedule_fn, np, torch = _prepare_imports(repo_root)
    stages = _build_train_stages(repo_root, args)
    stage_round_steps = {
        "stage1": _parse_round_steps(args.stage1_round_steps),
        "stage2": _parse_round_steps(args.stage2_round_steps),
        "stage3": _parse_round_steps(args.stage3_round_steps),
        "stage4": _parse_round_steps(args.stage4_round_steps),
        "stage5": _parse_round_steps(args.stage5_round_steps),
    }
    base_timesteps_per_round = int(sum(int(s["steps"]) for s in stages))
    if base_timesteps_per_round <= 0:
        raise RuntimeError("timesteps per round must be > 0.")
    if str(args.eval_scene).strip():
        eval_scene = _to_scene_path(repo_root, args.eval_scene)
    else:
        eval_scene = str(stages[-1]["scene"])

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

    max_model_bytes = int(max(0.1, float(args.max_model_mb)) * 1024 * 1024)
    policy_widths = _parse_int_list(args.policy_widths, fallback=[64, 96, 128])
    policy_depths = _parse_int_list(args.policy_depths, fallback=[2, 3])
    arch_candidates = _build_arch_candidates(policy_widths, policy_depths, int(args.arch_limit))
    if not arch_candidates:
        raise RuntimeError("No policy architecture candidates available.")

    model = None
    best_score = -10e9
    best_success = -1.0
    best_metrics: Dict[str, float] = {}
    history = []
    live_history = []
    started_at = time.time()
    total_trained_steps = 0
    best_path = out_prefix.with_name(f"{out_prefix.name}_best.zip")
    latest_path = out_prefix.with_name(f"{out_prefix.name}_latest.zip")
    interrupted = False

    print("[auto_train_anna] stages=%s" % json.dumps(stages, sort_keys=True))
    print("[auto_train_anna] stage_round_steps=%s" % json.dumps(stage_round_steps, sort_keys=True))
    print("[auto_train_anna] eval_scene=%s base_timesteps_per_round=%d" % (eval_scene, base_timesteps_per_round))
    print(
        "[auto_train_anna] runtime: GODOT_BIN=%s prefer_server=%s fallback=%s rl_physics_fps=%s rl_poll_sleep_usec=%s rl_max_steps=%s"
        % (
            os.environ.get("GODOT_BIN", ""),
            os.environ.get("ANNA_GODOT_PREFER_SERVER", ""),
            os.environ.get("ANNA_GODOT_SERVER_FALLBACK", ""),
            os.environ.get("ANNA_RL_PHYSICS_FPS", ""),
            os.environ.get("ANNA_RL_POLL_SLEEP_USEC", ""),
            os.environ.get("ANNA_RL_MAX_STEPS", ""),
        )
    )
    print("[auto_train_anna] eval runtime: eval_physics_fps=%d" % int(args.eval_physics_fps))
    print(
        "[auto_train_anna] size_cap=%.2fMB arch_candidates=%s"
        % (max_model_bytes / (1024.0 * 1024.0), json.dumps(arch_candidates))
    )

    # Probe model sizes once (cheap) and pick the largest architecture that fits the cap.
    probe_env = AnnaGymEnv(
        scene_path=str(stages[0]["scene"]),
        port=int(stages[0]["port"]),
        launch_godot=True,
        headless=True,
    )
    try:
        selected_arch, arch_probes = _pick_best_arch_under_cap(
            PPO=PPO,
            env=probe_env,
            out_prefix=out_prefix,
            arch_candidates=arch_candidates,
            max_model_bytes=max_model_bytes,
            seed=args.seed,
            ent_coef=float(args.entropy_coef),
            learning_rate=float(args.learning_rate),
        )
    finally:
        probe_env.close()

    print("[auto_train_anna] arch_probes=%s" % json.dumps(arch_probes, sort_keys=True))
    print("[auto_train_anna] selected_arch=%s" % json.dumps(selected_arch))
    rollout_steps = max(64, int(args.ppo_n_steps))
    # For current harness (single-env training), clamp batch to rollout size.
    ppo_batch_size = max(32, min(int(args.ppo_batch_size), rollout_steps))
    ppo_n_epochs = max(1, int(args.ppo_n_epochs))
    ppo_device = str(args.ppo_device).strip().lower() or "cpu"
    print(
        "[auto_train_anna] ppo n_steps=%d batch=%d n_epochs=%d device=%s"
        % (rollout_steps, ppo_batch_size, ppo_n_epochs, ppo_device)
    )
    print(
        "[auto_train_anna] live telemetry: report_steps=%d live_eval_episodes=%d live_eval_max_steps=%d save_latest=%s"
        % (
            int(args.live_report_steps),
            int(args.live_eval_episodes),
            int(args.live_eval_max_steps),
            str(bool(args.save_latest_per_live)),
        )
    )
    stage_unlock_enabled = bool(args.stage_unlock_by_success) and len(stages) > 1 and not str(args.scene).strip()
    unlocked_stage_count = 1 if stage_unlock_enabled else len(stages)
    stage_unlock_history = []
    if stage_unlock_enabled:
        print(
            "[auto_train_anna] stage unlock enabled: target=%.3f eval_episodes=%d max_steps=%d initial_stage=%s"
            % (
                float(args.stage_unlock_target),
                int(args.stage_unlock_eval_episodes),
                int(args.stage_unlock_max_steps),
                str(stages[0]["name"]),
            )
        )

    try:
        for rnd in range(1, max(1, args.rounds) + 1):
            round_seed = args.seed + rnd - 1
            np.random.seed(round_seed)
            random.seed(round_seed)
            torch.manual_seed(round_seed)
            round_trained_steps = 0

            for stage_idx, stage in enumerate(stages):
                if stage_idx >= int(unlocked_stage_count):
                    continue
                stage_scene = str(stage["scene"])
                stage_base_steps = int(stage["steps"])
                stage_port = int(stage["port"])
                stage_name = str(stage["name"])
                stage_schedule = stage_round_steps.get(stage_name, [])
                if rnd <= len(stage_schedule):
                    stage_steps = int(stage_schedule[rnd - 1])
                else:
                    stage_steps = _dynamic_stage_steps(
                        base_steps=stage_base_steps,
                        stage_idx=stage_idx,
                        stage_count=len(stages),
                        round_idx=rnd,
                        rounds_total=max(1, int(args.rounds)),
                        stage_growth=float(args.stage_growth),
                        max_stage_scale=float(args.max_stage_scale),
                    )
                print(
                    "[auto_train_anna] round=%d train %s scene=%s steps=%d (base=%d)"
                    % (rnd, stage_name, stage_scene, stage_steps, stage_base_steps)
                )
                train_env = _open_stage_env(
                    AnnaGymEnv=AnnaGymEnv,
                    Monitor=Monitor,
                    DummyVecEnv=DummyVecEnv,
                    SubprocVecEnv=SubprocVecEnv,
                    scene=stage_scene,
                    start_port=stage_port,
                    num_envs=max(1, int(args.num_envs)),
                    open_retries=max(1, int(args.stage_open_retries)),
                    retry_sleep_sec=float(args.stage_open_retry_sleep),
                )
                try:
                    if model is None:
                        init_model_path = Path(str(args.init_model)).expanduser() if str(args.init_model).strip() else None
                        if init_model_path is not None and init_model_path.exists():
                            try:
                                print("[auto_train_anna] warm start from: %s" % str(init_model_path))
                                model = PPO.load(
                                    str(init_model_path),
                                    env=train_env,
                                    device=ppo_device,
                                    print_system_info=False,
                                )
                                # Keep GA-selected optimization knobs even when warm-starting weights.
                                lr_value = float(args.learning_rate)
                                model.ent_coef = float(args.entropy_coef)
                                model.learning_rate = lr_value
                                model.lr_schedule = get_schedule_fn(lr_value)
                                if hasattr(model, "policy") and hasattr(model.policy, "optimizer"):
                                    for param_group in model.policy.optimizer.param_groups:
                                        param_group["lr"] = lr_value
                            except Exception as exc:
                                print("[auto_train_anna] warm start failed (%s), falling back to fresh init." % str(exc))
                                model = None
                        if model is None:
                            policy_kwargs = {"net_arch": dict(pi=list(selected_arch), vf=list(selected_arch))}
                            model = PPO(
                                "MlpPolicy",
                                train_env,
                                seed=round_seed,
                                verbose=args.verbose,
                                ent_coef=args.entropy_coef,
                                learning_rate=args.learning_rate,
                                policy_kwargs=policy_kwargs,
                                n_steps=rollout_steps,
                                batch_size=ppo_batch_size,
                                n_epochs=ppo_n_epochs,
                                device=ppo_device,
                            )
                    else:
                        model.set_env(train_env)

                    live_report_steps = int(args.live_report_steps)
                    use_chunks = live_report_steps > 0 and live_report_steps < stage_steps
                    stage_step_done = 0
                    stage_chunk_idx = 0
                    stage_chunk_total = (
                        int((stage_steps + live_report_steps - 1) / live_report_steps)
                        if use_chunks
                        else 1
                    )
                    while stage_step_done < stage_steps:
                        if use_chunks:
                            chunk_steps = min(live_report_steps, stage_steps - stage_step_done)
                        else:
                            chunk_steps = stage_steps - stage_step_done
                        stage_chunk_idx += 1
                        chunk_started = time.time()
                        model.learn(
                            total_timesteps=chunk_steps,
                            reset_num_timesteps=(total_trained_steps == 0),
                            progress_bar=False,
                        )
                        chunk_elapsed = max(1e-6, time.time() - chunk_started)
                        stage_step_done += chunk_steps
                        total_trained_steps += chunk_steps
                        round_trained_steps += chunk_steps

                        if use_chunks:
                            live_record = {
                                "round": int(rnd),
                                "stage": stage_name,
                                "stage_scene": stage_scene,
                                "chunk_index": int(stage_chunk_idx),
                                "chunk_total": int(stage_chunk_total),
                                "chunk_steps": int(chunk_steps),
                                "stage_steps_done": int(stage_step_done),
                                "stage_steps_total": int(stage_steps),
                                "timesteps_total": int(total_trained_steps),
                                "train_sps": float(chunk_steps / chunk_elapsed),
                                "elapsed_sec": round(chunk_elapsed, 3),
                            }
                            if int(args.live_eval_episodes) > 0:
                                live_port = _find_available_port_block(int(args.eval_port) + 300, 1, max_scan=2000)
                                live_eval_prev_env = _set_eval_runtime_tuning(int(args.eval_physics_fps))
                                live_eval_env = AnnaGymEnv(
                                    scene_path=stage_scene,
                                    port=live_port,
                                    launch_godot=True,
                                    headless=True,
                                )
                                try:
                                    live_metrics = _evaluate(
                                        model=model,
                                        env=live_eval_env,
                                        np=np,
                                        torch=torch,
                                        episodes=max(1, int(args.live_eval_episodes)),
                                        max_steps=max(50, int(args.live_eval_max_steps)),
                                        deterministic=not args.stochastic_eval,
                                        step_delay=0.0,
                                        wall_touch_ray_threshold=float(args.wall_touch_ray_threshold),
                                    )
                                finally:
                                    live_eval_env.close()
                                    _restore_runtime_tuning(live_eval_prev_env)
                                live_record["metrics"] = live_metrics
                                print(
                                    "[auto_train_anna][live] round=%d stage=%s chunk=%d/%d stage_steps=%d/%d total=%d sps=%.1f %s"
                                    % (
                                        rnd,
                                        stage_name,
                                        stage_chunk_idx,
                                        stage_chunk_total,
                                        stage_step_done,
                                        stage_steps,
                                        total_trained_steps,
                                        live_record["train_sps"],
                                        _format_live_metrics(live_metrics),
                                    )
                                )
                            else:
                                print(
                                    "[auto_train_anna][live] round=%d stage=%s chunk=%d/%d stage_steps=%d/%d total=%d sps=%.1f"
                                    % (
                                        rnd,
                                        stage_name,
                                        stage_chunk_idx,
                                        stage_chunk_total,
                                        stage_step_done,
                                        stage_steps,
                                        total_trained_steps,
                                        live_record["train_sps"],
                                    )
                                )
                            live_history.append(live_record)
                            if bool(args.save_latest_per_live):
                                model.save(str(latest_path.with_suffix("")), exclude=["policy.optimizer"])
                                print("[auto_train_anna][live] latest checkpoint: %s" % latest_path)
                finally:
                    train_env.close()

            eval_scene_round = eval_scene
            if stage_unlock_enabled and not str(args.eval_scene).strip():
                eval_scene_round = str(stages[max(0, int(unlocked_stage_count) - 1)]["scene"])

            eval_prev_env = _set_eval_runtime_tuning(int(args.eval_physics_fps))
            eval_env = AnnaGymEnv(
                scene_path=eval_scene_round,
                port=args.eval_port,
                launch_godot=True,
                headless=not args.render_eval,
            )
            try:
                metrics = _evaluate(
                    model=model,
                    env=eval_env,
                    np=np,
                    torch=torch,
                    episodes=args.eval_episodes,
                    max_steps=args.eval_max_steps,
                    deterministic=not args.stochastic_eval,
                    step_delay=args.step_delay,
                    wall_touch_ray_threshold=float(args.wall_touch_ray_threshold),
                )
            finally:
                eval_env.close()
                _restore_runtime_tuning(eval_prev_env)

            round_score = _score(metrics)
            record = {
                "round": rnd,
                "seed": round_seed,
                "timesteps_this_round": int(round_trained_steps),
                "timesteps_total": int(total_trained_steps),
                "eval_scene": eval_scene_round,
                "unlocked_stage_count": int(unlocked_stage_count),
                "unlocked_stage_name": str(stages[max(0, int(unlocked_stage_count) - 1)]["name"]),
                "score": round_score,
                **metrics,
            }
            history.append(record)
            print("[auto_train_anna] round=%d score=%.4f metrics=%s" % (rnd, round_score, json.dumps(metrics, sort_keys=True)))

            checkpoint_path = out_prefix.with_name(f"{out_prefix.name}_r{rnd}.zip")
            model.save(str(checkpoint_path.with_suffix("")), exclude=["policy.optimizer"])
            checkpoint_size = checkpoint_path.stat().st_size if checkpoint_path.exists() else 0
            checkpoint_fits_cap = checkpoint_size <= max_model_bytes
            print(
                "[auto_train_anna] round=%d checkpoint=%s size=%.3fMB fits_cap=%s"
                % (rnd, checkpoint_path.name, checkpoint_size / (1024.0 * 1024.0), checkpoint_fits_cap)
            )

            current_success = float(metrics.get("success_rate", 0.0))
            should_promote_best = False
            if checkpoint_fits_cap:
                # Prioritize real task completion over synthetic shaping score.
                if current_success > best_success + 1e-9:
                    should_promote_best = True
                elif abs(current_success - best_success) <= 1e-9 and round_score > best_score:
                    should_promote_best = True
            if should_promote_best:
                best_success = current_success
                best_score = round_score
                best_metrics = metrics
                best_path = out_prefix.with_name(f"{out_prefix.name}_best.zip")
                model.save(str(best_path.with_suffix("")), exclude=["policy.optimizer"])
                print(
                    "[auto_train_anna] new best model: %s (success_rate=%.3f score=%.4f)"
                    % (best_path, best_success, best_score)
                )
            elif not checkpoint_fits_cap:
                print("[auto_train_anna] size cap exceeded; skipping best-model promotion for this round.")

            if stage_unlock_enabled:
                gate_idx = max(0, int(unlocked_stage_count) - 1)
                gate_stage = stages[gate_idx]
                gate_scene = str(gate_stage["scene"])
                gate_port = _find_available_port_block(int(args.eval_port) + 600, 1, max_scan=2000)
                gate_prev_env = _set_eval_runtime_tuning(int(args.eval_physics_fps))
                gate_env = AnnaGymEnv(
                    scene_path=gate_scene,
                    port=gate_port,
                    launch_godot=True,
                    headless=True,
                )
                try:
                    gate_metrics = _evaluate(
                        model=model,
                        env=gate_env,
                        np=np,
                        torch=torch,
                        episodes=max(1, int(args.stage_unlock_eval_episodes)),
                        max_steps=max(50, int(args.stage_unlock_max_steps)),
                        deterministic=True,
                        step_delay=0.0,
                        wall_touch_ray_threshold=float(args.wall_touch_ray_threshold),
                    )
                finally:
                    gate_env.close()
                    _restore_runtime_tuning(gate_prev_env)

                gate_success = float(gate_metrics.get("success_rate", 0.0))
                gate_pass = gate_success >= float(args.stage_unlock_target)
                gate_event = {
                    "round": int(rnd),
                    "stage_index": int(gate_idx + 1),
                    "stage_name": str(gate_stage["name"]),
                    "stage_scene": gate_scene,
                    "success_rate": gate_success,
                    "target": float(args.stage_unlock_target),
                    "passed": bool(gate_pass),
                }
                record["stage_gate"] = gate_event
                stage_unlock_history.append(gate_event)
                print(
                    "[auto_train_anna][gate] round=%d stage=%s success=%.3f target=%.3f pass=%s"
                    % (rnd, gate_event["stage_name"], gate_success, float(args.stage_unlock_target), str(gate_pass))
                )
                if gate_pass and int(unlocked_stage_count) < len(stages):
                    unlocked_stage_count += 1
                    next_stage = stages[int(unlocked_stage_count) - 1]
                    print(
                        "[auto_train_anna][gate] unlocked stage %d/%d -> %s (%s)"
                        % (
                            int(unlocked_stage_count),
                            len(stages),
                            str(next_stage["name"]),
                            str(next_stage["scene"]),
                        )
                    )

            stop_by_target = (
                rnd >= args.min_rounds
                and (not stage_unlock_enabled or int(unlocked_stage_count) >= len(stages))
                and metrics["success_rate"] >= args.success_target
                and metrics["direction_score"] >= args.direction_target
                and metrics["fast_success_score"] >= args.fast_success_target
                and metrics["wall_touch_ratio"] <= args.wall_contact_max
                and metrics["collapse_forward"] < 0.5
            )
            if stop_by_target:
                print("[auto_train_anna] target reached at round %d, stopping early." % rnd)
                break
    except KeyboardInterrupt:
        interrupted = True
        print("[auto_train_anna] interrupted: persisting latest artifacts before exit.")
        if model is not None:
            interrupted_path = out_prefix.with_name(f"{out_prefix.name}_interrupted.zip")
            model.save(str(interrupted_path.with_suffix("")), exclude=["policy.optimizer"])
            model.save(str(latest_path.with_suffix("")), exclude=["policy.optimizer"])
            print("[auto_train_anna] interrupted checkpoint: %s" % interrupted_path)
            print("[auto_train_anna] latest checkpoint: %s" % latest_path)

    summary = {
        "scene": eval_scene,
        "stages": stages,
        "selected_arch": selected_arch,
        "arch_probes": arch_probes,
        "max_model_bytes": max_model_bytes,
        "max_model_mb": round(max_model_bytes / (1024.0 * 1024.0), 4),
        "rounds_completed": len(history),
        "timesteps_total": int(total_trained_steps),
        "best_score": best_score,
        "best_model": str(best_path),
        "best_model_exists": bool(best_path.exists()),
        "latest_model": str(latest_path),
        "latest_model_exists": bool(latest_path.exists()),
        "best_metrics": best_metrics,
        "history": history,
        "live_history": live_history,
        "stage_unlock_enabled": bool(stage_unlock_enabled),
        "unlocked_stage_count": int(unlocked_stage_count),
        "stage_unlock_history": stage_unlock_history,
        "interrupted": bool(interrupted),
        "config": vars(args),
        "duration_sec": round(time.time() - started_at, 3),
        "created_at_unix": int(time.time()),
    }
    summary_path = out_prefix.with_name(f"{out_prefix.name}_summary.json")
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print("[auto_train_anna] summary: %s" % summary_path)
    if not best_path.exists():
        print("[auto_train_anna] best model was not promoted (likely size cap or no completed round).")
    if latest_path.exists():
        print(
            "[auto_train_anna] watch latest: ANNA_GODOT_BIN=godot3-bin .venv/bin/python agents/eval_anna.py --model %s --scene %s --watch --render --cpu-threads %d"
            % (
                os.path.relpath(str(latest_path), str(repo_root)),
                eval_scene,
                max(1, int(args.cpu_threads)),
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
