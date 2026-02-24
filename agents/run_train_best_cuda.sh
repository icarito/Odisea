#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
PREIMPORT_OK=0
EXTRA_TRAIN_ARGS=()

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

run_import_once() {
  local godot_bin="$1"
  local log_file="$2"
  local timeout_sec="${ANNA_PREIMPORT_TIMEOUT_SEC:-600}"
  local use_xvfb="${ANNA_IMPORT_USE_XVFB:-1}"
  local force_sw="${ANNA_IMPORT_FORCE_SOFTWARE:-1}"
  local use_quit="${ANNA_PREIMPORT_USE_QUIT:-1}"
  if is_truthy "${ANNA_IMPORT_CLEAN_CACHE:-0}"; then
    use_quit="0"
  fi
  local -a cmd=()
  if is_truthy "${use_quit}"; then
    cmd=("${godot_bin}" "--path" "." "--editor" "--quit" "--headless" "--no-window" "--audio-driver" "Dummy")
  else
    cmd=("${godot_bin}" "--path" "." "-e" "--headless" "--no-window" "--audio-driver" "Dummy")
  fi
  if is_truthy "${use_xvfb}"; then
    cmd=("xvfb-run" "-a" "-s" "-screen 0 1024x768x24+120" "${cmd[@]}")
  fi
  echo "[run_train_best_cuda] Importing resources: ${cmd[*]}"
  local -a env_prefix=("env" "-u" "__NV_PRIME_RENDER_OFFLOAD" "-u" "__GLX_VENDOR_LIBRARY_NAME" "GODOT_SILENCE_ROOT_WARNING=1")
  set +e
  if is_truthy "${force_sw}"; then
    timeout "${timeout_sec}s" "${env_prefix[@]}" LIBGL_ALWAYS_SOFTWARE=1 "${cmd[@]}" 2>&1 | tee "${log_file}"
  else
    timeout "${timeout_sec}s" "${env_prefix[@]}" "${cmd[@]}" 2>&1 | tee "${log_file}"
  fi
  local rc="${PIPESTATUS[0]}"
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    echo "[run_train_best_cuda] Import timed out (${timeout_sec}s)."
    return 1
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "[run_train_best_cuda] Import failed (exit=${rc})."
    return "${rc}"
  fi
  if grep -E -q "SCRIPT ERROR:|Parse Error:|referenced nonexistent resource|No loader found for resource|Failed loading resource:|Unrecognized binary resource file" "${log_file}"; then
    echo "[run_train_best_cuda] Import reported resource/parse errors."
    return 1
  fi
  return 0
}

run_smoke_once() {
  local godot_bin="$1"
  local log_file="$2"
  local timeout_sec="${ANNA_PREIMPORT_SMOKE_TIMEOUT_SEC:-180}"
  local use_xvfb="${ANNA_IMPORT_USE_XVFB:-1}"
  local force_sw="${ANNA_IMPORT_FORCE_SOFTWARE:-1}"
  local -a cmd=("${godot_bin}" "--headless" "--no-window" "--audio-driver" "Dummy" "-s" "tests/ci_resource_smoke.gd")
  if is_truthy "${use_xvfb}"; then
    cmd=("xvfb-run" "-a" "-s" "-screen 0 1024x768x24+120" "${cmd[@]}")
  fi
  echo "[run_train_best_cuda] Running resource smoke: ${cmd[*]}"
  local -a env_prefix=("env" "-u" "__NV_PRIME_RENDER_OFFLOAD" "-u" "__GLX_VENDOR_LIBRARY_NAME" "GODOT_SILENCE_ROOT_WARNING=1")
  set +e
  if is_truthy "${force_sw}"; then
    timeout "${timeout_sec}s" "${env_prefix[@]}" LIBGL_ALWAYS_SOFTWARE=1 "${cmd[@]}" 2>&1 | tee "${log_file}"
  else
    timeout "${timeout_sec}s" "${env_prefix[@]}" "${cmd[@]}" 2>&1 | tee "${log_file}"
  fi
  local rc="${PIPESTATUS[0]}"
  set -e
  if [[ "${rc}" -eq 124 ]]; then
    echo "[run_train_best_cuda] Smoke timed out (${timeout_sec}s)."
    return 1
  fi
  if [[ "${rc}" -ne 0 ]]; then
    echo "[run_train_best_cuda] Smoke failed (exit=${rc})."
    return "${rc}"
  fi
  if grep -q "\\[CI_SMOKE\\] Missing resources count:" "${log_file}"; then
    echo "[run_train_best_cuda] Smoke detected missing resources."
    return 1
  fi
  if grep -E -q "SCRIPT ERROR:|Parse Error:|referenced nonexistent resource|Failed loading resource:" "${log_file}"; then
    echo "[run_train_best_cuda] Smoke detected parse/resource errors."
    return 1
  fi
  return 0
}

run_preimport_step() {
  local enabled="${ANNA_PREIMPORT_BEFORE_TRAIN:-1}"
  if ! is_truthy "${enabled}"; then
    echo "[run_train_best_cuda] Preimport step disabled (ANNA_PREIMPORT_BEFORE_TRAIN=${enabled})."
    return 0
  fi

  local required="${ANNA_PREIMPORT_REQUIRED:-1}"
  local clean_cache="${ANNA_IMPORT_CLEAN_CACHE:-0}"
  if is_truthy "${clean_cache}"; then
    echo "[run_train_best_cuda] Cleaning import caches (.import, .godot/imported) before preimport..."
    rm -rf .godot/imported
    mkdir -p .import
    find .import -mindepth 1 -maxdepth 1 -type f -delete || true
  fi

  local godot_bin
  if ! godot_bin="$(resolve_import_godot_bin)"; then
    echo "[run_train_best_cuda] Could not resolve Godot binary for preimport."
    if is_truthy "${required}"; then
      return 1
    fi
    return 0
  fi

  mkdir -p reports
  local disable_plugins="${ANNA_PREIMPORT_DISABLE_EDITOR_PLUGINS:-1}"
  local plugins_backup="project.godot.preimport.bak"
  local plugins_patched=0
  if is_truthy "${disable_plugins}"; then
    cp project.godot "${plugins_backup}"
    awk '
      BEGIN { in_editor_plugins = 0 }
      /^\[editor_plugins\]$/ { in_editor_plugins = 1; print; next }
      in_editor_plugins == 1 && /^enabled=/ {
        print "enabled=PoolStringArray( )"
        in_editor_plugins = 0
        next
      }
      { print }
    ' "${plugins_backup}" > project.godot
    plugins_patched=1
    echo "[run_train_best_cuda] Editor plugins disabled for preimport pass."
  fi
  cleanup_preimport_project() {
    if [[ "${plugins_patched}" -eq 1 && -f "${plugins_backup}" ]]; then
      mv -f "${plugins_backup}" project.godot
      echo "[run_train_best_cuda] Restored project.godot after preimport."
    fi
  }
  trap cleanup_preimport_project RETURN

  local import_log="reports/import_resources_train.log"
  local smoke_log="reports/resource_smoke_train.log"
  local smoke_retry_log="reports/resource_smoke_train_retry.log"

  if run_import_once "${godot_bin}" "${import_log}" && run_smoke_once "${godot_bin}" "${smoke_log}"; then
    echo "[run_train_best_cuda] Preimport + smoke OK."
    PREIMPORT_OK=1
    return 0
  fi

  echo "[run_train_best_cuda] Preimport/smoke first pass failed, retrying smoke once..."
  if run_smoke_once "${godot_bin}" "${smoke_retry_log}"; then
    echo "[run_train_best_cuda] Smoke retry OK."
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

export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-360}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}"
export ANNA_GODOT_VIDEO_DRIVER="${ANNA_GODOT_VIDEO_DRIVER:-GLES2}"
export ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-1}"
export ANNA_GODOT_READY_TIMEOUT_SEC="${ANNA_GODOT_READY_TIMEOUT_SEC:-240}"
export ANNA_GODOT_LAUNCH_STAGGER_SEC="${ANNA_GODOT_LAUNCH_STAGGER_SEC:-0.80}"
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

"${PYTHON_BIN}" agents/train_anna_cuda_big.py \
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
