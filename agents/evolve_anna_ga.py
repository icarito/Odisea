#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Tuple


@dataclass
class Individual:
    genes: Dict[str, Any]
    fitness: float = -1e9
    metrics: Dict[str, float] | None = None
    output_prefix: str = ""
    summary_path: str = ""
    rc: int = 0
    elapsed_sec: float = 0.0
    model_mb: float = 0.0

def _log(msg: str, work_dir: Path | None = None):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    if work_dir:
        try:
            with (work_dir / "evolution.log").open("a", encoding="utf-8") as f:
                f.write(line + "\n")
        except:
            pass


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Genetic search for ANNA PPO/curriculum configs.")
    p.add_argument("--population", type=int, default=8)
    p.add_argument("--generations", type=int, default=5)
    p.add_argument("--elite", type=int, default=2)
    p.add_argument("--mutation-rate", type=float, default=0.35)
    p.add_argument("--mutation-rate-max", type=float, default=0.65)
    p.add_argument("--mutation-boost", type=float, default=0.10)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--cpu-threads", type=int, default=8)
    p.add_argument("--num-envs", type=int, default=1)
    p.add_argument("--parallel-jobs", type=int, default=1)
    p.add_argument("--eval-episodes", type=int, default=20)
    p.add_argument("--eval-max-steps", type=int, default=1500)
    p.add_argument("--rl-max-steps", type=int, default=1500)
    p.add_argument("--live-report-steps", type=int, default=4000, help="Live telemetry chunk size passed to auto_train_anna.")
    p.add_argument("--live-eval-episodes", type=int, default=1, help="Quick eval episodes per live telemetry chunk.")
    p.add_argument("--live-eval-max-steps", type=int, default=300, help="Quick eval max steps per live telemetry chunk.")
    p.add_argument("--train-physics-fps", type=int, default=0, help="Training physics FPS passed to auto_train_anna (<=0 = uncapped mode).")
    p.add_argument("--eval-physics-fps", type=int, default=60, help="Evaluation physics FPS passed to auto_train_anna.")
    p.add_argument("--scene-stage1", default="core_v2/tests/TestScene_RL.tscn")
    p.add_argument("--scene-stage2", default="core_v2/tests/TestScene_RL_2.tscn")
    p.add_argument("--scene-stage3", default="core_v2/tests/TestScene_RL_3_Door.tscn")
    p.add_argument("--scene-stage4", default="core_v2/tests/TestScene_RL_3_Door.tscn")
    p.add_argument("--scene-stage5", default="core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn")
    p.add_argument("--timesteps-stage4", type=int, default=28000)
    p.add_argument("--timesteps-stage5", type=int, default=34000)
    p.add_argument("--rounds", type=int, default=3)
    p.add_argument("--min-rounds", type=int, default=3)
    p.add_argument("--arch-limit", type=int, default=3)
    p.add_argument("--max-model-mb", type=float, default=1.00)
    p.add_argument("--target-model-mb", type=float, default=0.60)
    p.add_argument("--model-size-weight", type=float, default=80.0)
    p.add_argument("--success-target", type=float, default=0.45)
    p.add_argument("--direction-target", type=float, default=0.68)
    p.add_argument("--fast-success-target", type=float, default=0.45)
    p.add_argument("--stage-unlock-target", type=float, default=0.55)
    p.add_argument("--stage-growth", type=float, default=0.18)
    p.add_argument("--max-stage-scale", type=float, default=1.8)
    p.add_argument("--init-model", default="", help="Optional PPO .zip used to warm-start each candidate.")
    p.add_argument("--port-base", type=int, default=5000)
    p.add_argument("--output-prefix", default="agents/models/anna_ga")
    p.add_argument("--work-dir", default="agents/runs/ga")
    p.add_argument("--python-bin", default=".venv/bin/python", help="Path to python executable.")
    p.add_argument("--timeout-sec", type=int, default=0, help="0 disables timeout per individual.")
    p.add_argument("--retry-failed", type=int, default=1, help="Retries per individual when training exits non-zero.")
    p.add_argument("--keep-failed", action="store_true")
    p.add_argument("--top-k-log", type=int, default=5)
    p.add_argument("--verbose", type=int, default=1)
    return p.parse_args()


def _gene_space() -> Dict[str, List[Any]]:
    return {
        "learning_rate": [2.5e-4, 3e-4, 4e-4, 5e-4],
        "entropy_coef": [0.02, 0.025, 0.03],
        "ppo_n_steps": [2048],
        "ppo_batch_size": [1024, 2048],
        "ppo_n_epochs": [1],
        "timesteps_stage1": [8000, 10000, 12000],
        "timesteps_stage2": [12000, 14000, 16000],
        "timesteps_stage3": [18000, 22000, 24000],
        "policy_widths": ["112,128,144", "128,144"],
        "policy_depths": ["2"],
        "wall_contact_max": [0.18, 0.22, 0.26],
    }


def _random_individual(space: Dict[str, List[Any]], rng: random.Random) -> Dict[str, Any]:
    return {k: rng.choice(v) for k, v in space.items()}


def _stable_gene_id(genes: Dict[str, Any]) -> str:
    payload = json.dumps(genes, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha1(payload).hexdigest()[:12]


def _fitness(
    metrics: Dict[str, float],
    model_mb: float,
    target_model_mb: float,
    model_size_weight: float,
) -> float:
    success = float(metrics.get("success_rate", 0.0))
    fast_success = float(metrics.get("fast_success_score", 0.0))
    direction = float(metrics.get("direction_score", 0.0))
    wall_clear = float(metrics.get("wall_clear_ratio", 0.0))
    speed = float(metrics.get("speed_score", 0.0))
    collapse = float(metrics.get("collapse_forward", 1.0))
    avg_success_len = float(metrics.get("avg_success_len", 1e9))
    avg_target_dist = float(metrics.get("avg_target_dist", 50.0))
    min_target_dist = float(metrics.get("min_target_dist", avg_target_dist))

    # Strongly prioritize real success in Stage 3.
    len_bonus = max(0.0, 1.0 - min(1.0, avg_success_len / 1500.0))
    prox = max(0.0, 1.0 - min(1.0, avg_target_dist / 25.0))
    min_prox = max(0.0, 1.0 - min(1.0, min_target_dist / 12.0))
    base = (
        success * 1000.0
        + fast_success * 120.0
        + len_bonus * 80.0
        + prox * 120.0
        + min_prox * 100.0
        + direction * 60.0
        + wall_clear * 25.0
        + speed * 15.0
        - collapse * 100.0
    )
    if model_mb <= 0.0 or target_model_mb <= 0.0 or model_size_weight <= 0.0:
        return base
    diff = abs(float(model_mb) - float(target_model_mb))
    # Soft preference for ~target size without overriding task success.
    size_term = -float(model_size_weight) * diff
    if diff <= 0.08:
        size_term += 12.0
    return base + size_term


def _select_progress_metrics(summary: Dict[str, Any]) -> Dict[str, float]:
    history = summary.get("history", []) or []
    if not isinstance(history, list) or not history:
        return dict(summary.get("best_metrics", {}) or {})

    def _key(item: Dict[str, Any]) -> Tuple[int, int, float, float, float]:
        stage = int(item.get("unlocked_stage_count", 0) or 0)
        stage_gate = item.get("stage_gate", {}) or {}
        passed = 1 if bool(stage_gate.get("passed", False)) else 0
        success = float(item.get("success_rate", 0.0) or 0.0)
        fast = float(item.get("fast_success_score", 0.0) or 0.0)
        score = float(item.get("score", 0.0) or 0.0)
        return (stage, passed, success, fast, score)

    chosen = max(history, key=_key)
    metrics = dict(chosen)
    metrics["stage_progress"] = float(chosen.get("unlocked_stage_count", 0) or 0)
    return metrics


def _fmt_metric(metrics: Dict[str, float], key: str, fmt: str = ".3f", default: float = 0.0) -> str:
    try:
        val = float(metrics.get(key, default))
    except Exception:
        val = float(default)
    return format(val, fmt)


def _generation_stats(evaluated: List[Individual]) -> Dict[str, float]:
    if not evaluated:
        return {}

    def _avg(key: str, default: float = 0.0) -> float:
        vals = [float((e.metrics or {}).get(key, default)) for e in evaluated]
        return sum(vals) / max(1, len(vals))

    fits = sorted([float(e.fitness) for e in evaluated], reverse=True)
    mid = len(fits) // 2
    median_fit = fits[mid] if len(fits) % 2 == 1 else (fits[mid - 1] + fits[mid]) * 0.5
    return {
        "fit_mean": sum(fits) / max(1, len(fits)),
        "fit_median": median_fit,
        "success_mean": _avg("success_rate"),
        "fast_success_mean": _avg("fast_success_score"),
        "direction_mean": _avg("direction_score"),
        "speed_mean": _avg("speed_score"),
        "wall_touch_mean": _avg("wall_touch_ratio"),
        "avg_target_dist_mean": _avg("avg_target_dist", 50.0),
        "min_target_dist_mean": _avg("min_target_dist", 50.0),
    }


def _build_cmd(
    args: argparse.Namespace,
    genes: Dict[str, Any],
    output_prefix: str,
    ports: Dict[str, int],
) -> List[str]:
    return [
        args.python_bin,
        "agents/auto_train_anna.py",
        "--scene-stage1",
        args.scene_stage1,
        "--scene-stage2",
        args.scene_stage2,
        "--scene-stage3",
        args.scene_stage3,
        "--scene-stage4",
        args.scene_stage4,
        "--scene-stage5",
        args.scene_stage5,
        "--train-port-stage1",
        str(int(ports["train_stage1"])),
        "--train-port-stage2",
        str(int(ports["train_stage2"])),
        "--train-port-stage3",
        str(int(ports["train_stage3"])),
        "--train-port-stage4",
        str(int(ports["train_stage4"])),
        "--train-port-stage5",
        str(int(ports["train_stage5"])),
        "--eval-port",
        str(int(ports["eval"])),
        "--timesteps-stage1",
        str(genes["timesteps_stage1"]),
        "--timesteps-stage2",
        str(genes["timesteps_stage2"]),
        "--timesteps-stage3",
        str(genes["timesteps_stage3"]),
        "--timesteps-stage4",
        str(max(1, int(args.timesteps_stage4))),
        "--timesteps-stage5",
        str(max(1, int(args.timesteps_stage5))),
        "--rounds",
        str(args.rounds),
        "--min-rounds",
        str(args.min_rounds),
        "--eval-episodes",
        str(args.eval_episodes),
        "--eval-max-steps",
        str(args.eval_max_steps),
        "--cpu-threads",
        str(args.cpu_threads),
        "--num-envs",
        str(max(1, int(args.num_envs))),
        "--ppo-n-steps",
        str(genes["ppo_n_steps"]),
        "--ppo-batch-size",
        str(genes["ppo_batch_size"]),
        "--ppo-n-epochs",
        str(genes["ppo_n_epochs"]),
        "--ppo-device",
        "cpu",
        "--learning-rate",
        str(genes["learning_rate"]),
        "--entropy-coef",
        str(genes["entropy_coef"]),
        "--policy-widths",
        str(genes["policy_widths"]),
        "--policy-depths",
        str(genes["policy_depths"]),
        "--arch-limit",
        str(max(1, int(args.arch_limit))),
        "--max-model-mb",
        str(float(args.max_model_mb)),
        "--rl-physics-fps",
        str(args.train_physics_fps),
        "--eval-physics-fps",
        str(args.eval_physics_fps),
        "--rl-max-steps",
        str(args.rl_max_steps),
        "--live-report-steps",
        str(args.live_report_steps),
        "--live-eval-episodes",
        str(args.live_eval_episodes),
        "--live-eval-max-steps",
        str(args.live_eval_max_steps),
        "--rl-disable-cpu-sleep",
        "--success-target",
        str(float(args.success_target)),
        "--direction-target",
        str(float(args.direction_target)),
        "--fast-success-target",
        str(float(args.fast_success_target)),
        "--stage-unlock-target",
        str(float(args.stage_unlock_target)),
        "--stage-growth",
        str(float(args.stage_growth)),
        "--max-stage-scale",
        str(float(args.max_stage_scale)),
        "--init-model",
        str(args.init_model),
        "--wall-contact-max",
        str(genes["wall_contact_max"]),
        "--output-prefix",
        output_prefix,
        "--verbose",
        str(args.verbose),
    ]


def _ports_for_gid(port_base: int, gid: str) -> Dict[str, int]:
    seed = int(gid[:8], 16)
    base = int(port_base) + (seed % 700) * 10
    return {
        "train_stage1": base,
        "train_stage2": base + 1,
        "train_stage3": base + 2,
        "train_stage4": base + 3,
        "train_stage5": base + 4,
        "eval": base + 100,
    }


def _evaluate_individual(
    args: argparse.Namespace,
    genes: Dict[str, Any],
    run_dir: Path,
    cache: Dict[str, Individual],
) -> Individual:
    gid = _stable_gene_id(genes)
    if gid in cache:
        return cache[gid]

    out_prefix = f"{args.output_prefix}_{gid}"
    summary_path = Path(f"{out_prefix}_summary.json")
    log_path = run_dir / f"{gid}.log"
    ports = _ports_for_gid(int(args.port_base), gid)
    cmd = _build_cmd(args, genes, out_prefix, ports)
    env = os.environ.copy()
    env.setdefault("PYTHONUNBUFFERED", "1")
    env.setdefault("GODOT_BIN", "godot3-server")
    env.setdefault("ANNA_GODOT_PREFER_SERVER", "1")
    env.setdefault("ANNA_GODOT_SERVER_FALLBACK", "0")
    env.setdefault("ANNA_GODOT_DISABLE_RENDER_LOOP", "1")
    env.setdefault("ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG", "1")
    env.setdefault("ANNA_GODOT_SERVER_VIDEO_DRIVER", "")
    env.setdefault("ANNA_RL_BINARY_PROTOCOL", "1")
    env.setdefault("ANNA_RL_MAX_STEPS", str(args.rl_max_steps))
    env.setdefault("ANNA_RL_PHYSICS_FPS", str(args.train_physics_fps))
    env.setdefault("ANNA_RL_TARGET_FPS", "0" if int(args.train_physics_fps) <= 0 else str(args.train_physics_fps))
    env.setdefault("ANNA_RL_PHYSICS_FPS_CAP", "6000")
    env.setdefault("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME", "128")
    env.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "1")
    env.setdefault("ANNA_RL_POLL_SLEEP_USEC", "0")
    env.setdefault("vblank_mode", "0")
    if "GODOT_THREADS" in os.environ:
        env["GODOT_THREADS"] = os.environ["GODOT_THREADS"]

    started = time.time()
    rc = 0
    retry_failed = max(0, int(args.retry_failed))
    attempts = 1 + retry_failed
    try:
        summary_path.unlink(missing_ok=True)
    except Exception:
        pass
    with log_path.open("w", encoding="utf-8") as lf:
        lf.write("# CMD: %s\n\n" % " ".join(cmd))
        lf.flush()
        for attempt in range(1, attempts + 1):
            if attempt > 1:
                lf.write("\n[RETRY] attempt %d/%d after rc=%d\n" % (attempt, attempts, rc))
                lf.flush()
                time.sleep(1.0)
            env["ANNA_GA_ATTEMPT"] = str(attempt)
            try:
                if args.parallel_jobs == 1 and args.verbose > 0:
                    print(f"\n" + "="*60, flush=True)
                    print(f"🧬 [GA] Evaluating Candidate : {gid} (attempt {attempt}/{attempts})", flush=True)
                    print(f"🧬 Genes: {json.dumps(genes)}", flush=True)
                    print("="*60 + "\n", flush=True)
                    proc = subprocess.Popen(
                        cmd,
                        cwd=str(Path(__file__).resolve().parents[1]),
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True,
                        bufsize=1,
                    )
                    for line in proc.stdout:
                        lf.write(line)
                        # Suppress Bullet noise from the console so the user can easily read SB3 tables
                        skip = False
                        for noise in [
                            "RigidBody in 3D only supports primitive shapes",
                            "VisualServer attempted to free a NULL RID",
                            "Octahedral compression cannot be used",
                            "at: copyAllOwnerShapes",
                            "at: free (servers/visual/",
                            "at: norm_to_oct (servers/",
                            "ERROR: Expected Image data size",
                            "at: create (core/image.cpp:",
                        ]:
                            if noise in line:
                                skip = True
                                break
                        if not skip:
                            sys.stdout.write(line)
                            sys.stdout.flush()

                    proc.wait(timeout=(None if args.timeout_sec <= 0 else args.timeout_sec))
                    rc = int(proc.returncode)
                else:
                    proc = subprocess.run(
                        cmd,
                        cwd=str(Path(__file__).resolve().parents[1]),
                        env=env,
                        stdout=lf,
                        stderr=subprocess.STDOUT,
                        timeout=(None if args.timeout_sec <= 0 else args.timeout_sec),
                        check=False,
                    )
                    rc = int(proc.returncode)
            except subprocess.TimeoutExpired:
                rc = 124
                lf.write("\n[TIMEOUT] %ds\n" % int(args.timeout_sec))
            if rc == 0 and summary_path.exists():
                break

    metrics: Dict[str, float] = {}
    fit = -1e9
    best_model_path = Path(f"{out_prefix}_best.zip")
    latest_model_path = Path(f"{out_prefix}_latest.zip")
    if best_model_path.exists():
        model_mb = best_model_path.stat().st_size / (1024.0 * 1024.0)
    elif latest_model_path.exists():
        model_mb = latest_model_path.stat().st_size / (1024.0 * 1024.0)
    else:
        model_mb = 0.0
    if rc == 0 and summary_path.exists():
        data = json.loads(summary_path.read_text(encoding="utf-8"))
        metrics = _select_progress_metrics(data)
        stage_progress = float(metrics.get("stage_progress", 0.0))
        success_rate = float(metrics.get("success_rate", 0.0))
        fit = _fitness(
            metrics=metrics,
            model_mb=float(model_mb),
            target_model_mb=float(args.target_model_mb),
            model_size_weight=float(args.model_size_weight),
        )
        # Do not over-reward higher stage snapshots that have poor actual success.
        effective_stage = stage_progress if success_rate >= 0.5 else max(1.0, stage_progress - 1.5)
        fit += effective_stage * 140.0
        if stage_progress >= 4.0 and success_rate < 0.4:
            fit -= 220.0
        if not best_model_path.exists():
            # Prefer candidates that actually produce a promoted best artifact.
            fit -= 120.0
    elif not args.keep_failed:
        for p in [summary_path, Path(f"{out_prefix}_best.zip")]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass

    ind = Individual(
        genes=dict(genes),
        fitness=float(fit),
        metrics=metrics,
        output_prefix=out_prefix,
        summary_path=str(summary_path),
    )
    cache[gid] = ind
    elapsed = time.time() - started
    print(
        "[ga] eval gid=%s rc=%d fit=%.3f stage=%s success=%s fast=%s dir=%s speed=%s wall=%s d_avg=%s d_min=%s model=%.3fMB elapsed=%.1fs out=%s"
        % (
            gid,
            rc,
            ind.fitness,
            _fmt_metric(metrics, "stage_progress", ".0f", 0.0),
            _fmt_metric(metrics, "success_rate"),
            _fmt_metric(metrics, "fast_success_score"),
            _fmt_metric(metrics, "direction_score"),
            _fmt_metric(metrics, "speed_score"),
            _fmt_metric(metrics, "wall_touch_ratio"),
            _fmt_metric(metrics, "avg_target_dist", ".2f", 50.0),
            _fmt_metric(metrics, "min_target_dist", ".2f", 50.0),
            model_mb,
            elapsed,
            out_prefix,
        )
    )
    return ind


def _crossover(a: Dict[str, Any], b: Dict[str, Any], rng: random.Random) -> Dict[str, Any]:
    child: Dict[str, Any] = {}
    for k in a.keys():
        child[k] = a[k] if rng.random() < 0.5 else b[k]
    return child


def _mutate(
    genes: Dict[str, Any],
    space: Dict[str, List[Any]],
    mutation_rate: float,
    rng: random.Random,
) -> Dict[str, Any]:
    g = dict(genes)
    for k, choices in space.items():
        if rng.random() < mutation_rate:
            g[k] = rng.choice(choices)
    return g


def main() -> int:
    args = _parse_args()
    rng = random.Random(args.seed)
    space = _gene_space()
    run_dir = Path(args.work_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    cache: Dict[str, Individual] = {}
    history: List[Dict[str, Any]] = []

    pop_size = max(2, int(args.population))
    elite_n = max(1, min(int(args.elite), pop_size))
    parallel_jobs = max(1, int(args.parallel_jobs))
    if parallel_jobs > 1 and int(args.cpu_threads) > 1:
        args.cpu_threads = max(1, int(math.floor(float(args.cpu_threads) / float(parallel_jobs))))
    mutation_rate = float(args.mutation_rate)
    population = [_random_individual(space, rng) for _ in range(pop_size)]
    best: Individual | None = None

    for gen in range(1, max(1, int(args.generations)) + 1):
        print("[ga] generation=%d pop=%d" % (gen, pop_size))
        evaluated: List[Individual] = []
        if parallel_jobs <= 1:
            for genes in population:
                ind = _evaluate_individual(args, genes, run_dir, cache)
                evaluated.append(ind)
                if best is None or ind.fitness > best.fitness:
                    best = ind
        else:
            with ThreadPoolExecutor(max_workers=parallel_jobs) as ex:
                futures = [ex.submit(_evaluate_individual, args, genes, run_dir, cache) for genes in population]
                for fut in as_completed(futures):
                    ind = fut.result()
                    evaluated.append(ind)
                    if best is None or ind.fitness > best.fitness:
                        best = ind

        evaluated.sort(key=lambda i: i.fitness, reverse=True)
        elites = evaluated[:elite_n]
        best_gen_success = float((elites[0].metrics or {}).get("success_rate", 0.0))
        gen_record = {
            "generation": gen,
            "best_fitness": elites[0].fitness,
            "best_success_rate": best_gen_success,
            "best_output_prefix": elites[0].output_prefix,
            "elites": [
                {
                    "fitness": e.fitness,
                    "output_prefix": e.output_prefix,
                    "genes": e.genes,
                    "metrics": e.metrics or {},
                }
                for e in elites
            ],
        }
        history.append(gen_record)
        print(
            "[ga] generation=%d best_fit=%.3f best_success=%.3f best=%s"
            % (
                gen,
                elites[0].fitness,
                best_gen_success,
                elites[0].output_prefix,
            )
        )
        gstats = _generation_stats(evaluated)
        if gstats:
            print(
                "[ga] generation=%d stats fit_mean=%.3f fit_median=%.3f success_mean=%.3f fast_mean=%.3f dir_mean=%.3f speed_mean=%.3f wall_mean=%.3f d_avg_mean=%.2f d_min_mean=%.2f"
                % (
                    gen,
                    float(gstats.get("fit_mean", 0.0)),
                    float(gstats.get("fit_median", 0.0)),
                    float(gstats.get("success_mean", 0.0)),
                    float(gstats.get("fast_success_mean", 0.0)),
                    float(gstats.get("direction_mean", 0.0)),
                    float(gstats.get("speed_mean", 0.0)),
                    float(gstats.get("wall_touch_mean", 0.0)),
                    float(gstats.get("avg_target_dist_mean", 0.0)),
                    float(gstats.get("min_target_dist_mean", 0.0)),
                )
            )

        if best_gen_success <= 0.0:
            mutation_rate = min(float(args.mutation_rate_max), mutation_rate + float(args.mutation_boost))
        else:
            mutation_rate = max(float(args.mutation_rate), mutation_rate - float(args.mutation_boost) * 0.5)
        print("[ga] generation=%d mutation_rate=%.3f parallel_jobs=%d child_cpu_threads=%d" % (gen, mutation_rate, parallel_jobs, int(args.cpu_threads)))

        # Early stop if task solved.
        if float((elites[0].metrics or {}).get("success_rate", 0.0)) >= 0.7:
            print("[ga] early-stop: success_rate >= 0.70")
            break

        # Build next generation from elites.
        next_population: List[Dict[str, Any]] = [dict(e.genes) for e in elites]
        while len(next_population) < pop_size:
            pa = rng.choice(elites).genes
            pb = rng.choice(elites).genes
            child = _crossover(pa, pb, rng)
            child = _mutate(child, space, mutation_rate, rng)
            next_population.append(child)
        population = next_population

    out_report = run_dir / ("ga_report_%d.json" % int(time.time()))
    report = {
        "args": vars(args),
        "best": {
            "fitness": (best.fitness if best else -1e9),
            "output_prefix": (best.output_prefix if best else ""),
            "summary_path": (best.summary_path if best else ""),
            "genes": (best.genes if best else {}),
            "metrics": (best.metrics if best else {}),
        },
        "history": history,
    }
    out_report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("[ga] report=%s" % out_report)
    if best:
        print("[ga] BEST_MODEL=%s_best.zip" % best.output_prefix)
        print("[ga] BEST_SUMMARY=%s" % best.summary_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
