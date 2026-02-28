#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RUN_DIR:-agents/runs/overnight_programmer/${STAMP}}"
MODEL_DIR="${MODEL_DIR:-agents/models/programmer_overnight/${STAMP}}"
LOG_DIR="${RUN_DIR}/logs"
mkdir -p "${RUN_DIR}" "${MODEL_DIR}" "${LOG_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
if [[ -f ".venv311/bin/activate" ]]; then
  source .venv311/bin/activate
  PYTHON_BIN="python"
elif [[ -f ".venv/bin/activate" ]]; then
  source .venv/bin/activate
  PYTHON_BIN="python"
fi

export GODOT_BIN="${GODOT_BIN:-godot3-server}"
export ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}"
export ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}"
export ANNA_GODOT_DISABLE_RENDER_LOOP="${ANNA_GODOT_DISABLE_RENDER_LOOP:-1}"
export ANNA_GODOT_SERVER_VIDEO_DRIVER="${ANNA_GODOT_SERVER_VIDEO_DRIVER:-}"
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG="${ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG:-1}"
export ANNA_GODOT_QUIET="${ANNA_GODOT_QUIET:-1}"
export ANNA_RL_DISABLE_QODOT="${ANNA_RL_DISABLE_QODOT:-1}"

CPU_THREADS="${CPU_THREADS:-6}"
NUM_ENVS="${NUM_ENVS:-1}"
HOURS="${HOURS:-8}"
MAX_MODEL_MB="${MAX_MODEL_MB:-3.0}"
MAX_CPU_TEMP_C="${MAX_CPU_TEMP_C:-80}"
RESUME_CPU_TEMP_C="${RESUME_CPU_TEMP_C:-75}"
TEMP_POLL_SEC="${TEMP_POLL_SEC:-15}"

{
  echo "created_at=${STAMP}"
  echo "run_dir=${RUN_DIR}"
  echo "model_dir=${MODEL_DIR}"
  echo "python_bin=${PYTHON_BIN}"
  echo "godot_bin=${GODOT_BIN}"
  echo "hours=${HOURS}"
  echo "cpu_threads=${CPU_THREADS}"
  echo "num_envs=${NUM_ENVS}"
  echo "max_model_mb=${MAX_MODEL_MB}"
} > "${RUN_DIR}/run_manifest.env"

git rev-parse HEAD > "${RUN_DIR}/git_head.txt" || true
git status --short > "${RUN_DIR}/git_status.txt" || true

"${PYTHON_BIN}" -u agents/anna_overnight_programmer.py \
  --hours "${HOURS}" \
  --cpu-threads "${CPU_THREADS}" \
  --num-envs "${NUM_ENVS}" \
  --max-model-mb "${MAX_MODEL_MB}" \
  --max-temp-c "${MAX_CPU_TEMP_C}" \
  --resume-temp-c "${RESUME_CPU_TEMP_C}" \
  --temp-poll-sec "${TEMP_POLL_SEC}" \
  --run-dir "${RUN_DIR}" \
  --models-dir "${MODEL_DIR}" \
  --python-bin "${PYTHON_BIN}" \
  "$@" \
  2>&1 | tee "${LOG_DIR}/overnight_programmer.log"

echo "RUN_DIR=${RUN_DIR}"
echo "MODEL_DIR=${MODEL_DIR}"
if [[ -f "${RUN_DIR}/best_model.txt" ]]; then
  echo "BEST_MODEL=$(cat "${RUN_DIR}/best_model.txt")"
fi
