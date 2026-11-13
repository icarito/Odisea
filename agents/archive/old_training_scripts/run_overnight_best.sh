#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="${RUN_DIR:-agents/runs/overnight/${STAMP}}"
LOG_DIR="${RUN_DIR}/logs"
mkdir -p "${LOG_DIR}"
mkdir -p agents/runs/overnight
ln -sfn "${STAMP}" agents/runs/overnight/latest

echo "[run_overnight_best] run_dir=${RUN_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  echo "[run_overnight_best] Using active virtualenv: ${VIRTUAL_ENV}"
elif [[ -f ".venv/bin/activate" ]]; then
  source .venv/bin/activate
  PYTHON_BIN="python"
  echo "[run_overnight_best] Activated .venv"
elif [[ -f ".venv311/bin/activate" ]]; then
  source .venv311/bin/activate
  PYTHON_BIN="python"
  echo "[run_overnight_best] Activated .venv311"
fi

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "[run_overnight_best] Could not find Python." >&2
    exit 1
  fi
fi

export GODOT_BIN="${GODOT_BIN:-godot3-server}"
export ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}"
export ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}"
export ANNA_GODOT_DISABLE_RENDER_LOOP="${ANNA_GODOT_DISABLE_RENDER_LOOP:-1}"
export ANNA_GODOT_SERVER_VIDEO_DRIVER="${ANNA_GODOT_SERVER_VIDEO_DRIVER:-}"
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG="${ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG:-1}"
export ANNA_GODOT_QUIET="${ANNA_GODOT_QUIET:-1}"
export ANNA_RL_DISABLE_CPU_SLEEP="${ANNA_RL_DISABLE_CPU_SLEEP:-1}"
export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-0}"
export ANNA_RL_POLL_SLEEP_USEC="${ANNA_RL_POLL_SLEEP_USEC:-0}"
export ANNA_RL_DISABLE_QODOT="${ANNA_RL_DISABLE_QODOT:-1}"

if [[ "${ANNA_GODOT_MAX_FPS:-}" == "0" ]]; then
  echo "[run_overnight_best] WARNING: ANNA_GODOT_MAX_FPS=0 hurts SPS. Unsetting."
  unset ANNA_GODOT_MAX_FPS
fi

# Conservative and stable single-process defaults (override as needed).
export CPU_THREADS="${CPU_THREADS:-8}"
export NUM_ENVS="${NUM_ENVS:-1}"
export NUM_ENVS_STAGE3="${NUM_ENVS_STAGE3:-1}"
export N_STEPS="${N_STEPS:-2048}"
export BATCH_SIZE="${BATCH_SIZE:-2048}"
export CHECKPOINT_EVERY="${CHECKPOINT_EVERY:-25000}"
export VERBOSE="${VERBOSE:-1}"
export MODEL_OUT="${MODEL_OUT:-agents/models/anna_ppo_overnight_${STAMP}.zip}"

{
  echo "created_at=${STAMP}"
  echo "run_dir=${RUN_DIR}"
  echo "python_bin=${PYTHON_BIN}"
  echo "godot_bin=${GODOT_BIN}"
  echo "model_out=${MODEL_OUT}"
  echo "cpu_threads=${CPU_THREADS}"
  echo "num_envs=${NUM_ENVS}"
  echo "num_envs_stage3=${NUM_ENVS_STAGE3}"
} > "${RUN_DIR}/run_manifest.env"

git rev-parse HEAD > "${RUN_DIR}/git_head.txt" || true
git status --short > "${RUN_DIR}/git_status.txt" || true

if [[ "${SKIP_FPS_PROBE:-0}" != "1" ]]; then
  FPS_SCENE="${FPS_SCENE:-core_v2/tests/TestScene_RL.tscn}"
  FPS_STEPS="${FPS_STEPS:-2000}"
  FPS_MIN="${FPS_MIN:-1500}"
  FPS_PORT="${FPS_PORT:-5799}"
  echo "[run_overnight_best] Running FPS probe..."
  PYTHONPATH=. "${PYTHON_BIN}" agents/probe_rl_fps.py \
    --scene "${FPS_SCENE}" \
    --steps "${FPS_STEPS}" \
    --port "${FPS_PORT}" \
    --min-sps "${FPS_MIN}" \
    --json-out "${RUN_DIR}/fps_probe.json" \
    | tee "${LOG_DIR}/fps_probe.log"
fi

echo "[run_overnight_best] Starting training..."
echo "[run_overnight_best] Command: ./agents/run_train_best_cuda.sh" | tee "${LOG_DIR}/train_cmd.log"
./agents/run_train_best_cuda.sh "$@" 2>&1 | tee "${LOG_DIR}/train.log"

if [[ -f "agents/models/.anna_cuda_big_last_model_out" ]]; then
  head -n 1 agents/models/.anna_cuda_big_last_model_out > "${RUN_DIR}/last_model.txt" || true
fi

if [[ -n "${MODEL_OUT:-}" && -f "${MODEL_OUT}" ]]; then
  echo "${MODEL_OUT}" > "${RUN_DIR}/model_out.txt"
fi

echo "[run_overnight_best] done"
echo "[run_overnight_best] logs: ${LOG_DIR}"
