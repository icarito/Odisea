#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
from stable_baselines3.common.vec_env import DummyVecEnv

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


class ThroughputCallback(BaseCallback):
    def __init__(
        self,
        log_every_steps: int = 2048,
        temp_read_path: str = "/sys/class/thermal/thermal_zone0/temp",
        temp_throttle_c: float = 86.0,
        temp_cooldown_s: float = 6.0,
    ):
        super().__init__()
        self.log_every_steps = max(256, int(log_every_steps))
        self.temp_read_path = str(temp_read_path)
        self.temp_throttle_c = float(temp_throttle_c)
        self.temp_cooldown_s = max(0.0, float(temp_cooldown_s))
        self._last_calls = 0
        self._last_time = 0.0

    def _on_training_start(self) -> None:
        self._last_calls = int(self.n_calls)
        self._last_time = time.time()

    def _read_cpu_temp_c(self) -> float:
        try:
            raw = Path(self.temp_read_path).read_text(encoding="utf-8").strip()
            val = float(raw)
            if val > 1000.0:
                val /= 1000.0
            return val
        except Exception:
            return -1.0

    def _on_step(self) -> bool:
        if (self.n_calls - self._last_calls) < self.log_every_steps:
            return True
        now = time.time()
        dt = max(1e-6, now - self._last_time)
        delta = self.n_calls - self._last_calls
        sps = float(delta) / dt
        temp_c = self._read_cpu_temp_c()
        if temp_c > 0.0:
            print(f"[monitor] steps={self.n_calls} sps={sps:.1f} temp_c={temp_c:.1f}")
        else:
            print(f"[monitor] steps={self.n_calls} sps={sps:.1f} temp_c=na")
        if self.temp_throttle_c > 0.0 and temp_c > 0.0 and temp_c >= self.temp_throttle_c and self.temp_cooldown_s > 0.0:
            print(
                "[monitor] thermal_guard temp=%.1fC >= %.1fC, cooling for %.1fs"
                % (temp_c, self.temp_throttle_c, self.temp_cooldown_s)
            )
            time.sleep(self.temp_cooldown_s)
        self._last_calls = self.n_calls
        self._last_time = now
        return True


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Fast RL1+RL2 training with high-SPS monitoring and SB3 tensor stats.")
    p.add_argument("--steps-rl1", type=int, default=30000)
    p.add_argument("--steps-rl2", type=int, default=60000)
    p.add_argument("--base-port", type=int, default=6200)
    p.add_argument("--cpu-threads", type=int, default=8)
    p.add_argument("--n-steps", type=int, default=4096)
    p.add_argument("--batch-size", type=int, default=4096)
    p.add_argument("--n-epochs", type=int, default=1)
    p.add_argument("--policy-width", type=int, default=128)
    p.add_argument("--policy-depth", type=int, default=2)
    p.add_argument("--learning-rate", type=float, default=6e-4)
    p.add_argument("--ent-coef", type=float, default=0.08)
    p.add_argument("--log-every", type=int, default=2048)
    p.add_argument("--temp-read-path", default="/sys/class/thermal/thermal_zone0/temp")
    p.add_argument("--temp-throttle-c", type=float, default=86.0, help="0 disables thermal throttling.")
    p.add_argument("--temp-cooldown-s", type=float, default=6.0)
    p.add_argument("--log-file", default="/tmp/rl12_fast_monitor.log")
    p.add_argument("--model-out", default="core_v2/trained_models/rl12_fast_monitor_best.zip")
    return p.parse_args()


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


def _set_eval_60hz() -> dict:
    keys = [
        "ANNA_RL_TARGET_FPS",
        "ANNA_RL_PHYSICS_FPS",
        "ANNA_RL_PHYSICS_FPS_CAP",
        "ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME",
    ]
    prev = {k: os.environ.get(k) for k in keys}
    os.environ["ANNA_RL_TARGET_FPS"] = "60"
    os.environ["ANNA_RL_PHYSICS_FPS"] = "60"
    os.environ["ANNA_RL_PHYSICS_FPS_CAP"] = "60"
    os.environ["ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME"] = "8"
    return prev


def _restore_env(prev: dict) -> None:
    for key, value in prev.items():
        if value is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = value


def _make_env(scene_path: str, port: int):
    return DummyVecEnv(
        [
            lambda: AnnaGymEnv(
                scene_path=scene_path,
                port=port,
                launch_godot=True,
                headless=True,
            )
        ]
    )


def _eval_model(model, scene_path: str, port: int, episodes: int = 5, max_steps: int = 1200) -> float:
    prev = _set_eval_60hz()
    env = AnnaGymEnv(scene_path=scene_path, port=port, launch_godot=True, headless=True)
    try:
        success = 0
        for _ in range(max(1, int(episodes))):
            obs, _ = env.reset()
            done = False
            steps = 0
            while not done and steps < int(max_steps):
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, _ = env.step(int(action))
                done = bool(terminated or truncated)
                steps += 1
                if terminated and float(reward) > 0.0:
                    success += 1
                    break
        return success / float(max(1, int(episodes)))
    finally:
        env.close()
        _restore_env(prev)


def main() -> int:
    args = _parse_args()
    log_path = Path(args.log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_file = log_path.open("w", encoding="utf-8", buffering=1)
    sys.stdout = _TeeStream(sys.__stdout__, log_file)
    sys.stderr = _TeeStream(sys.__stderr__, log_file)

    _set_runtime_env(args.cpu_threads)
    try:
        import torch
        torch.set_num_threads(max(1, int(args.cpu_threads)))
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass
    model_out = Path(args.model_out)
    model_out.parent.mkdir(parents=True, exist_ok=True)

    print("[train_rl12_fast] server_required=1 video_driver=<none> audio_driver_flag=disabled binary_protocol=1")
    print(
        "[train_rl12_fast] train_runtime physics=%s cap=%s target=%s"
        % (
            os.environ.get("ANNA_RL_PHYSICS_FPS", ""),
            os.environ.get("ANNA_RL_PHYSICS_FPS_CAP", ""),
            os.environ.get("ANNA_RL_TARGET_FPS", ""),
        )
    )
    print(
        "[train_rl12_fast] thermal_guard path=%s throttle_c=%.1f cooldown_s=%.1f"
        % (args.temp_read_path, float(args.temp_throttle_c), float(args.temp_cooldown_s))
    )

    stage1 = "core_v2/tests/TestScene_RL.tscn"
    stage2 = "core_v2/tests/TestScene_RL_2.tscn"
    cb = ThroughputCallback(
        log_every_steps=args.log_every,
        temp_read_path=args.temp_read_path,
        temp_throttle_c=args.temp_throttle_c,
        temp_cooldown_s=args.temp_cooldown_s,
    )

    arch = [max(16, int(args.policy_width))] * max(1, int(args.policy_depth))
    env = _make_env(stage1, int(args.base_port))
    model = PPO(
        "MlpPolicy",
        env,
        n_steps=max(256, int(args.n_steps)),
        batch_size=max(256, int(args.batch_size)),
        n_epochs=max(1, int(args.n_epochs)),
        learning_rate=float(args.learning_rate),
        ent_coef=float(args.ent_coef),
        policy_kwargs={"net_arch": dict(pi=list(arch), vf=list(arch))},
        verbose=1,
        device="cpu",
    )
    print(f"[train_rl12_fast] stage=RL1 steps={int(args.steps_rl1)}")
    model.learn(total_timesteps=max(1024, int(args.steps_rl1)), callback=cb, progress_bar=False)
    env.close()

    s1 = _eval_model(model, stage1, int(args.base_port) + 50, episodes=5, max_steps=1200)
    print(f"[train_rl12_fast] eval_60hz RL1 success_rate={s1:.3f}")

    env = _make_env(stage2, int(args.base_port) + 1)
    model.set_env(env)
    print(f"[train_rl12_fast] stage=RL2 steps={int(args.steps_rl2)}")
    model.learn(total_timesteps=max(1024, int(args.steps_rl2)), callback=cb, progress_bar=False)
    env.close()

    s2 = _eval_model(model, stage2, int(args.base_port) + 60, episodes=8, max_steps=1200)
    print(f"[train_rl12_fast] eval_60hz RL2 success_rate={s2:.3f}")

    model.save(str(model_out.with_suffix("")), exclude=["policy.optimizer"])
    print(f"[train_rl12_fast] saved={model_out}")
    print(f"[train_rl12_fast] log_file={log_path}")
    log_file.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
