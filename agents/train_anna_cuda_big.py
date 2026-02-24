#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import shutil
import socket
import subprocess
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
    parser.add_argument("--scene-stage3", default="core_v2/tests/TestScene_RL_BaseTerrace.tscn")
    parser.add_argument("--timesteps-stage1", type=int, default=150000)
    parser.add_argument("--timesteps-stage2", type=int, default=650000)
    parser.add_argument("--timesteps-stage3", type=int, default=700000)
    parser.add_argument("--port-stage1", type=int, default=5000)
    parser.add_argument("--port-stage2", type=int, default=5200)
    parser.add_argument("--port-stage3", type=int, default=5400)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--cpu-threads", type=int, default=8)
    parser.add_argument("--num-envs", type=int, default=6, help="Parallel Godot envs per stage (unique ports are auto-assigned).")
    parser.add_argument("--num-envs-stage1", type=int, default=0, help="Optional override for stage1 env count.")
    parser.add_argument("--num-envs-stage2", type=int, default=0, help="Optional override for stage2 env count.")
    parser.add_argument("--num-envs-stage3", type=int, default=0, help="Optional override for stage3 env count.")
    parser.add_argument("--device", choices=["auto", "cuda", "cpu"], default="auto")
    parser.add_argument("--cuda-device-id", type=int, default=0)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot3-bin"))
    parser.add_argument("--skip-import-prewarm", action="store_true", help="Skip one-time Godot import warmup.")
    parser.add_argument("--import-timeout-sec", type=int, default=900)
    parser.add_argument("--learning-rate", type=float, default=2.5e-4)
    parser.add_argument("--entropy-coef", type=float, default=0.015)
    parser.add_argument("--gamma", type=float, default=0.995)
    parser.add_argument("--gae-lambda", type=float, default=0.98)
    parser.add_argument("--clip-range", type=float, default=0.2)
    parser.add_argument("--n-steps", type=int, default=4096)
    parser.add_argument("--batch-size", type=int, default=4096)
    parser.add_argument("--n-epochs", type=int, default=10)
    parser.add_argument("--net-arch", type=_parse_int_list, default="2048,2048,1024,512")
    parser.add_argument("--checkpoint-every", type=int, default=50000)
    # Stage 3 curriculum overrides (BaseTerrace-specific)
    parser.add_argument("--stage3-max-steps", type=int, default=800,
        help="Max episode steps for Stage 3 (shorter = faster credit assignment).")
    parser.add_argument("--stage3-spawn-x", type=float, default=5.0)
    parser.add_argument("--stage3-spawn-y", type=float, default=2.5)
    parser.add_argument("--stage3-spawn-z", type=float, default=15.0)
    parser.add_argument("--stage3-target-radius-min", type=float, default=4.0)
    parser.add_argument("--stage3-target-radius-max", type=float, default=10.0)
    parser.add_argument("--stage3-target-y", type=float, default=2.0)
    parser.add_argument(
        "--max-periodic-checkpoints",
        type=int,
        default=4,
        help="Keep only the latest N periodic checkpoints per run (0 disables pruning).",
    )
    parser.add_argument(
        "--resume",
        choices=["auto", "always", "never"],
        default=os.environ.get("ANNA_TRAIN_RESUME_MODE", "auto"),
        help="Resume from latest checkpoint in ckpt dir.",
    )
    parser.add_argument(
        "--resume-from",
        default="",
        help="Optional explicit checkpoint/model .zip path to resume from.",
    )
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


def _set_nvidia_prime_defaults() -> None:
    # Equivalent to:
    # __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia python agents/train_anna_cuda_big.py
    os.environ.setdefault("__NV_PRIME_RENDER_OFFLOAD", "1")
    os.environ.setdefault("__GLX_VENDOR_LIBRARY_NAME", "nvidia")


def _set_torch_cuda_defaults() -> None:
    # Throughput-oriented defaults for PPO MLP on CUDA nodes.
    os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "max_split_size_mb:256,garbage_collection_threshold:0.8")
    os.environ.setdefault("ANNA_CUDA_TF32", "1")
    os.environ.setdefault("ANNA_CUDNN_BENCHMARK", "1")
    os.environ.setdefault("ANNA_TORCH_MATMUL_PRECISION", "high")


def _set_rl_runtime_defaults() -> None:
    # 0 => uncapped preset in AnnaBridge (maps to a high fixed physics rate).
    os.environ.setdefault("ANNA_RL_PHYSICS_FPS", "0")
    os.environ.setdefault("ANNA_GODOT_PREFER_SERVER", "1")
    os.environ.setdefault("ANNA_GODOT_SERVER_FALLBACK", "0")
    os.environ.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "1")
    os.environ.setdefault("ODISEA_DISABLE_PERFMON_IN_RL", "1")
    os.environ.setdefault("ODISEA_QUIET_PERFMON", "1")
    os.environ.setdefault("ODISEA_DISABLE_FAKE_SHADOW", "1")
    os.environ.setdefault("ODISEA_DISABLE_SHADER_WARMUP", "1")
    os.environ.setdefault("ODISEA_DISABLE_SHADER_WARMUP_IN_RL", "1")


def _prepare_imports(repo_root: Path):
    client_dir = repo_root / "core_v2" / "anna" / "client"
    if str(client_dir) not in sys.path:
        sys.path.insert(0, str(client_dir))

    from anna_gym import AnnaGymEnv  # type: ignore
    from stable_baselines3 import PPO  # type: ignore
    from stable_baselines3.common.monitor import Monitor  # type: ignore
    from stable_baselines3.common.utils import get_schedule_fn  # type: ignore
    from stable_baselines3.common.vec_env import DummyVecEnv, SubprocVecEnv  # type: ignore
    import numpy as np  # type: ignore
    import torch  # type: ignore
    from torch import nn  # type: ignore

    return AnnaGymEnv, PPO, Monitor, DummyVecEnv, SubprocVecEnv, get_schedule_fn, np, torch, nn


def _configure_cuda_runtime(torch_mod) -> dict:
    tf32_enabled = str(os.environ.get("ANNA_CUDA_TF32", "1")).lower() in ("1", "true", "yes", "on")
    cudnn_benchmark = str(os.environ.get("ANNA_CUDNN_BENCHMARK", "1")).lower() in ("1", "true", "yes", "on")
    matmul_precision = str(os.environ.get("ANNA_TORCH_MATMUL_PRECISION", "high")).strip().lower() or "high"
    if matmul_precision not in ("highest", "high", "medium"):
        matmul_precision = "high"

    try:
        torch_mod.backends.cuda.matmul.allow_tf32 = tf32_enabled
    except Exception:
        pass
    try:
        torch_mod.backends.cudnn.allow_tf32 = tf32_enabled
    except Exception:
        pass
    try:
        torch_mod.backends.cudnn.benchmark = cudnn_benchmark
    except Exception:
        pass
    try:
        torch_mod.set_float32_matmul_precision(matmul_precision)
    except Exception:
        pass

    return {
        "cuda_tf32": bool(tf32_enabled),
        "cudnn_benchmark": bool(cudnn_benchmark),
        "matmul_precision": matmul_precision,
    }


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


def _resolve_godot_bin(godot_bin: str) -> str:
    candidate = str(godot_bin).strip() or "godot3-bin"
    if shutil.which(candidate):
        return candidate
    if candidate == "godot3-bin" and shutil.which("godot3"):
        return "godot3"
    raise RuntimeError("Godot binary not found: %s" % candidate)


def _run_import_prewarm(repo_root: Path, godot_bin: str, timeout_sec: int) -> bool:
    if "server" in Path(godot_bin).name:
        print("[train_anna_cuda_big] import prewarm skipped: server binary has no editor mode.")
        return False

    cmd = [godot_bin, "--editor", "--quit", "--path", str(repo_root), "--audio-driver", "Dummy", "--no-window"]
    if not os.environ.get("DISPLAY"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1024x768x24+120"] + cmd
    print("[train_anna_cuda_big] import prewarm: %s" % " ".join(cmd))
    strict = str(os.environ.get("ANNA_IMPORT_PREWARM_STRICT", "0")).lower() in ("1", "true", "yes")
    try:
        subprocess.run(cmd, check=True, cwd=str(repo_root), timeout=max(30, int(timeout_sec)))
        return True
    except Exception as e:
        if strict:
            raise
        print("[train_anna_cuda_big] WARNING: import prewarm failed (%s). Continuing without prewarm." % e)
        return False


def _build_env_factory(AnnaGymEnv, Monitor, scene: str, port: int, render: bool, no_launch: bool, godot_bin: str, extra_env: dict = None):
    def _make():
        if extra_env:
            import os as _os
            for k, v in extra_env.items():
                _os.environ[k] = str(v)
        env = AnnaGymEnv(
            scene_path=scene,
            port=int(port),
            launch_godot=not no_launch,
            headless=not render,
            godot_bin=godot_bin,
        )
        return Monitor(env)

    return _make


def _open_stage_env(
    AnnaGymEnv,
    Monitor,
    DummyVecEnv,
    SubprocVecEnv,
    scene: str,
    base_port: int,
    render: bool,
    no_launch: bool,
    godot_bin: str,
    num_envs: int,
    extra_env: dict = None,
):
    env_fns = []
    for idx in range(max(1, int(num_envs))):
        env_fns.append(
            _build_env_factory(
                AnnaGymEnv=AnnaGymEnv,
                Monitor=Monitor,
                scene=scene,
                port=int(base_port) + idx,
                render=render,
                no_launch=no_launch,
                godot_bin=godot_bin,
                extra_env=extra_env,
            )
        )
    if len(env_fns) > 1:
        return SubprocVecEnv(env_fns, start_method="spawn")
    return DummyVecEnv(env_fns)


def _fit_batch_size(rollout_size: int, batch_size: int) -> int:
    rollout_size = max(1, int(rollout_size))
    batch = max(1, min(int(batch_size), rollout_size))
    while batch > 1 and (rollout_size % batch) != 0:
        batch -= 1
    return batch


def _is_port_available(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", int(port)))
            return True
        except OSError:
            return False


def _find_available_port_block(start_port: int, block_size: int, max_scan: int = 4000) -> int:
    start = max(1024, int(start_port))
    size = max(1, int(block_size))
    for base in range(start, start + max(1, int(max_scan))):
        ok = True
        for port in range(base, base + size):
            if not _is_port_available(port):
                ok = False
                break
        if ok:
            return base
    raise RuntimeError(
        "Could not find %d consecutive free ports starting at %d (scan=%d)."
        % (size, start, int(max_scan))
    )


def _resolve_stage_env_count(scene_path: str, default_envs: int, override_envs: int, is_stage3: bool = False) -> int:
    if int(override_envs) > 0:
        return max(1, int(override_envs))
    default_envs = max(1, int(default_envs))
    if is_stage3 and "BaseTerrace" in str(scene_path):
        suggested = max(1, int(os.environ.get("ANNA_STAGE3_NUM_ENVS_DEFAULT", "2")))
        return min(default_envs, suggested)
    return default_envs


def _atomic_write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    tmp.replace(path)


def _safe_read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_model_zip_atomic(model, dst_zip: Path) -> None:
    dst_zip.parent.mkdir(parents=True, exist_ok=True)
    tmp_base = dst_zip.parent / (dst_zip.stem + ".tmp")
    tmp_zip = Path(str(tmp_base) + ".zip")
    for candidate in [tmp_base, tmp_zip]:
        if candidate.exists():
            candidate.unlink()
    model.save(str(tmp_base))
    # SB3 writes either "<path>.zip" (common) or exactly "<path>" depending on version/path handling.
    src_zip: Path | None = None
    if tmp_zip.exists():
        src_zip = tmp_zip
    elif tmp_base.exists():
        src_zip = tmp_base
    if src_zip is None:
        raise RuntimeError("Checkpoint not generated: %s or %s" % (tmp_zip, tmp_base))
    src_zip.replace(dst_zip)


def _prune_periodic_checkpoints(checkpoint_dir: Path, model_stem: str, keep: int) -> None:
    keep = max(0, int(keep))
    if keep <= 0:
        return
    periodic = sorted(checkpoint_dir.glob("%s_ts*.zip" % model_stem), key=lambda p: p.name)
    excess = len(periodic) - keep
    if excess <= 0:
        return
    for old_path in periodic[:excess]:
        try:
            old_path.unlink()
        except Exception:
            pass


def _apply_ppo_overrides(model, args: argparse.Namespace, get_schedule_fn) -> None:
    lr = float(args.learning_rate)
    model.learning_rate = lr
    model.lr_schedule = get_schedule_fn(lr)
    model.ent_coef = float(args.entropy_coef)
    model.clip_range = get_schedule_fn(float(args.clip_range))


def _norm_done(stage_targets: dict, raw_done: dict) -> dict:
    out = {}
    for name, target in stage_targets.items():
        try:
            val = int(raw_done.get(name, 0))
        except Exception:
            val = 0
        out[name] = max(0, min(int(target), val))
    return out


def main() -> int:
    args = _parse_args()
    _set_cpu_limits(args.cpu_threads)
    _set_nvidia_prime_defaults()
    _set_torch_cuda_defaults()
    _set_rl_runtime_defaults()

    repo_root = Path(__file__).resolve().parents[1]
    AnnaGymEnv, PPO, Monitor, DummyVecEnv, SubprocVecEnv, get_schedule_fn, np, torch, nn = _prepare_imports(repo_root)

    # Stage 3 specific environment variables (BaseTerrace curriculum)
    stage3_extra_env = {
        "ANNA_RL_MAX_STEPS": str(int(args.stage3_max_steps)),
        "ANNA_RL_SPAWN_X": str(float(args.stage3_spawn_x)),
        "ANNA_RL_SPAWN_Y": str(float(args.stage3_spawn_y)),
        "ANNA_RL_SPAWN_Z": str(float(args.stage3_spawn_z)),
        "ANNA_RL_TARGET_RADIUS_MIN": str(float(args.stage3_target_radius_min)),
        "ANNA_RL_TARGET_RADIUS_MAX": str(float(args.stage3_target_radius_max)),
        "ANNA_RL_TARGET_Y": str(float(args.stage3_target_y)),
    }
    print("[train_anna_cuda_big] Stage3 env overrides: %s" % stage3_extra_env)

    torch.set_num_threads(max(1, int(args.cpu_threads)))
    try:
        torch.set_num_interop_threads(max(1, int(args.cpu_threads)))
    except Exception:
        pass

    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    num_envs = max(1, int(args.num_envs))
    godot_bin = _resolve_godot_bin(args.godot_bin)
    print(
        "[train_anna_cuda_big] PRIME offload env: __NV_PRIME_RENDER_OFFLOAD=%s __GLX_VENDOR_LIBRARY_NAME=%s"
        % (
            os.environ.get("__NV_PRIME_RENDER_OFFLOAD", ""),
            os.environ.get("__GLX_VENDOR_LIBRARY_NAME", ""),
        )
    )

    device = _resolve_device(args, torch)
    if device.startswith("cuda"):
        cuda_id = int(args.cuda_device_id)
        if cuda_id >= torch.cuda.device_count():
            raise RuntimeError("Requested cuda device id %d but only %d devices detected." % (cuda_id, torch.cuda.device_count()))
        torch.cuda.set_device(cuda_id)
        torch.cuda.manual_seed_all(args.seed)
        cuda_runtime_cfg = _configure_cuda_runtime(torch)
        print("[train_anna_cuda_big] using CUDA: %s (%s)" % (device, torch.cuda.get_device_name(cuda_id)))
        print(
            "[train_anna_cuda_big] CUDA runtime: tf32=%s cudnn_benchmark=%s matmul_precision=%s"
            % (
                cuda_runtime_cfg["cuda_tf32"],
                cuda_runtime_cfg["cudnn_benchmark"],
                cuda_runtime_cfg["matmul_precision"],
            )
        )
    else:
        cuda_runtime_cfg = {
            "cuda_tf32": False,
            "cudnn_benchmark": False,
            "matmul_precision": "high",
        }
        print("[train_anna_cuda_big] using device: %s" % device)

    prewarm_succeeded = False
    if (not args.no_launch) and (not args.skip_import_prewarm):
        prewarm_succeeded = _run_import_prewarm(
            repo_root=repo_root,
            godot_bin=godot_bin,
            timeout_sec=int(args.import_timeout_sec),
        )

    scene_stage1 = _scene_rel(repo_root, args.scene_stage1)
    scene_stage2 = _scene_rel(repo_root, args.scene_stage2)
    scene_stage3 = _scene_rel(repo_root, args.scene_stage3)
    stage1_envs = _resolve_stage_env_count(scene_stage1, num_envs, args.num_envs_stage1, False)
    stage2_envs = _resolve_stage_env_count(scene_stage2, num_envs, args.num_envs_stage2, False)
    stage3_envs = _resolve_stage_env_count(scene_stage3, num_envs, args.num_envs_stage3, True)

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
    # Cleanup stale partial saves from interrupted runs.
    for stale in checkpoint_dir.glob("*.tmp"):
        try:
            stale.unlink()
        except Exception:
            pass
    checkpoint_latest_zip = checkpoint_dir / (model_stem + "_latest.zip")
    train_state_path = checkpoint_dir / (model_stem + "_train_state.json")

    policy_kwargs = {
        "net_arch": dict(pi=list(args.net_arch), vf=list(args.net_arch)),
        "activation_fn": nn.ReLU,
        "ortho_init": False,
    }
    stage_targets = {
        "stage1": int(steps_stage1),
        "stage2": int(steps_stage2),
        "stage3": int(steps_stage3),
    }
    stage_envs = {
        "stage1": int(stage1_envs),
        "stage2": int(stage2_envs),
        "stage3": int(stage3_envs),
    }
    stage_scenes = {
        "stage1": scene_stage1,
        "stage2": scene_stage2,
        "stage3": scene_stage3,
    }
    rollout_size = int(args.n_steps) * stage1_envs
    fitted_batch = _fit_batch_size(rollout_size=rollout_size, batch_size=int(args.batch_size))
    stage1_port = _find_available_port_block(int(args.port_stage1), stage1_envs)
    stage2_port = _find_available_port_block(max(int(args.port_stage2), stage1_port + stage1_envs + 16), stage2_envs)
    stage3_port = _find_available_port_block(max(int(args.port_stage3), stage2_port + stage2_envs + 16), stage3_envs)

    print("[train_anna_cuda_big] stage1=%s (%d)" % (scene_stage1, steps_stage1))
    print("[train_anna_cuda_big] stage2=%s (%d)" % (scene_stage2, steps_stage2))
    print("[train_anna_cuda_big] stage3=%s (%d)" % (scene_stage3, steps_stage3))
    print("[train_anna_cuda_big] envs: stage1=%d stage2=%d stage3=%d" % (stage1_envs, stage2_envs, stage3_envs))
    if stage1_port != int(args.port_stage1):
        print("[train_anna_cuda_big] port shift: stage1 %d -> %d" % (int(args.port_stage1), stage1_port))
    if stage2_port != int(args.port_stage2):
        print("[train_anna_cuda_big] port shift: stage2 %d -> %d" % (int(args.port_stage2), stage2_port))
    if stage3_port != int(args.port_stage3):
        print("[train_anna_cuda_big] port shift: stage3 %d -> %d" % (int(args.port_stage3), stage3_port))
    print("[train_anna_cuda_big] total=%d cpu_threads=%d num_envs=%d n_steps=%d rollout=%d batch=%d net_arch=%s" % (
        total_timesteps,
        args.cpu_threads,
        num_envs,
        int(args.n_steps),
        rollout_size,
        fitted_batch,
        args.net_arch,
    ))
    print("[train_anna_cuda_big] resume=%s" % str(args.resume))

    started_at = time.time()
    stage_ports = {
        "stage1": int(stage1_port),
        "stage2": int(stage2_port),
        "stage3": int(stage3_port),
    }
    stage_extra_env = {
        "stage1": {},
        "stage2": {},
        "stage3": stage3_extra_env,
    }
    stage_order = ["stage1", "stage2", "stage3"]

    resume_mode = str(args.resume).strip().lower()
    resume_from_arg = str(args.resume_from).strip()
    resume_source: Path | None = None
    state_raw = _safe_read_json(train_state_path)
    stage_done = _norm_done(stage_targets, state_raw.get("stage_done", {}))
    resumed = False

    if resume_from_arg:
        resume_source = (repo_root / resume_from_arg).resolve()
    elif resume_mode != "never" and checkpoint_latest_zip.exists():
        resume_source = checkpoint_latest_zip

    if resume_mode == "always" and (resume_source is None or not resume_source.exists()):
        raise RuntimeError(
            "Resume requested (--resume always) but no checkpoint was found at %s"
            % checkpoint_latest_zip
        )

    if resume_source is not None and not resume_source.exists():
        raise RuntimeError("Resume checkpoint not found: %s" % resume_source)

    if resume_source is not None:
        resumed = True
        print("[train_anna_cuda_big] resume checkpoint: %s" % resume_source)
        if state_raw:
            print("[train_anna_cuda_big] resume stage_done: %s" % stage_done)
        else:
            print("[train_anna_cuda_big] resume without train state; stage progress will restart from 0.")

    model = None
    first_learn_call = True

    for stage_name in stage_order:
        stage_target = int(stage_targets[stage_name])
        if stage_target <= 0:
            continue
        done_before = int(stage_done.get(stage_name, 0))
        if done_before >= stage_target:
            print("[train_anna_cuda_big] %s already complete (%d/%d), skipping." % (stage_name, done_before, stage_target))
            continue

        env = _open_stage_env(
            AnnaGymEnv,
            Monitor,
            DummyVecEnv,
            SubprocVecEnv,
            stage_scenes[stage_name],
            stage_ports[stage_name],
            args.render,
            args.no_launch,
            godot_bin,
            stage_envs[stage_name],
            extra_env=stage_extra_env[stage_name],
        )
        try:
            rollout_for_stage = int(args.n_steps) * int(stage_envs[stage_name])
            chunk_steps = max(int(args.checkpoint_every), rollout_for_stage)
            if model is None:
                if resume_source is not None:
                    print("[train_anna_cuda_big] loading model from checkpoint for %s..." % stage_name)
                    model = PPO.load(str(resume_source), env=env, device=device)
                    _apply_ppo_overrides(model, args, get_schedule_fn)
                    model.tensorboard_log = str(tb_log)
                    model.verbose = int(args.verbose)
                    print(
                        "[train_anna_cuda_big] resume overrides: lr=%.8f ent_coef=%.5f clip_range=%.3f"
                        % (float(args.learning_rate), float(args.entropy_coef), float(args.clip_range))
                    )
                    first_learn_call = False
                else:
                    model = PPO(
                        "MlpPolicy",
                        env,
                        verbose=int(args.verbose),
                        tensorboard_log=str(tb_log),
                        seed=int(args.seed),
                        learning_rate=float(args.learning_rate),
                        ent_coef=float(args.entropy_coef),
                        gamma=float(args.gamma),
                        gae_lambda=float(args.gae_lambda),
                        clip_range=float(args.clip_range),
                        n_steps=int(args.n_steps),
                        batch_size=fitted_batch,
                        n_epochs=int(args.n_epochs),
                        policy_kwargs=policy_kwargs,
                        device=device,
                    )
                    first_learn_call = True
            else:
                if int(getattr(model, "n_envs", 1)) != int(stage_envs[stage_name]):
                    print(
                        "[train_anna_cuda_big] env-count change %d -> %d; reloading model for %s"
                        % (int(getattr(model, "n_envs", 1)), int(stage_envs[stage_name]), stage_name)
                    )
                    _save_model_zip_atomic(model, checkpoint_latest_zip)
                    model = PPO.load(str(checkpoint_latest_zip), env=env, device=device)
                    _apply_ppo_overrides(model, args, get_schedule_fn)
                    model.tensorboard_log = str(tb_log)
                    model.verbose = int(args.verbose)
                    print(
                        "[train_anna_cuda_big] reload overrides: lr=%.8f ent_coef=%.5f clip_range=%.3f"
                        % (float(args.learning_rate), float(args.entropy_coef), float(args.clip_range))
                    )
                    first_learn_call = False
                else:
                    model.set_env(env)

            print("[train_anna_cuda_big] %s: target=%d already=%d chunk=%d rollout=%d" % (
                stage_name,
                stage_target,
                done_before,
                chunk_steps,
                rollout_for_stage,
            ))
            while int(stage_done.get(stage_name, 0)) < stage_target:
                remaining = stage_target - int(stage_done.get(stage_name, 0))
                run_steps = min(int(chunk_steps), int(remaining))
                before_ts = int(model.num_timesteps)
                model.learn(
                    total_timesteps=int(run_steps),
                    reset_num_timesteps=first_learn_call,
                    progress_bar=True,
                )
                first_learn_call = False
                gained = max(0, int(model.num_timesteps) - before_ts)
                if gained <= 0:
                    gained = int(run_steps)

                stage_done[stage_name] = min(stage_target, int(stage_done.get(stage_name, 0)) + int(gained))
                periodic_zip = checkpoint_dir / ("%s_ts%010d.zip" % (model_stem, int(model.num_timesteps)))
                _save_model_zip_atomic(model, periodic_zip)
                _save_model_zip_atomic(model, checkpoint_latest_zip)
                _prune_periodic_checkpoints(
                    checkpoint_dir=checkpoint_dir,
                    model_stem=model_stem,
                    keep=int(args.max_periodic_checkpoints),
                )
                state_payload = {
                    "version": 1,
                    "model_out": str(model_out),
                    "latest_checkpoint": str(checkpoint_latest_zip),
                    "periodic_checkpoint": str(periodic_zip),
                    "num_timesteps": int(model.num_timesteps),
                    "stage_done": dict(stage_done),
                    "stage_targets": dict(stage_targets),
                    "current_stage": stage_name,
                    "completed": all(int(stage_done[s]) >= int(stage_targets[s]) for s in stage_order),
                    "updated_at_unix": int(time.time()),
                }
                _atomic_write_json(train_state_path, state_payload)
                print(
                    "[train_anna_cuda_big] %s progress: %d/%d (global_ts=%d)"
                    % (stage_name, int(stage_done[stage_name]), stage_target, int(model.num_timesteps))
                )
        finally:
            env.close()

    if model is None:
        if resume_source is not None and resume_source.exists():
            print("[train_anna_cuda_big] All stages already complete; exporting from %s" % resume_source)
            model = PPO.load(str(resume_source), device=device)
            _apply_ppo_overrides(model, args, get_schedule_fn)
        else:
            raise RuntimeError("No stage executed; check timesteps and resume settings.")

    model.save(str(model_out.with_suffix("")))
    _save_model_zip_atomic(model, checkpoint_latest_zip)
    _atomic_write_json(
        train_state_path,
        {
            "version": 1,
            "model_out": str(model_out),
            "latest_checkpoint": str(checkpoint_latest_zip),
            "periodic_checkpoint": str(checkpoint_latest_zip),
            "num_timesteps": int(model.num_timesteps),
            "stage_done": dict(stage_done),
            "stage_targets": dict(stage_targets),
            "current_stage": "done",
            "completed": True,
            "updated_at_unix": int(time.time()),
        },
    )

    metadata = {
        "model": str(model_out),
        "device": device,
        "cuda_available": bool(torch.cuda.is_available()),
        "cuda_device_name": torch.cuda.get_device_name(int(args.cuda_device_id)) if device.startswith("cuda") else None,
        "cuda_tf32": bool(cuda_runtime_cfg.get("cuda_tf32", False)),
        "cudnn_benchmark": bool(cuda_runtime_cfg.get("cudnn_benchmark", False)),
        "matmul_precision": str(cuda_runtime_cfg.get("matmul_precision", "high")),
        "seed": int(args.seed),
        "cpu_threads": int(args.cpu_threads),
        "num_envs": int(num_envs),
        "num_envs_stage1": int(stage1_envs),
        "num_envs_stage2": int(stage2_envs),
        "num_envs_stage3": int(stage3_envs),
        "learning_rate": float(args.learning_rate),
        "entropy_coef": float(args.entropy_coef),
        "gamma": float(args.gamma),
        "gae_lambda": float(args.gae_lambda),
        "clip_range": float(args.clip_range),
        "n_steps": int(args.n_steps),
        "rollout_size": int(rollout_size),
        "batch_size": int(fitted_batch),
        "n_epochs": int(args.n_epochs),
        "net_arch": list(args.net_arch),
        "godot_bin": godot_bin,
        "import_prewarm_requested": not bool(args.skip_import_prewarm),
        "import_prewarm_succeeded": bool(prewarm_succeeded),
        "scene_stage1": scene_stage1,
        "scene_stage2": scene_stage2,
        "scene_stage3": scene_stage3,
        "timesteps_stage1": steps_stage1,
        "timesteps_stage2": steps_stage2,
        "timesteps_stage3": steps_stage3,
        "timesteps_total_requested": total_timesteps,
        "timesteps_total_trained": int(model.num_timesteps),
        "timesteps": int(model.num_timesteps),
        "port_stage1_requested": int(args.port_stage1),
        "port_stage2_requested": int(args.port_stage2),
        "port_stage3_requested": int(args.port_stage3),
        "port_stage1": int(stage1_port),
        "port_stage2": int(stage2_port),
        "port_stage3": int(stage3_port),
        "checkpoint_dir": str(checkpoint_dir),
        "checkpoint_latest": str(checkpoint_latest_zip),
        "train_state_path": str(train_state_path),
        "checkpoint_every": int(args.checkpoint_every),
        "resume_mode": resume_mode,
        "resume_source": str(resume_source) if resume_source is not None else None,
        "resumed": bool(resumed),
        "stage_done": dict(stage_done),
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
