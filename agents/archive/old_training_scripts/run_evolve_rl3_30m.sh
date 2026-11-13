#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f ".venv311/bin/activate" ]]; then
  source .venv311/bin/activate
elif [[ -f ".venv/bin/activate" ]]; then
  source .venv/bin/activate
fi

BASE_MODEL="${BASE_MODEL:-}"
MINUTES="${MINUTES:-30}"
CPU_THREADS="${CPU_THREADS:-6}"
POPULATION="${POPULATION:-4}"
TRAIN_STEPS="${TRAIN_STEPS:-12000}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RUN_DIR:-agents/runs/evo_rl3_${STAMP}}"
LOG_PATH="${RUN_DIR}.launcher.log"

mkdir -p "${RUN_DIR}"

if [[ -z "${BASE_MODEL}" ]]; then
  BASE_MODEL="$(
    ls -1t \
      agents/models_small/*_best.zip \
      agents/models/*_best.zip \
      agents/models/*.zip \
      2>/dev/null | head -n1 || true
  )"
fi

if [[ -z "${BASE_MODEL}" || ! -f "${BASE_MODEL}" ]]; then
  echo "[run_evolve_rl3_30m] BASE_MODEL no encontrado."
  echo "[run_evolve_rl3_30m] Define BASE_MODEL=/ruta/al/modelo.zip o agrega un *_best.zip en agents/models*."
  exit 2
fi

env \
  PYTHONUNBUFFERED=1 \
  GODOT_BIN="${GODOT_BIN:-godot3-server}" \
  python -u agents/evolve_rl3_params.py \
    --minutes "${MINUTES}" \
    --cpu-threads "${CPU_THREADS}" \
    --population "${POPULATION}" \
    --train-steps "${TRAIN_STEPS}" \
    --base-model "${BASE_MODEL}" \
    --scene core_v2/tests/TestScene_RL_3.tscn \
    --run-dir "${RUN_DIR}" \
    --python-bin python \
    --godot-bin "${GODOT_BIN:-godot3-server}" \
    --max-temp-c "${MAX_CPU_TEMP_C:-82}" \
    --resume-temp-c "${RESUME_CPU_TEMP_C:-76}" \
    --temp-poll-sec "${TEMP_POLL_SEC:-15}" \
    --verbose "${VERBOSE:-1}" \
    | tee "${LOG_PATH}"

echo "EVO_RUN_DIR=${RUN_DIR}"
echo "EVO_LOG=${LOG_PATH}"
