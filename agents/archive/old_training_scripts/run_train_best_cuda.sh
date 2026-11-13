#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
PREIMPORT_OK=0
EXTRA_TRAIN_ARGS=()
IMPORT_HELPER="${REPO_ROOT}/scripts/godot_import_smoke.sh"

if [[ -n "${VIRTUAL_ENV:-}" ]]; then
  echo "[run_train_best_cuda] Using active virtualenv: ${VIRTUAL_ENV}"
elif [[ -f ".venv/bin/activate" ]]; then
  # Local dev convenience: auto-activate project venv when present.
  # On remote servers (e.g. Vast.ai), script works without .venv.
  source .venv/bin/activate
  PYTHON_BIN="python"
  echo "[run_train_best_cuda] Activated ${REPO_ROOT}/.venv"
else
  echo "[run_train_best_cuda] .venv not found; using system Python (${PYTHON_BIN})."
fi

if ! command -v "${PYTHON_BIN}" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
  else
    echo "[run_train_best_cuda] Could not find a Python interpreter." >&2
    exit 1
  fi
fi

is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "${v}" == "1" || "${v}" == "true" || "${v}" == "yes" || "${v}" == "on" ]]
}

resolve_import_godot_bin() {
  local candidate="${ANNA_IMPORT_GODOT_BIN:-}"
  if [[ -z "${candidate}" ]]; then
    candidate="${GODOT_BIN:-godot3-bin}"
  fi
  # Preimport needs editor mode; do not use server binaries here.
  if [[ "${candidate}" != *server* ]] && command -v "${candidate}" >/dev/null 2>&1; then
    echo "${candidate}"
    return 0
  fi
  if command -v godot3-bin >/dev/null 2>&1; then
    echo "godot3-bin"
    return 0
  fi
  if command -v godot3 >/dev/null 2>&1; then
    echo "godot3"
    return 0
  fi
  if command -v godot >/dev/null 2>&1; then
    echo "godot"
    return 0
  fi
  return 1
}

resolve_train_godot_bin() {
  local candidate="${GODOT_BIN:-godot3-server}"
  if command -v "${candidate}" >/dev/null 2>&1; then
    echo "${candidate}"
    return 0
  fi
  if command -v godot3-server >/dev/null 2>&1; then
    echo "godot3-server"
    return 0
  fi
  if command -v godot-server >/dev/null 2>&1; then
    echo "godot-server"
    return 0
  fi
  if command -v godot3-bin >/dev/null 2>&1; then
    echo "godot3-bin"
    return 0
  fi
  if command -v godot3 >/dev/null 2>&1; then
    echo "godot3"
    return 0
  fi
  if command -v godot >/dev/null 2>&1; then
    echo "godot"
    return 0
  fi
  return 1
}

run_preimport_step() {
  local enabled="${ANNA_PREIMPORT_BEFORE_TRAIN:-1}"
  if ! is_truthy "${enabled}"; then
    echo "[run_train_best_cuda] Preimport step disabled (ANNA_PREIMPORT_BEFORE_TRAIN=${enabled})."
    return 0
  fi

  local required="${ANNA_PREIMPORT_REQUIRED:-1}"
  local clean_cache="${ANNA_IMPORT_CLEAN_CACHE:-0}"

  local godot_bin
  if ! godot_bin="$(resolve_import_godot_bin)"; then
    echo "[run_train_best_cuda] Could not resolve Godot binary for preimport."
    if is_truthy "${required}"; then
      return 1
    fi
    return 0
  fi

  if [[ ! -x "${IMPORT_HELPER}" ]]; then
    echo "[run_train_best_cuda] Import helper not found/executable: ${IMPORT_HELPER}" >&2
    if is_truthy "${required}"; then
      return 1
    fi
    return 0
  fi

  mkdir -p reports
  local import_log="reports/import_resources_train.log"
  local smoke_log="reports/resource_smoke_train.log"
  local smoke_retry_log="reports/resource_smoke_train_retry.log"
  local import_mode="${ANNA_PREIMPORT_MODE:-auto}"
  local use_xvfb="${ANNA_IMPORT_USE_XVFB:-1}"
  local force_sw="${ANNA_IMPORT_FORCE_SOFTWARE:-1}"
  local disable_plugins="${ANNA_PREIMPORT_DISABLE_EDITOR_PLUGINS:-1}"

  if "${IMPORT_HELPER}" \
    --godot-bin "${godot_bin}" \
    --project-path "." \
    --import-log "${import_log}" \
    --smoke-log "${smoke_log}" \
    --smoke-retry-log "${smoke_retry_log}" \
    --timeout-import "${ANNA_PREIMPORT_TIMEOUT_SEC:-600}" \
    --timeout-smoke "${ANNA_PREIMPORT_SMOKE_TIMEOUT_SEC:-180}" \
    --clean-cache "${clean_cache}" \
    --disable-editor-plugins "${disable_plugins}" \
    --xvfb "${use_xvfb}" \
    --force-software "${force_sw}" \
    --import-mode "${import_mode}" \
    --allow-smoke-retry "1"; then
    echo "[run_train_best_cuda] Preimport + smoke OK."
    PREIMPORT_OK=1
    return 0
  fi

  if is_truthy "${required}"; then
    echo "[run_train_best_cuda] Preimport required and still failing."
    return 1
  fi
  echo "[run_train_best_cuda] Preimport failed but continuing (ANNA_PREIMPORT_REQUIRED=${required})."
  return 0
}

export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-0}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"

# Force NVIDIA OpenGL/GLES2 in headless Godot on vast.ai and similar bare-metal GPU servers.
# Without this, Godot falls back to llvmpipe (software) -> ~500 FPS instead of 2000+.
_NV_LIB_PATHS="/usr/lib/x86_64-linux-gnu/nvidia:/usr/lib/nvidia:/usr/local/nvidia/lib64"
_NV_LIB_PATHS="${_NV_LIB_PATHS}:/usr/lib/x86_64-linux-gnu:/usr/lib"
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
  export LD_LIBRARY_PATH="${_NV_LIB_PATHS}:${LD_LIBRARY_PATH}"
else
  export LD_LIBRARY_PATH="${_NV_LIB_PATHS}"
fi
unset _NV_LIB_PATHS
echo "[run_train_best_cuda] LD_LIBRARY_PATH (NVIDIA boosted): ${LD_LIBRARY_PATH}"

export ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}"
export ANNA_GODOT_VIDEO_DRIVER="${ANNA_GODOT_VIDEO_DRIVER:-GLES2}"
export ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}"
export ANNA_GODOT_READY_TIMEOUT_SEC="${ANNA_GODOT_READY_TIMEOUT_SEC:-240}"
export ANNA_GODOT_LAUNCH_STAGGER_SEC="${ANNA_GODOT_LAUNCH_STAGGER_SEC:-0.80}"
export ANNA_GODOT_DISABLE_RENDER_LOOP="${ANNA_GODOT_DISABLE_RENDER_LOOP:-1}"
export ANNA_GODOT_SERVER_VIDEO_DRIVER="${ANNA_GODOT_SERVER_VIDEO_DRIVER:-}"
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG="${ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG:-1}"
export ANNA_GODOT_QUIET="${ANNA_GODOT_QUIET:-1}"
export ANNA_CONNECT_MAX_RETRIES="${ANNA_CONNECT_MAX_RETRIES:-240}"
export ANNA_CONNECT_RETRY_DELAY_SEC="${ANNA_CONNECT_RETRY_DELAY_SEC:-1.0}"
export ANNA_IMPORT_PREWARM_STRICT="${ANNA_IMPORT_PREWARM_STRICT:-0}"
export ODISEA_DISABLE_PERFMON_IN_RL="${ODISEA_DISABLE_PERFMON_IN_RL:-1}"
export ODISEA_QUIET_PERFMON="${ODISEA_QUIET_PERFMON:-1}"
export ODISEA_DISABLE_FAKE_SHADOW="${ODISEA_DISABLE_FAKE_SHADOW:-1}"
export ODISEA_DISABLE_SHADER_WARMUP="${ODISEA_DISABLE_SHADER_WARMUP:-1}"
export ODISEA_DISABLE_SHADER_WARMUP_IN_RL="${ODISEA_DISABLE_SHADER_WARMUP_IN_RL:-1}"
export ANNA_CUDA_TF32="${ANNA_CUDA_TF32:-1}"
export ANNA_CUDNN_BENCHMARK="${ANNA_CUDNN_BENCHMARK:-1}"
export ANNA_TORCH_MATMUL_PRECISION="${ANNA_TORCH_MATMUL_PRECISION:-high}"
export ANNA_RL_DISABLE_CPU_SLEEP="${ANNA_RL_DISABLE_CPU_SLEEP:-1}"
export ANNA_RL_MAX_STEPS="${ANNA_RL_MAX_STEPS:-1200}"
export ANNA_RL_TIME_PENALTY="${ANNA_RL_TIME_PENALTY:--0.03}"
export ANNA_RL_DISABLE_QODOT="${ANNA_RL_DISABLE_QODOT:-1}"

# godot3-server + '--max-fps 0' can cap RL throughput hard. Keep it unset by default.
if [[ "${ANNA_GODOT_MAX_FPS:-}" == "0" ]]; then
  echo "[run_train_best_cuda] WARNING: ANNA_GODOT_MAX_FPS=0 reduces godot3-server SPS. Unsetting."
  unset ANNA_GODOT_MAX_FPS
fi

# Avoid leaking ad-hoc OYS scripts from the shell into RL runs unless explicitly requested.
if [[ "${ANNA_KEEP_OYS_AUTO_RUN:-0}" != "1" ]]; then
  unset OYS_AUTO_RUN || true
  unset ANNA_FORCE_OYS_NOOP || true
fi

MODEL_POINTER_FILE="${ANNA_MODEL_POINTER_FILE:-agents/models/.anna_cuda_big_last_model_out}"
if [[ -z "${MODEL_OUT:-}" ]]; then
  if is_truthy "${ANNA_AUTO_RESUME:-1}" && ! is_truthy "${ANNA_NEW_RUN:-0}" && [[ -f "${MODEL_POINTER_FILE}" ]]; then
    MODEL_OUT="$(head -n 1 "${MODEL_POINTER_FILE}")"
    echo "[run_train_best_cuda] Reusing previous MODEL_OUT from pointer: ${MODEL_OUT}"
  else
    STAMP="$(date +%Y%m%d_%H%M%S)"
    MODEL_OUT="agents/models/anna_ppo_cuda_big_${STAMP}.zip"
    echo "[run_train_best_cuda] New MODEL_OUT: ${MODEL_OUT}"
  fi
fi
mkdir -p "$(dirname "${MODEL_POINTER_FILE}")"
echo "${MODEL_OUT}" > "${MODEL_POINTER_FILE}"

RESUME_MODE="${RESUME_MODE:-auto}"
if [[ "${RESUME_MODE}" != "auto" && "${RESUME_MODE}" != "always" && "${RESUME_MODE}" != "never" ]]; then
  echo "[run_train_best_cuda] Invalid RESUME_MODE=${RESUME_MODE}, forcing auto."
  RESUME_MODE="auto"
fi
if [[ -n "${RESUME_FROM:-}" ]]; then
  EXTRA_TRAIN_ARGS+=("--resume-from" "${RESUME_FROM}")
fi

run_preimport_step
if [[ "${PREIMPORT_OK}" -eq 1 ]] && is_truthy "${ANNA_SKIP_PY_PREWARM_AFTER_PREIMPORT:-1}"; then
  EXTRA_TRAIN_ARGS+=("--skip-import-prewarm")
fi

TRAIN_GODOT_BIN="$(resolve_train_godot_bin || true)"
if [[ -z "${TRAIN_GODOT_BIN}" ]]; then
  echo "[run_train_best_cuda] Could not resolve Godot binary for training." >&2
  exit 1
fi
echo "[run_train_best_cuda] Training Godot binary: ${TRAIN_GODOT_BIN}"
if [[ "${TRAIN_GODOT_BIN}" != *server* ]]; then
  echo "[run_train_best_cuda] WARNING: server binary not available; using ${TRAIN_GODOT_BIN}."
fi

"${PYTHON_BIN}" agents/train_anna_cuda_big.py \
  --godot-bin "${TRAIN_GODOT_BIN}" \
  --device auto \
  --cpu-threads "${CPU_THREADS:-16}" \
  --num-envs "${NUM_ENVS:-8}" \
  --num-envs-stage3 "${NUM_ENVS_STAGE3:-2}" \
  --scene-stage1 "${SCENE_STAGE1:-core_v2/tests/TestScene_RL.tscn}" \
  --scene-stage2 "${SCENE_STAGE2:-core_v2/tests/TestScene_RL_2.tscn}" \
  --scene-stage3 "${SCENE_STAGE3:-core_v2/tests/TestScene_RL_BaseTerrace.tscn}" \
  --timesteps-stage1 "${STAGE1_STEPS:-150000}" \
  --timesteps-stage2 "${STAGE2_STEPS:-650000}" \
  --timesteps-stage3 "${STAGE3_STEPS:-700000}" \
  --stage3-max-steps "${STAGE3_MAX_STEPS:-800}" \
  --stage3-spawn-x "${STAGE3_SPAWN_X:-5.0}" \
  --stage3-spawn-y "${STAGE3_SPAWN_Y:-2.5}" \
  --stage3-spawn-z "${STAGE3_SPAWN_Z:-15.0}" \
  --stage3-target-radius-min "${STAGE3_TARGET_RADIUS_MIN:-4.0}" \
  --stage3-target-radius-max "${STAGE3_TARGET_RADIUS_MAX:-10.0}" \
  --stage3-target-y "${STAGE3_TARGET_Y:-2.0}" \
  --n-steps "${N_STEPS:-4096}" \
  --batch-size "${BATCH_SIZE:-8192}" \
  --n-epochs "${N_EPOCHS:-10}" \
  --learning-rate "${LR:-0.00025}" \
  --entropy-coef "${ENT_COEF:-0.015}" \
  --gamma "${GAMMA:-0.995}" \
  --gae-lambda "${GAE_LAMBDA:-0.98}" \
  --clip-range "${CLIP_RANGE:-0.2}" \
  --checkpoint-every "${CHECKPOINT_EVERY:-50000}" \
  --resume "${RESUME_MODE}" \
  --model-out "${MODEL_OUT}" \
  --verbose "${VERBOSE:-1}" \
  "${EXTRA_TRAIN_ARGS[@]}" \
  "$@"

echo "[run_train_best_cuda] done model=${MODEL_OUT}"
