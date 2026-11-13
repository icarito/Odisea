#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import time
from pathlib import Path


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Evolutionary search for RL3 runtime params with thermal guard.")
    p.add_argument("--minutes", type=int, default=30)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--cpu-threads", type=int, default=6)
    p.add_argument("--population", type=int, default=4, help="Candidates per generation.")
    p.add_argument("--train-steps", type=int, default=12000)
    p.add_argument("--eval-episodes-fast", type=int, default=6)
    p.add_argument("--eval-max-steps-fast", type=int, default=2400)
    p.add_argument("--eval-episodes-60hz", type=int, default=4)
    p.add_argument("--eval-max-steps-60hz", type=int, default=1200)
    p.add_argument("--fast-weight", type=float, default=0.65)
    p.add_argument("--hz60-weight", type=float, default=0.35)
    p.add_argument("--max-temp-c", type=float, default=82.0)
    p.add_argument("--resume-temp-c", type=float, default=76.0)
    p.add_argument("--temp-poll-sec", type=int, default=15)
    p.add_argument("--base-model", required=True)
    p.add_argument("--scene", default="core_v2/tests/TestScene_RL_3.tscn")
    p.add_argument("--run-dir", default="")
    p.add_argument("--python-bin", default="python")
    p.add_argument("--godot-bin", default="godot3-server")
    p.add_argument("--verbose", type=int, default=1)
    return p.parse_args()


def _get_cpu_temp_c() -> float | None:
    if shutil.which("sensors") is None:
        return None
    try:
        out = subprocess.check_output(["sensors"], text=True, stderr=subprocess.STDOUT)
    except Exception:
        return None
    vals = []
    for line in out.splitlines():
        head = line.split("(", 1)[0]
        m = re.search(r"([+-]?[0-9]+(?:\.[0-9]+)?)°C", head)
        if not m:
            continue
        v = float(m.group(1))
        if 0.0 < v < 130.0:
            vals.append(v)
    if not vals:
        return None
    return max(vals)


def _thermal_guard(args: argparse.Namespace, log_path: Path) -> None:
    while True:
        t = _get_cpu_temp_c()
        if t is None or t < float(args.max_temp_c):
            return
        _log(log_path, f"[evo] thermal guard: {t:.1f}C >= {args.max_temp_c:.1f}C; waiting...")
        time.sleep(max(1, int(args.temp_poll_sec)))
        t2 = _get_cpu_temp_c()
        if t2 is not None and t2 <= float(args.resume_temp_c):
            _log(log_path, f"[evo] thermal guard: resumed at {t2:.1f}C")
            return


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _default_genes() -> dict:
    return {
        "jump_target_above_y": 1.2,
        "jump_target_above_dist": 9.0,
        "jump_max_steer_angle": 0.45,
        "jump_ahead_dist": 1.85,
        "wall_contact_penalty": 0.05,
        "stuck_extra_penalty_scale": 0.015,
        "stuck_extra_penalty_cap": 0.50,
        "stuck_no_recovery_penalty": 0.18,
        "stuck_wall_fail_frames": 120,
        "hazard_contact_grace_frames": 24,
        "hazard_forward_press_penalty": 0.12,
        "spawn_alt_prob": 0.35,
        "target_radius_min": 6.0,
        "target_radius_max": 14.0,
        "learning_rate": 0.0004,
        "entropy_coef": 0.02,
        "n_epochs": 2,
    }


def _mutate(genes: dict, rng: random.Random) -> dict:
    g = dict(genes)
    if rng.random() < 0.85:
        g["jump_target_above_y"] = _clamp(g["jump_target_above_y"] + rng.uniform(-0.25, 0.25), 0.6, 2.4)
    if rng.random() < 0.85:
        g["jump_target_above_dist"] = _clamp(g["jump_target_above_dist"] + rng.uniform(-1.2, 1.2), 5.5, 13.0)
    if rng.random() < 0.85:
        g["jump_max_steer_angle"] = _clamp(g["jump_max_steer_angle"] + rng.uniform(-0.10, 0.10), 0.20, 0.85)
    if rng.random() < 0.65:
        g["jump_ahead_dist"] = _clamp(g["jump_ahead_dist"] + rng.uniform(-0.25, 0.25), 1.1, 2.8)
    if rng.random() < 0.75:
        g["wall_contact_penalty"] = _clamp(g["wall_contact_penalty"] + rng.uniform(-0.015, 0.02), 0.02, 0.14)
    if rng.random() < 0.75:
        g["stuck_extra_penalty_scale"] = _clamp(g["stuck_extra_penalty_scale"] + rng.uniform(-0.006, 0.006), 0.004, 0.05)
    if rng.random() < 0.75:
        g["stuck_extra_penalty_cap"] = _clamp(g["stuck_extra_penalty_cap"] + rng.uniform(-0.12, 0.12), 0.20, 1.20)
    if rng.random() < 0.75:
        g["stuck_no_recovery_penalty"] = _clamp(g["stuck_no_recovery_penalty"] + rng.uniform(-0.08, 0.08), 0.05, 0.60)
    if rng.random() < 0.70:
        g["stuck_wall_fail_frames"] = int(_clamp(int(g["stuck_wall_fail_frames"]) + rng.randint(-20, 20), 60, 220))
    if rng.random() < 0.70:
        g["hazard_contact_grace_frames"] = int(_clamp(int(g["hazard_contact_grace_frames"]) + rng.randint(-6, 6), 8, 60))
    if rng.random() < 0.70:
        g["hazard_forward_press_penalty"] = _clamp(g["hazard_forward_press_penalty"] + rng.uniform(-0.05, 0.05), 0.04, 0.40)
    if rng.random() < 0.65:
        g["spawn_alt_prob"] = _clamp(g["spawn_alt_prob"] + rng.uniform(-0.12, 0.12), 0.10, 0.65)
    if rng.random() < 0.60:
        g["target_radius_min"] = _clamp(g["target_radius_min"] + rng.uniform(-0.8, 0.8), 4.5, 9.0)
    if rng.random() < 0.60:
        g["target_radius_max"] = _clamp(g["target_radius_max"] + rng.uniform(-1.3, 1.3), 10.0, 18.0)
    if g["target_radius_max"] < (g["target_radius_min"] + 1.0):
        g["target_radius_max"] = g["target_radius_min"] + 1.0
    if rng.random() < 0.50:
        g["learning_rate"] = rng.choice([0.0003, 0.00035, 0.0004, 0.00045, 0.0005, 0.0006])
    if rng.random() < 0.50:
        g["entropy_coef"] = rng.choice([0.012, 0.016, 0.020, 0.024, 0.03])
    if rng.random() < 0.35:
        g["n_epochs"] = int(rng.choice([2, 3]))
    return g


def _candidate_env(args: argparse.Namespace, genes: dict, fast_mode: bool) -> dict:
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = str(int(args.cpu_threads))
    env["MKL_NUM_THREADS"] = str(int(args.cpu_threads))
    env["OPENBLAS_NUM_THREADS"] = str(int(args.cpu_threads))
    env["NUMEXPR_NUM_THREADS"] = str(int(args.cpu_threads))
    env["GODOT_BIN"] = args.godot_bin
    env["ANNA_GODOT_PREFER_SERVER"] = "1"
    env["ANNA_GODOT_SERVER_FALLBACK"] = "0"
    env["ANNA_GODOT_DISABLE_RENDER_LOOP"] = "1"
    env["ANNA_GODOT_SERVER_VIDEO_DRIVER"] = ""
    env["ANNA_RL_DISABLE_QODOT"] = "1"
    env["ANNA_RL_EXIT_ON_DISCONNECT"] = "0"
    env["ANNA_RL_SPAWN_X"] = "0"
    env["ANNA_RL_SPAWN_Y"] = "5.2"
    env["ANNA_RL_SPAWN_Z"] = "0"
    env["ANNA_RL_SPAWN_ALT_X"] = "0"
    env["ANNA_RL_SPAWN_ALT_Y"] = "2.2"
    env["ANNA_RL_SPAWN_ALT_Z"] = "0"
    env["ANNA_RL_SPAWN_ALT_PROB"] = f"{float(genes['spawn_alt_prob']):.4f}"
    env["ANNA_RL_TARGET_Y"] = "5.0"
    env["ANNA_RL_TARGET_RADIUS_MIN"] = f"{float(genes['target_radius_min']):.4f}"
    env["ANNA_RL_TARGET_RADIUS_MAX"] = f"{float(genes['target_radius_max']):.4f}"
    env["ANNA_RL_JUMP_TARGET_ABOVE_Y"] = f"{float(genes['jump_target_above_y']):.4f}"
    env["ANNA_RL_JUMP_TARGET_ABOVE_DIST"] = f"{float(genes['jump_target_above_dist']):.4f}"
    env["ANNA_RL_JUMP_MAX_STEER_ANGLE"] = f"{float(genes['jump_max_steer_angle']):.4f}"
    env["ANNA_RL_JUMP_AHEAD_DIST"] = f"{float(genes['jump_ahead_dist']):.4f}"
    env["ANNA_RL_WALL_CONTACT_PENALTY"] = f"{float(genes['wall_contact_penalty']):.4f}"
    env["ANNA_RL_STUCK_EXTRA_PENALTY_SCALE"] = f"{float(genes['stuck_extra_penalty_scale']):.4f}"
    env["ANNA_RL_STUCK_EXTRA_PENALTY_CAP"] = f"{float(genes['stuck_extra_penalty_cap']):.4f}"
    env["ANNA_RL_STUCK_NO_RECOVERY_PENALTY"] = f"{float(genes['stuck_no_recovery_penalty']):.4f}"
    env["ANNA_RL_STUCK_WALL_FAIL_FRAMES"] = str(int(genes["stuck_wall_fail_frames"]))
    env["ANNA_RL_HAZARD_CONTACT_GRACE_FRAMES"] = str(int(genes["hazard_contact_grace_frames"]))
    env["ANNA_RL_HAZARD_FORWARD_PRESS_PENALTY"] = f"{float(genes['hazard_forward_press_penalty']):.4f}"
    if fast_mode:
        env["ANNA_RL_PHYSICS_FPS"] = "2000"
        env["ANNA_RL_TARGET_FPS"] = "2000"
        env["ANNA_RL_PHYSICS_FPS_CAP"] = "2000"
        env["ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME"] = "64"
        env["ANNA_RL_DISABLE_CPU_SLEEP"] = "1"
        env["ANNA_RL_POLL_SLEEP_USEC"] = "0"
    else:
        env["ANNA_RL_PHYSICS_FPS"] = "60"
        env["ANNA_RL_TARGET_FPS"] = "60"
        env["ANNA_RL_PHYSICS_FPS_CAP"] = "60"
        env["ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME"] = "16"
        env["ANNA_RL_DISABLE_CPU_SLEEP"] = "0"
        env["ANNA_RL_POLL_SLEEP_USEC"] = "1000"
    return env


def _run_cmd(cmd: list[str], env: dict, log_path: Path, timeout: int = 0) -> int:
    with log_path.open("w", encoding="utf-8") as lf:
        lf.write("# CMD: %s\n\n" % " ".join(cmd))
        lf.flush()
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(Path(__file__).resolve().parents[1]),
                env=env,
                stdout=lf,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=(None if timeout <= 0 else timeout),
            )
            return int(proc.returncode)
        except subprocess.TimeoutExpired:
            lf.write("\n[TIMEOUT]\n")
            return 124


def _parse_eval_summary(path: Path) -> dict:
    out = {"episodes": 0, "avg_reward": -999999.0, "avg_len": 0.0, "success_rate": 0.0}
    if not path.exists():
        return out
    txt = path.read_text(encoding="utf-8", errors="ignore")
    m = re.search(
        r"summary episodes=(\d+) avg_reward=([-0-9.]+) avg_len=([-0-9.]+) success_rate=([-0-9.]+)%",
        txt,
    )
    if not m:
        return out
    out["episodes"] = int(m.group(1))
    out["avg_reward"] = float(m.group(2))
    out["avg_len"] = float(m.group(3))
    out["success_rate"] = float(m.group(4))
    return out


def _score(eval_fast: dict, eval_60: dict, fast_weight: float, hz60_weight: float) -> float:
    sf = eval_fast["success_rate"] * 1000.0 + eval_fast["avg_reward"]
    s60 = eval_60["success_rate"] * 1000.0 + eval_60["avg_reward"]
    return float(sf * fast_weight + s60 * hz60_weight)


def _log(log_path: Path, msg: str) -> None:
    line = msg.rstrip()
    print(line)
    with log_path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def main() -> int:
    args = _parse_args()
    rng = random.Random(int(args.seed))
    repo_root = Path(__file__).resolve().parents[1]
    base_model = (repo_root / args.base_model).resolve()
    if not base_model.exists():
        raise SystemExit("base model not found: %s" % base_model)

    stamp = time.strftime("%Y%m%d_%H%M%S")
    run_dir = Path(args.run_dir) if args.run_dir else (repo_root / "agents" / "runs" / f"evo_rl3_{stamp}")
    run_dir.mkdir(parents=True, exist_ok=True)
    models_dir = run_dir / "models"
    logs_dir = run_dir / "logs"
    models_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)
    manifest = run_dir / "manifest.log"

    deadline = time.time() + max(1, int(args.minutes)) * 60
    _log(manifest, f"[evo] run_dir={run_dir}")
    _log(manifest, f"[evo] base_model={base_model}")
    _log(manifest, f"[evo] budget_minutes={args.minutes} population={args.population} train_steps={args.train_steps}")
    _log(manifest, f"[evo] thermal max={args.max_temp_c} resume={args.resume_temp_c}")

    best_genes = _default_genes()
    best_model = base_model
    best_score = -1e18
    best_record = {}
    history = []
    generation = 0
    candidate_counter = 0

    while time.time() < deadline:
        generation += 1
        candidates = [best_genes]
        for _ in range(max(1, int(args.population)) - 1):
            candidates.append(_mutate(best_genes, rng))

        _log(manifest, f"[evo] generation={generation} candidates={len(candidates)}")

        for idx, genes in enumerate(candidates, start=1):
            if time.time() >= deadline:
                break
            # Avoid starting a long candidate when very close to deadline.
            if time.time() + 35 > deadline and idx > 1:
                _log(manifest, "[evo] near deadline, stopping candidate loop.")
                break

            candidate_counter += 1
            cid = f"g{generation:03d}_c{candidate_counter:04d}"
            train_model = models_dir / f"{cid}.zip"
            train_log = logs_dir / f"{cid}_train.log"
            eval_fast_log = logs_dir / f"{cid}_eval_fast.log"
            eval_60_log = logs_dir / f"{cid}_eval_60.log"

            _thermal_guard(args, manifest)
            t0 = time.time()

            env_fast = _candidate_env(args, genes, fast_mode=True)
            train_cmd = [
                args.python_bin,
                "-u",
                "agents/train_anna_cuda_big.py",
                "--godot-bin",
                args.godot_bin,
                "--device",
                "cpu",
                "--cpu-threads",
                str(args.cpu_threads),
                "--num-envs",
                "1",
                "--num-envs-stage1",
                "1",
                "--num-envs-stage2",
                "1",
                "--num-envs-stage3",
                "1",
                "--timesteps-stage1",
                "0",
                "--timesteps-stage2",
                str(args.train_steps),
                "--timesteps-stage3",
                "0",
                "--scene-stage1",
                "core_v2/tests/TestScene_RL_2.tscn",
                "--scene-stage2",
                args.scene,
                "--scene-stage3",
                "core_v2/tests/TestScene_RL_BaseTerrace.tscn",
                "--n-steps",
                "2048",
                "--batch-size",
                "2048",
                "--n-epochs",
                str(int(genes["n_epochs"])),
                "--net-arch",
                "192,192",
                "--learning-rate",
                str(float(genes["learning_rate"])),
                "--entropy-coef",
                str(float(genes["entropy_coef"])),
                "--checkpoint-every",
                str(max(1000, int(args.train_steps))),
                "--skip-import-prewarm",
                "--resume",
                "never",
                "--resume-from",
                os.path.relpath(str(best_model), str(repo_root)),
                "--model-out",
                os.path.relpath(str(train_model), str(repo_root)),
                "--verbose",
                str(args.verbose),
            ]
            rc_train = _run_cmd(train_cmd, env_fast, train_log, timeout=0)
            if rc_train != 0 or not train_model.exists():
                _log(manifest, f"[evo] {cid} train failed rc={rc_train}")
                continue

            eval_fast_cmd = [
                args.python_bin,
                "-u",
                "agents/eval_anna.py",
                "--model",
                os.path.relpath(str(train_model), str(repo_root)),
                "--scene",
                args.scene,
                "--headless",
                "--episodes",
                str(args.eval_episodes_fast),
                "--max-steps",
                str(args.eval_max_steps_fast),
                "--port",
                str(6100 + (candidate_counter % 200)),
            ]
            _ = _run_cmd(eval_fast_cmd, env_fast, eval_fast_log, timeout=0)
            eval_fast = _parse_eval_summary(eval_fast_log)

            env_60 = _candidate_env(args, genes, fast_mode=False)
            eval_60_cmd = [
                args.python_bin,
                "-u",
                "agents/eval_anna.py",
                "--model",
                os.path.relpath(str(train_model), str(repo_root)),
                "--scene",
                args.scene,
                "--headless",
                "--episodes",
                str(args.eval_episodes_60hz),
                "--max-steps",
                str(args.eval_max_steps_60hz),
                "--port",
                str(6400 + (candidate_counter % 200)),
            ]
            _ = _run_cmd(eval_60_cmd, env_60, eval_60_log, timeout=0)
            eval_60 = _parse_eval_summary(eval_60_log)

            fitness = _score(eval_fast, eval_60, float(args.fast_weight), float(args.hz60_weight))
            elapsed = time.time() - t0
            row = {
                "candidate_id": cid,
                "generation": generation,
                "genes": genes,
                "train_model": str(train_model),
                "eval_fast": eval_fast,
                "eval_60hz": eval_60,
                "fitness": float(fitness),
                "elapsed_sec": round(elapsed, 3),
            }
            history.append(row)
            _log(
                manifest,
                "[evo] %s fit=%.3f fast[s=%.1f r=%.1f] 60[s=%.1f r=%.1f] elapsed=%.1fs"
                % (
                    cid,
                    float(fitness),
                    float(eval_fast["success_rate"]),
                    float(eval_fast["avg_reward"]),
                    float(eval_60["success_rate"]),
                    float(eval_60["avg_reward"]),
                    elapsed,
                ),
            )

            if fitness > best_score:
                best_score = float(fitness)
                best_genes = dict(genes)
                best_model = train_model
                best_record = row
                _log(manifest, f"[evo] NEW_BEST {cid} fit={best_score:.3f} model={best_model}")

        # Persist checkpoint per generation.
        checkpoint = {
            "args": vars(args),
            "deadline_unix": int(deadline),
            "best_score": float(best_score),
            "best_genes": best_genes,
            "best_model": str(best_model),
            "best_record": best_record,
            "history_size": len(history),
        }
        (run_dir / "state.json").write_text(json.dumps(checkpoint, indent=2), encoding="utf-8")
        (run_dir / "history.json").write_text(json.dumps(history, indent=2), encoding="utf-8")

    report = {
        "args": vars(args),
        "finished_unix": int(time.time()),
        "best_score": float(best_score),
        "best_genes": best_genes,
        "best_model": str(best_model),
        "best_record": best_record,
        "evaluated_candidates": len(history),
    }
    (run_dir / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (run_dir / "best_model.txt").write_text(str(best_model) + "\n", encoding="utf-8")
    _log(manifest, f"[evo] done candidates={len(history)} best_score={best_score:.3f} best_model={best_model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
