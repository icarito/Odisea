#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv

sys.path.insert(0, "core_v2/anna/client")
from anna_gym import AnnaGymEnv  # noqa: E402


class _TeeStream:
    def __init__(self, *streams):
        self._streams = streams

    def write(self, data):
        for stream in self._streams:
            try:
                stream.write(data)
            except Exception:
                pass
        return len(data)

    def flush(self):
        for stream in self._streams:
            try:
                stream.flush()
            except Exception:
                pass


def _parse_int_list(raw: str, fallback: List[int]) -> List[int]:
    out: List[int] = []
    for token in str(raw).split(","):
        token = token.strip()
        if not token:
            continue
        try:
            val = int(token)
        except ValueError:
            continue
        if val > 0:
            out.append(val)
    if not out:
        out = list(fallback)
    return sorted(set(out))


def _read_temp_c(path: str) -> float:
    try:
        raw = Path(path).read_text(encoding="utf-8").strip()
        val = float(raw)
        if val > 1000.0:
            val /= 1000.0
        return val
    except Exception:
        return -1.0


class BenchCallback(BaseCallback):
    def __init__(self, report_every_ts: int, temp_path: str):
        super().__init__()
        self.report_every_ts = max(2048, int(report_every_ts))
        self.temp_path = str(temp_path)
        self._last_ts = 0
        self._last_t = 0.0
        self.max_temp_c = -1.0
        self.sps_samples: List[float] = []

    def _on_training_start(self) -> None:
        self._last_ts = int(self.model.num_timesteps)
        self._last_t = time.time()

    def _on_step(self) -> bool:
        now_ts = int(self.model.num_timesteps)
        if (now_ts - self._last_ts) < self.report_every_ts:
            return True
        now_t = time.time()
        dt = max(1e-6, now_t - self._last_t)
        dts = max(1, now_ts - self._last_ts)
        sps = float(dts) / dt
        self.sps_samples.append(float(sps))
        temp_c = _read_temp_c(self.temp_path)
        if temp_c > self.max_temp_c:
            self.max_temp_c = temp_c
        if temp_c > 0.0:
            print(f"[bench] timesteps={now_ts} sps={sps:.1f} temp_c={temp_c:.1f}")
        else:
            print(f"[bench] timesteps={now_ts} sps={sps:.1f} temp_c=na")
        self._last_ts = now_ts
        self._last_t = now_t
        return True

    def mean_sps(self) -> float:
        if not self.sps_samples:
            return 0.0
        return float(sum(self.sps_samples) / max(1, len(self.sps_samples)))


@dataclass
class BenchConfig:
    num_envs: int
    n_steps: int
    batch_size: int
    n_epochs: int
    policy_width: int
    policy_depth: int
    repeat: int


def _set_runtime_env(cpu_threads: int) -> None:
    threads = str(max(1, int(cpu_threads)))
    os.environ["OMP_NUM_THREADS"] = threads
    os.environ["MKL_NUM_THREADS"] = threads
    os.environ["OPENBLAS_NUM_THREADS"] = threads
    os.environ["NUMEXPR_NUM_THREADS"] = threads
    os.environ["ANNA_GODOT_PREFER_SERVER"] = "1"
    os.environ["ANNA_GODOT_REQUIRE_SERVER"] = "1"
    os.environ["ANNA_GODOT_SERVER_FALLBACK"] = "0"
    os.environ["ANNA_GODOT_SERVER_VIDEO_DRIVER"] = ""
    os.environ["ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG"] = "1"
    os.environ["ANNA_GODOT_DISABLE_RENDER_LOOP"] = "1"
    os.environ["ANNA_RL_DISABLE_CPU_SLEEP"] = "1"
    os.environ["ANNA_RL_POLL_SLEEP_USEC"] = "0"
    os.environ["ANNA_RL_BINARY_PROTOCOL"] = "1"
    os.environ["ANNA_RL_PHYSICS_FPS"] = "0"
    os.environ["ANNA_RL_TARGET_FPS"] = "0"
    os.environ["ANNA_RL_PHYSICS_FPS_CAP"] = "6000"
    os.environ["ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME"] = "128"


def _build_vec_env(scene: str, base_port: int, num_envs: int, vec_mode: str, start_method: str):
    env_fns = []
    for idx in range(num_envs):
        port = int(base_port) + idx

        def _make(p=port):
            env = AnnaGymEnv(
                scene_path=scene,
                port=p,
                launch_godot=True,
                headless=True,
            )
            return Monitor(env)

        env_fns.append(_make)
    if vec_mode == "dummy":
        return DummyVecEnv(env_fns)
    if num_envs <= 1:
        return DummyVecEnv(env_fns)
    return SubprocVecEnv(env_fns, start_method=start_method)


def _extract_logger_metrics(model: PPO) -> Dict[str, float]:
    out: Dict[str, float] = {}
    raw = getattr(model.logger, "name_to_value", {}) or {}
    keys = [
        "time/fps",
        "train/entropy_loss",
        "train/explained_variance",
        "train/approx_kl",
        "train/value_loss",
        "train/loss",
        "train/policy_gradient_loss",
    ]
    for k in keys:
        try:
            out[k] = float(raw.get(k))
        except Exception:
            continue
    return out


def _thermal_score(sps: float, max_temp_c: float, target_c: float) -> float:
    if max_temp_c <= 0.0 or target_c <= 0.0 or max_temp_c <= target_c:
        return float(sps)
    over = max_temp_c - target_c
    penalty = min(0.7, over * 0.03)
    return float(sps) * (1.0 - penalty)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Benchmark multi-env sweet spot for ANNA PPO training throughput.")
    p.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    p.add_argument("--base-port", type=int, default=7000)
    p.add_argument("--total-timesteps", type=int, default=131072)
    p.add_argument("--env-counts", default="1,2,3,4")
    p.add_argument("--n-steps-list", default="2048,4096,8192")
    p.add_argument("--n-epochs", type=int, default=1)
    p.add_argument("--policy-width", type=int, default=64)
    p.add_argument("--policy-depth", type=int, default=1)
    p.add_argument("--learning-rate", type=float, default=6e-4)
    p.add_argument("--ent-coef", type=float, default=0.08)
    p.add_argument("--cpu-threads", type=int, default=8)
    p.add_argument("--vec-mode", choices=["auto", "dummy", "subproc"], default="auto")
    p.add_argument("--subproc-start-method", choices=["fork", "spawn", "forkserver"], default="fork")
    p.add_argument("--repeats", type=int, default=1)
    p.add_argument("--report-every-ts", type=int, default=8192)
    p.add_argument("--temp-read-path", default="/sys/class/thermal/thermal_zone0/temp")
    p.add_argument("--temp-target-c", type=float, default=84.0)
    p.add_argument("--log-file", default="/tmp/anna_multi_env_benchmark.log")
    p.add_argument("--out-json", default="/tmp/anna_multi_env_benchmark_latest.json")
    p.add_argument("--out-csv", default="/tmp/anna_multi_env_benchmark_latest.csv")
    return p.parse_args()


def main() -> int:
    args = _parse_args()
    log_path = Path(args.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("w", encoding="utf-8", buffering=1)
    sys.stdout = _TeeStream(sys.__stdout__, log_file)
    sys.stderr = _TeeStream(sys.__stderr__, log_file)

    _set_runtime_env(int(args.cpu_threads))

    try:
        import torch
        torch.set_num_threads(max(1, int(args.cpu_threads)))
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass

    env_counts = _parse_int_list(args.env_counts, fallback=[1, 2, 3, 4])
    n_steps_list = _parse_int_list(args.n_steps_list, fallback=[2048, 4096, 8192])
    repeats = max(1, int(args.repeats))
    total_ts = max(8192, int(args.total_timesteps))
    scene = str(args.scene)

    print(
        "[bench] start scene=%s total_timesteps=%d env_counts=%s n_steps_list=%s repeats=%d cpu_threads=%d"
        % (scene, total_ts, env_counts, n_steps_list, repeats, int(args.cpu_threads))
    )
    print(
        "[bench] runtime godot_server=required physics=%s cap=%s binary=%s"
        % (
            os.environ.get("ANNA_RL_PHYSICS_FPS", ""),
            os.environ.get("ANNA_RL_PHYSICS_FPS_CAP", ""),
            os.environ.get("ANNA_RL_BINARY_PROTOCOL", ""),
        )
    )
    print(
        "[bench] vec_mode=%s subproc_start_method=%s"
        % (str(args.vec_mode), str(args.subproc_start_method))
    )

    records: List[Dict[str, float]] = []
    cfg_idx = 0
    for num_envs in env_counts:
        for n_steps in n_steps_list:
            for rep in range(1, repeats + 1):
                cfg_idx += 1
                rollout = int(num_envs) * int(n_steps)
                batch_size = max(256, rollout)
                cfg = BenchConfig(
                    num_envs=int(num_envs),
                    n_steps=int(n_steps),
                    batch_size=int(batch_size),
                    n_epochs=max(1, int(args.n_epochs)),
                    policy_width=max(16, int(args.policy_width)),
                    policy_depth=max(1, int(args.policy_depth)),
                    repeat=rep,
                )
                run_port = int(args.base_port) + (cfg_idx * 20)
                print(
                    "\n[bench] run=%d num_envs=%d n_steps=%d batch=%d rep=%d port_base=%d"
                    % (cfg_idx, cfg.num_envs, cfg.n_steps, cfg.batch_size, cfg.repeat, run_port)
                )
                vec_mode = str(args.vec_mode)
                if vec_mode == "auto":
                    vec_mode = "dummy" if cfg.num_envs <= 1 else "subproc"
                env = _build_vec_env(
                    scene=scene,
                    base_port=run_port,
                    num_envs=cfg.num_envs,
                    vec_mode=vec_mode,
                    start_method=str(args.subproc_start_method),
                )
                cb = BenchCallback(report_every_ts=int(args.report_every_ts), temp_path=args.temp_read_path)
                model = PPO(
                    "MlpPolicy",
                    env,
                    n_steps=cfg.n_steps,
                    batch_size=cfg.batch_size,
                    n_epochs=cfg.n_epochs,
                    learning_rate=float(args.learning_rate),
                    ent_coef=float(args.ent_coef),
                    policy_kwargs={
                        "net_arch": dict(
                            pi=[cfg.policy_width] * cfg.policy_depth,
                            vf=[cfg.policy_width] * cfg.policy_depth,
                        )
                    },
                    verbose=1,
                    device="cpu",
                )
                started = time.time()
                try:
                    model.learn(total_timesteps=total_ts, progress_bar=False, callback=cb)
                    elapsed = max(1e-6, time.time() - started)
                    agg_sps = float(total_ts) / elapsed
                    stable_sps = float(cb.mean_sps())
                    logger_metrics = _extract_logger_metrics(model)
                    max_temp = float(cb.max_temp_c)
                    score_base = stable_sps if stable_sps > 0.0 else agg_sps
                    score = _thermal_score(score_base, max_temp, float(args.temp_target_c))
                    row = {
                        "num_envs": float(cfg.num_envs),
                        "n_steps": float(cfg.n_steps),
                        "batch_size": float(cfg.batch_size),
                        "repeat": float(cfg.repeat),
                        "timesteps": float(total_ts),
                        "elapsed_sec": float(elapsed),
                        "agg_sps": float(agg_sps),
                        "stable_sps": float(stable_sps),
                        "max_temp_c": float(max_temp),
                        "thermal_score": float(score),
                        "sb3_fps": float(logger_metrics.get("time/fps", 0.0)),
                        "entropy_loss": float(logger_metrics.get("train/entropy_loss", 0.0)),
                        "explained_variance": float(logger_metrics.get("train/explained_variance", 0.0)),
                        "approx_kl": float(logger_metrics.get("train/approx_kl", 0.0)),
                        "value_loss": float(logger_metrics.get("train/value_loss", 0.0)),
                        "loss": float(logger_metrics.get("train/loss", 0.0)),
                    }
                    records.append(row)
                    print(
                        "[bench] done num_envs=%d n_steps=%d rep=%d agg_sps=%.1f stable_sps=%.1f sb3_fps=%.1f temp_max=%.1f score=%.1f"
                        % (
                            cfg.num_envs,
                            cfg.n_steps,
                            cfg.repeat,
                            row["agg_sps"],
                            row["stable_sps"],
                            row["sb3_fps"],
                            row["max_temp_c"],
                            row["thermal_score"],
                        )
                    )
                finally:
                    try:
                        env.close()
                    except Exception:
                        pass

    if not records:
        print("[bench] no results")
        return 1

    records_sorted = sorted(records, key=lambda x: x["thermal_score"], reverse=True)
    best = records_sorted[0]

    # Aggregate by (num_envs, n_steps) for cleaner recommendation.
    grouped: Dict[str, Dict[str, float]] = {}
    for row in records:
        key = "%d|%d" % (int(row["num_envs"]), int(row["n_steps"]))
        bucket = grouped.setdefault(
            key,
            {
                "num_envs": row["num_envs"],
                "n_steps": row["n_steps"],
                "runs": 0.0,
                "agg_sps_sum": 0.0,
                "stable_sps_sum": 0.0,
                "thermal_score_sum": 0.0,
                "max_temp_c_max": -1.0,
            },
        )
        bucket["runs"] += 1.0
        bucket["agg_sps_sum"] += row["agg_sps"]
        bucket["stable_sps_sum"] += row["stable_sps"]
        bucket["thermal_score_sum"] += row["thermal_score"]
        if row["max_temp_c"] > bucket["max_temp_c_max"]:
            bucket["max_temp_c_max"] = row["max_temp_c"]
    summary_rows: List[Dict[str, float]] = []
    for key, bucket in grouped.items():
        runs = max(1.0, bucket["runs"])
        summary_rows.append(
            {
                "num_envs": bucket["num_envs"],
                "n_steps": bucket["n_steps"],
                "runs": runs,
                "avg_agg_sps": bucket["agg_sps_sum"] / runs,
                "avg_stable_sps": bucket["stable_sps_sum"] / runs,
                "avg_thermal_score": bucket["thermal_score_sum"] / runs,
                "max_temp_c": bucket["max_temp_c_max"],
            }
        )
    summary_rows.sort(key=lambda x: x["avg_thermal_score"], reverse=True)
    sweet = summary_rows[0]

    out_payload = {
        "args": vars(args),
        "best_single_run": best,
        "sweet_spot": sweet,
        "grouped": summary_rows,
        "runs": records_sorted,
        "generated_at_unix": time.time(),
    }

    out_json = Path(args.out_json)
    out_csv = Path(args.out_csv)
    out_json.write_text(json.dumps(out_payload, indent=2), encoding="utf-8")
    with out_csv.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "num_envs",
                "n_steps",
                "batch_size",
                "repeat",
                "timesteps",
                "elapsed_sec",
                "agg_sps",
                "stable_sps",
                "max_temp_c",
                "thermal_score",
                "sb3_fps",
                "entropy_loss",
                "explained_variance",
                "approx_kl",
                "value_loss",
                "loss",
            ],
        )
        writer.writeheader()
        for row in records_sorted:
            writer.writerow(row)

    print("\n[bench] top runs:")
    for row in records_sorted[:5]:
        print(
            "  envs=%d n_steps=%d rep=%d agg_sps=%.1f score=%.1f temp=%.1f sb3_fps=%.1f"
            % (
                int(row["num_envs"]),
                int(row["n_steps"]),
                int(row["repeat"]),
                row["agg_sps"],
                row["thermal_score"],
                row["max_temp_c"],
                row["sb3_fps"],
            )
        )
    print(
        "[bench] sweet_spot envs=%d n_steps=%d avg_agg_sps=%.1f avg_stable_sps=%.1f avg_score=%.1f max_temp=%.1f"
        % (
            int(sweet["num_envs"]),
            int(sweet["n_steps"]),
            float(sweet["avg_agg_sps"]),
            float(sweet["avg_stable_sps"]),
            float(sweet["avg_thermal_score"]),
            float(sweet["max_temp_c"]),
        )
    )
    print(f"[bench] outputs json={out_json} csv={out_csv} log={log_path}")
    log_file.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
