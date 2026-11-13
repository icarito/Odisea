#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p reports agents/runs/ga
log="reports/evolve_ga_$(date +%Y%m%d_%H%M%S).log"

PY="${PYTHON_BIN:-python3}"

env \
  PYTHONUNBUFFERED=1 \
  GODOT_BIN="${GODOT_BIN:-godot3-server}" \
  ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}" \
  ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}" \
  ANNA_RL_MAX_STEPS="${ANNA_RL_MAX_STEPS:-1500}" \
  vblank_mode=0 \
  "${PY}" agents/evolve_anna_ga.py \
    --population "${GA_POPULATION:-8}" \
    --generations "${GA_GENERATIONS:-5}" \
    --elite "${GA_ELITE:-2}" \
    --mutation-rate "${GA_MUTATION_RATE:-0.35}" \
    --mutation-rate-max "${GA_MUTATION_RATE_MAX:-0.70}" \
    --mutation-boost "${GA_MUTATION_BOOST:-0.12}" \
    --cpu-threads "${GA_CPU_THREADS:-8}" \
    --parallel-jobs "${GA_PARALLEL_JOBS:-1}" \
    --eval-episodes "${GA_EVAL_EPISODES:-20}" \
    --eval-max-steps "${GA_EVAL_MAX_STEPS:-1500}" \
    --rl-max-steps "${ANNA_RL_MAX_STEPS:-1500}" \
    --scene-stage1 core_v2/tests/TestScene_RL.tscn \
    --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
    --scene-stage3 core_v2/tests/TestScene_RL_3_Door.tscn \
    --rounds "${GA_ROUNDS:-3}" \
    --min-rounds "${GA_MIN_ROUNDS:-3}" \
    --output-prefix "agents/models/anna_ga" \
    --work-dir "agents/runs/ga" \
    --python-bin "${PY}" \
    --verbose "${GA_VERBOSE:-1}" \
    | tee "${log}"

echo "GA_LOG=${log}"
