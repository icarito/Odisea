#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path


DEFAULT_SCENES = {
    "stage1": "core_v2/tests/TestScene_RL.tscn",
    "stage2": "core_v2/tests/TestScene_RL_2.tscn",
    "stage3": "core_v2/tests/TestScene_RL_3.tscn",
    "stage4": "core_v2/tests/TestScene_RL_3_Door.tscn",
    "stage5": "core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn",
}


def _parse_layers(raw: str) -> list[dict]:
    out = []
    for token in str(raw).split(","):
        piece = token.strip().lower()
        if not piece:
            continue
        m = re.match(r"^(\d+)x(\d+)$", piece)
        if not m:
            continue
        out.append({"width": int(m.group(1)), "depth": int(m.group(2)), "name": piece})
    if not out:
        out = [
            {"width": 128, "depth": 2, "name": "128x2"},
            {"width": 160, "depth": 2, "name": "160x2"},
            {"width": 192, "depth": 2, "name": "192x2"},
            {"width": 192, "depth": 3, "name": "192x3"},
        ]
    return out


def _parse_stage_steps(raw: str) -> list[int]:
    vals = []
    for token in str(raw).split(","):
        tok = token.strip()
        if not tok:
            continue
        try:
            vals.append(max(1000, int(tok)))
        except ValueError:
            continue
    if len(vals) < 5:
        vals = [8000, 12000, 16000, 22000, 30000]
    return vals[:5]


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Overnight ANNA programmer curriculum runner (5-stage, thermal-safe).")
    p.add_argument("--hours", type=float, default=8.0)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--cpu-threads", type=int, default=6)
    p.add_argument("--num-envs", type=int, default=1)
    p.add_argument("--max-model-mb", type=float, default=3.0)
    p.add_argument("--layers", default="128x2,160x2,192x2,192x3")
    p.add_argument("--base-stage-steps", default="8000,12000,16000,22000,30000")
    p.add_argument("--layer-scale", type=float, default=1.35)
    p.add_argument("--base-rounds", type=int, default=2)
    p.add_argument("--eval-episodes", type=int, default=8)
    p.add_argument("--eval-max-steps", type=int, default=1500)
    p.add_argument("--rl-physics-fps", type=int, default=900)
    p.add_argument("--max-temp-c", type=float, default=80.0)
    p.add_argument("--resume-temp-c", type=float, default=75.0)
    p.add_argument("--temp-poll-sec", type=float, default=15.0)
    p.add_argument("--python-bin", default="python")
    p.add_argument("--run-dir", default="")
    p.add_argument("--models-dir", default="")
    p.add_argument("--scene-stage1", default=DEFAULT_SCENES["stage1"])
    p.add_argument("--scene-stage2", default=DEFAULT_SCENES["stage2"])
    p.add_argument("--scene-stage3", default=DEFAULT_SCENES["stage3"])
    p.add_argument("--scene-stage4", default=DEFAULT_SCENES["stage4"])
    p.add_argument("--scene-stage5", default=DEFAULT_SCENES["stage5"])
    p.add_argument("--verbose", type=int, default=1)
    return p.parse_args()


def _log(path: Path, msg: str) -> None:
    line = msg.rstrip()
    print(line)
    with path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def _cpu_temp_c() -> float | None:
    if shutil.which("sensors") is None:
        return None
    try:
        out = subprocess.check_output(["sensors"], text=True, stderr=subprocess.STDOUT)
    except Exception:
        return None
    vals = []
    for line in out.splitlines():
        # Read only the primary value after ":" and ignore "(high/crit)" thresholds.
        m = re.search(r":\s*([+-]?[0-9]+(?:\.[0-9]+)?)°C", line)
        if not m:
            continue
        v = float(m.group(1))
        if 0.0 < v < 130.0:
            vals.append(v)
    if not vals:
        return None
    return max(vals)


def _monitor_with_thermal(proc: subprocess.Popen, log_path: Path, max_temp_c: float, resume_temp_c: float, poll_sec: float) -> int:
    paused = False
    while True:
        rc = proc.poll()
        if rc is not None:
            return int(rc)
        t = _cpu_temp_c()
        if t is not None:
            if (not paused) and t >= max_temp_c:
                try:
                    os.killpg(proc.pid, signal.SIGSTOP)
                    paused = True
                    _log(log_path, f"[overnight] thermal pause at {t:.1f}C")
                except Exception:
                    paused = False
            elif paused and t <= resume_temp_c:
                try:
                    os.killpg(proc.pid, signal.SIGCONT)
                    paused = False
                    _log(log_path, f"[overnight] thermal resume at {t:.1f}C")
                except Exception:
                    pass
        time.sleep(max(1.0, float(poll_sec)))


def _run_and_monitor(cmd: list[str], env: dict, log_path: Path, max_temp_c: float, resume_temp_c: float, poll_sec: float) -> int:
    with log_path.open("w", encoding="utf-8") as lf:
        lf.write("# CMD: %s\n\n" % " ".join(cmd))
        lf.flush()
        proc = subprocess.Popen(
            cmd,
            cwd=str(Path(__file__).resolve().parents[1]),
            env=env,
            stdout=lf,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    return _monitor_with_thermal(proc, log_path, max_temp_c, resume_temp_c, poll_sec)


def _parse_eval_summary(path: Path) -> dict:
    out = {"episodes": 0, "avg_reward": -999999.0, "avg_len": 0.0, "success_rate": 0.0}
    if not path.exists():
        return out
    txt = path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"summary episodes=(\d+) avg_reward=([-0-9.]+) avg_len=([-0-9.]+) success_rate=([-0-9.]+)%", txt)
    if not m:
        return out
    out["episodes"] = int(m.group(1))
    out["avg_reward"] = float(m.group(2))
    out["avg_len"] = float(m.group(3))
    out["success_rate"] = float(m.group(4))
    return out


def _score_model(eval_rl3: dict, eval_door: dict, eval_rl4: dict) -> float:
    return (
        1.0 * float(eval_rl3["success_rate"])
        + 1.4 * float(eval_door["success_rate"])
        + 1.8 * float(eval_rl4["success_rate"])
        + 0.002 * float(eval_rl3["avg_reward"])
        + 0.0025 * float(eval_door["avg_reward"])
        + 0.003 * float(eval_rl4["avg_reward"])
    )


def main() -> int:
    args = _parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    stamp = time.strftime("%Y%m%d_%H%M%S")
    if args.run_dir:
        run_dir = Path(args.run_dir)
        if not run_dir.is_absolute():
            run_dir = repo_root / run_dir
    else:
        run_dir = repo_root / "agents" / "runs" / "overnight_programmer" / stamp
    if args.models_dir:
        models_dir = Path(args.models_dir)
        if not models_dir.is_absolute():
            models_dir = repo_root / models_dir
    else:
        models_dir = repo_root / "agents" / "models" / "programmer_overnight" / stamp
    logs_dir = run_dir / "logs"
    run_dir.mkdir(parents=True, exist_ok=True)
    models_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    manifest = run_dir / "manifest.log"
    deadline = time.time() + max(0.25, float(args.hours)) * 3600.0

    layers = _parse_layers(args.layers)
    base_steps = _parse_stage_steps(args.base_stage_steps)
    stage_scenes = {
        "stage1": str(args.scene_stage1),
        "stage2": str(args.scene_stage2),
        "stage3": str(args.scene_stage3),
        "stage4": str(args.scene_stage4),
        "stage5": str(args.scene_stage5),
    }

    _log(manifest, f"[overnight] run_dir={run_dir}")
    _log(manifest, f"[overnight] models_dir={models_dir}")
    _log(manifest, f"[overnight] deadline_unix={int(deadline)}")
    _log(manifest, f"[overnight] layers={layers}")

    leaderboard = []
    max_model_bytes = int(max(0.1, float(args.max_model_mb)) * 1024 * 1024)

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(max(1, int(args.cpu_threads)))
    env["MKL_NUM_THREADS"] = str(max(1, int(args.cpu_threads)))
    env["OPENBLAS_NUM_THREADS"] = str(max(1, int(args.cpu_threads)))
    env["NUMEXPR_NUM_THREADS"] = str(max(1, int(args.cpu_threads)))
    env.setdefault("GODOT_BIN", "godot3-server")
    env.setdefault("ANNA_GODOT_PREFER_SERVER", "1")
    env.setdefault("ANNA_GODOT_SERVER_FALLBACK", "0")
    env.setdefault("ANNA_GODOT_DISABLE_RENDER_LOOP", "1")
    env.setdefault("ANNA_GODOT_SERVER_VIDEO_DRIVER", "")
    env.setdefault("ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG", "1")
    env.setdefault("ANNA_RL_DISABLE_QODOT", "1")
    env["ANNA_RL_PHYSICS_FPS"] = str(int(args.rl_physics_fps))
    env["ANNA_RL_TARGET_FPS"] = str(int(args.rl_physics_fps))
    env["ANNA_RL_PHYSICS_FPS_CAP"] = str(int(args.rl_physics_fps))
    env.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "0")
    env.setdefault("ANNA_RL_POLL_SLEEP_USEC", "1000")

    for idx, layer in enumerate(layers, start=1):
        if time.time() >= deadline:
            _log(manifest, "[overnight] reached deadline before next layer.")
            break

        layer_name = layer["name"]
        stage_scale = float(args.layer_scale) ** float(idx - 1)
        rounds = max(1, int(args.base_rounds) + (idx - 1))
        stage_steps = [max(1000, int(round(v * stage_scale))) for v in base_steps]

        out_prefix = run_dir / "models" / f"anna_programmer_{idx:02d}_{layer_name}"
        out_prefix.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            args.python_bin,
            "-u",
            "agents/auto_train_anna.py",
            "--scene-stage1",
            stage_scenes["stage1"],
            "--scene-stage2",
            stage_scenes["stage2"],
            "--scene-stage3",
            stage_scenes["stage3"],
            "--scene-stage4",
            stage_scenes["stage4"],
            "--scene-stage5",
            stage_scenes["stage5"],
            "--timesteps-stage1",
            str(stage_steps[0]),
            "--timesteps-stage2",
            str(stage_steps[1]),
            "--timesteps-stage3",
            str(stage_steps[2]),
            "--timesteps-stage4",
            str(stage_steps[3]),
            "--timesteps-stage5",
            str(stage_steps[4]),
            "--rounds",
            str(rounds),
            "--train-port-stage1",
            str(5000 + (idx * 20)),
            "--train-port-stage2",
            str(5001 + (idx * 20)),
            "--train-port-stage3",
            str(5002 + (idx * 20)),
            "--train-port-stage4",
            str(5003 + (idx * 20)),
            "--train-port-stage5",
            str(5004 + (idx * 20)),
            "--eval-scene",
            stage_scenes["stage5"],
            "--eval-port",
            str(5600 + idx),
            "--eval-episodes",
            str(max(2, int(args.eval_episodes))),
            "--eval-max-steps",
            str(int(args.eval_max_steps)),
            "--policy-widths",
            str(layer["width"]),
            "--policy-depths",
            str(layer["depth"]),
            "--arch-limit",
            "1",
            "--max-model-mb",
            str(float(args.max_model_mb)),
            "--cpu-threads",
            str(int(args.cpu_threads)),
            "--num-envs",
            str(int(args.num_envs)),
            "--ppo-device",
            "cpu",
            "--rl-allow-cpu-sleep",
            "--rl-physics-fps",
            str(int(args.rl_physics_fps)),
            "--rl-max-steps",
            "1500",
            "--seed",
            str(int(args.seed) + idx),
            "--output-prefix",
            str(out_prefix.relative_to(repo_root)),
            "--verbose",
            str(int(args.verbose)),
        ]

        layer_log = logs_dir / f"layer_{idx:02d}_{layer_name}.log"
        _log(manifest, f"[overnight] layer={idx} arch={layer_name} steps={stage_steps} rounds={rounds}")
        rc = _run_and_monitor(cmd, env, layer_log, float(args.max_temp_c), float(args.resume_temp_c), float(args.temp_poll_sec))
        if rc != 0:
            _log(manifest, f"[overnight] layer {layer_name} failed rc={rc}")
            continue

        best_model = out_prefix.with_name(out_prefix.name + "_best.zip")
        summary_path = out_prefix.with_name(out_prefix.name + "_summary.json")
        if not best_model.exists():
            _log(manifest, f"[overnight] layer {layer_name} has no best model: {best_model}")
            continue

        size_bytes = best_model.stat().st_size
        if size_bytes > max_model_bytes:
            _log(manifest, f"[overnight] layer {layer_name} skipped, model > cap ({size_bytes} bytes)")
            continue

        eval_results = {}
        for scene_key in ("stage3", "stage4", "stage5"):
            scene_path = stage_scenes[scene_key]
            eval_log = logs_dir / f"layer_{idx:02d}_{layer_name}_{scene_key}_eval.log"
            eval_cmd = [
                args.python_bin,
                "-u",
                "agents/eval_anna.py",
                "--model",
                str(best_model.relative_to(repo_root)),
                "--scene",
                scene_path,
                "--headless",
                "--episodes",
                str(max(2, int(args.eval_episodes))),
                "--max-steps",
                str(int(args.eval_max_steps)),
                "--cpu-threads",
                str(max(1, int(args.cpu_threads // 2))),
                "--port",
                str(5900 + idx * 10 + (0 if scene_key == "stage3" else (1 if scene_key == "stage4" else 2))),
            ]
            rc_eval = _run_and_monitor(eval_cmd, env, eval_log, float(args.max_temp_c), float(args.resume_temp_c), float(args.temp_poll_sec))
            if rc_eval != 0:
                _log(manifest, f"[overnight] eval failed layer={layer_name} scene={scene_path} rc={rc_eval}")
            eval_results[scene_key] = _parse_eval_summary(eval_log)

        score = _score_model(eval_results["stage3"], eval_results["stage4"], eval_results["stage5"])

        record = {
            "layer_index": idx,
            "layer": layer_name,
            "width": int(layer["width"]),
            "depth": int(layer["depth"]),
            "rounds": int(rounds),
            "stage_steps": stage_steps,
            "best_model": str(best_model),
            "summary": str(summary_path),
            "size_bytes": int(size_bytes),
            "size_mb": round(size_bytes / (1024.0 * 1024.0), 4),
            "eval": eval_results,
            "score": float(score),
            "created_unix": int(time.time()),
        }
        leaderboard.append(record)
        leaderboard.sort(key=lambda r: float(r["score"]), reverse=True)

        top_dir = models_dir / "top_models"
        top_dir.mkdir(parents=True, exist_ok=True)
        for i, row in enumerate(leaderboard[:3], start=1):
            src = Path(row["best_model"])
            if not src.exists():
                continue
            dst = top_dir / f"rank_{i}_{Path(row['layer']).name}.zip"
            shutil.copy2(src, dst)
            row["top_model_copy"] = str(dst)

        (run_dir / "leaderboard.json").write_text(json.dumps(leaderboard, indent=2), encoding="utf-8")
        _log(manifest, f"[overnight] layer={layer_name} score={score:.3f} size_mb={record['size_mb']:.3f}")

    if leaderboard:
        best = leaderboard[0]
        best_txt = run_dir / "best_model.txt"
        best_txt.write_text(str(best.get("top_model_copy", best["best_model"])) + "\n", encoding="utf-8")
        _log(manifest, f"[overnight] best={best.get('layer')} score={best.get('score')}")
    else:
        _log(manifest, "[overnight] no successful layers produced a leaderboard entry.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
