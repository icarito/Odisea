#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

is_truthy() {
  local v="${1:-}"
  v="${v,,}"
  [[ "${v}" == "1" || "${v}" == "true" || "${v}" == "yes" || "${v}" == "on" ]]
}

GODOT_BIN="${GODOT_BIN:-godot3-bin}"
PROJECT_PATH="."
IMPORT_LOG="reports/import_resources.log"
SMOKE_LOG="reports/resource_smoke.log"
SMOKE_RETRY_LOG="reports/resource_smoke_retry.log"
TIMEOUT_IMPORT_SEC="${TIMEOUT_IMPORT_SEC:-600}"
TIMEOUT_SMOKE_SEC="${TIMEOUT_SMOKE_SEC:-180}"
CLEAN_CACHE="${CLEAN_CACHE:-1}"
DISABLE_EDITOR_PLUGINS="${DISABLE_EDITOR_PLUGINS:-1}"
USE_XVFB="${USE_XVFB:-0}"
FORCE_SOFTWARE="${FORCE_SOFTWARE:-0}"
IMPORT_MODE="${IMPORT_MODE:-auto}" # auto|quick|full
ALLOW_SMOKE_RETRY="${ALLOW_SMOKE_RETRY:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --godot-bin) GODOT_BIN="$2"; shift 2 ;;
    --project-path) PROJECT_PATH="$2"; shift 2 ;;
    --import-log) IMPORT_LOG="$2"; shift 2 ;;
    --smoke-log) SMOKE_LOG="$2"; shift 2 ;;
    --smoke-retry-log) SMOKE_RETRY_LOG="$2"; shift 2 ;;
    --timeout-import) TIMEOUT_IMPORT_SEC="$2"; shift 2 ;;
    --timeout-smoke) TIMEOUT_SMOKE_SEC="$2"; shift 2 ;;
    --clean-cache) CLEAN_CACHE="$2"; shift 2 ;;
    --disable-editor-plugins) DISABLE_EDITOR_PLUGINS="$2"; shift 2 ;;
    --xvfb) USE_XVFB="$2"; shift 2 ;;
    --force-software) FORCE_SOFTWARE="$2"; shift 2 ;;
    --import-mode) IMPORT_MODE="$2"; shift 2 ;;
    --allow-smoke-retry) ALLOW_SMOKE_RETRY="$2"; shift 2 ;;
    *)
      echo "[godot_import_smoke] Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$(dirname "${IMPORT_LOG}")"
mkdir -p "$(dirname "${SMOKE_LOG}")"
mkdir -p "$(dirname "${SMOKE_RETRY_LOG}")"

if is_truthy "${CLEAN_CACHE}"; then
  echo "[godot_import_smoke] Cleaning import caches (.godot/imported; preserving tracked .import artifacts)..."
  rm -rf "${PROJECT_PATH}/.godot/imported"
  mkdir -p "${PROJECT_PATH}/.import"
  if git -C "${PROJECT_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    while IFS= read -r -d '' import_file; do
      rel_path="${import_file#${PROJECT_PATH}/}"
      if ! git -C "${PROJECT_PATH}" ls-files --error-unmatch "${rel_path}" >/dev/null 2>&1; then
        rm -f "${import_file}"
      fi
    done < <(find "${PROJECT_PATH}/.import" -mindepth 1 -maxdepth 1 -type f -print0)
  fi
fi

project_file="${PROJECT_PATH}/project.godot"
plugins_backup=""
plugins_patched=0
cleanup_project_file() {
  if [[ "${plugins_patched}" -eq 1 && -n "${plugins_backup}" && -f "${plugins_backup}" ]]; then
    mv -f "${plugins_backup}" "${project_file}"
    echo "[godot_import_smoke] Restored project.godot."
  fi
}
trap cleanup_project_file EXIT

if is_truthy "${DISABLE_EDITOR_PLUGINS}" && [[ -f "${project_file}" ]]; then
  plugins_backup="${project_file}.preimport.bak"
  cp "${project_file}" "${plugins_backup}"
  awk '
    BEGIN { in_editor_plugins = 0 }
    /^\[editor_plugins\]$/ { in_editor_plugins = 1; print; next }
    in_editor_plugins == 1 && /^enabled=/ {
      print "enabled=PoolStringArray( )"
      in_editor_plugins = 0
      next
    }
    { print }
  ' "${plugins_backup}" > "${project_file}"
  plugins_patched=1
  echo "[godot_import_smoke] Editor plugins disabled for import pass."
fi

if [[ "${IMPORT_MODE}" != "auto" && "${IMPORT_MODE}" != "quick" && "${IMPORT_MODE}" != "full" ]]; then
  echo "[godot_import_smoke] Invalid --import-mode=${IMPORT_MODE}; expected auto|quick|full" >&2
  exit 2
fi
if [[ "${IMPORT_MODE}" == "auto" ]]; then
  if is_truthy "${CLEAN_CACHE}"; then
    IMPORT_MODE="full"
  else
    IMPORT_MODE="quick"
  fi
fi

import_regex='SCRIPT ERROR:|Parse Error:|referenced nonexistent resource|No loader found for resource|Failed loading resource:|Unrecognized binary resource file'
smoke_regex='SCRIPT ERROR:|Parse Error:|referenced nonexistent resource|No loader found for resource|Failed loading resource:'

run_cmd() {
  local timeout_sec="$1"
  local log_file="$2"
  shift 2
  local -a cmd=("$@")
  if is_truthy "${USE_XVFB}"; then
    cmd=("xvfb-run" "-a" "-s" "-screen 0 1024x768x24+120" "${cmd[@]}")
  fi
  local -a env_prefix=("env" "-u" "__NV_PRIME_RENDER_OFFLOAD" "-u" "__GLX_VENDOR_LIBRARY_NAME" "GODOT_SILENCE_ROOT_WARNING=1")
  set +e
  if is_truthy "${FORCE_SOFTWARE}"; then
    timeout "${timeout_sec}s" "${env_prefix[@]}" LIBGL_ALWAYS_SOFTWARE=1 "${cmd[@]}" 2>&1 | tee "${log_file}"
  else
    timeout "${timeout_sec}s" "${env_prefix[@]}" "${cmd[@]}" 2>&1 | tee "${log_file}"
  fi
  local rc="${PIPESTATUS[0]}"
  set -e
  return "${rc}"
}

run_import_once() {
  local -a cmd=("${GODOT_BIN}" "--path" "${PROJECT_PATH}" "--headless" "--no-window" "--audio-driver" "Dummy")
  if [[ "${IMPORT_MODE}" == "quick" ]]; then
    cmd=("${GODOT_BIN}" "--path" "${PROJECT_PATH}" "--editor" "--quit" "--headless" "--no-window" "--audio-driver" "Dummy")
  else
    cmd+=("-e")
  fi
  echo "[godot_import_smoke] Import mode=${IMPORT_MODE}: ${cmd[*]}"
  if ! run_cmd "${TIMEOUT_IMPORT_SEC}" "${IMPORT_LOG}" "${cmd[@]}"; then
    local rc=$?
    if [[ "${rc}" -eq 124 ]]; then
      echo "[godot_import_smoke] Import timed out (${TIMEOUT_IMPORT_SEC}s)."
      return 1
    fi
    echo "[godot_import_smoke] Import command failed (exit=${rc})."
    return 1
  fi
  if grep -E -q "${import_regex}" "${IMPORT_LOG}"; then
    echo "[godot_import_smoke] Import reported parse/resource errors."
    return 1
  fi
  return 0
}

run_smoke_once() {
  local log_file="$1"
  local -a cmd=("${GODOT_BIN}" "--headless" "--no-window" "--audio-driver" "Dummy" "-s" "tests/ci_resource_smoke.gd")
  echo "[godot_import_smoke] Smoke: ${cmd[*]}"
  if ! run_cmd "${TIMEOUT_SMOKE_SEC}" "${log_file}" "${cmd[@]}"; then
    local rc=$?
    if [[ "${rc}" -eq 124 ]]; then
      echo "[godot_import_smoke] Smoke timed out (${TIMEOUT_SMOKE_SEC}s)."
      return 1
    fi
    echo "[godot_import_smoke] Smoke command failed (exit=${rc})."
    return 1
  fi
  if grep -q "\[CI_SMOKE\] Missing resources count:" "${log_file}"; then
    echo "[godot_import_smoke] Smoke detected missing resources."
    return 1
  fi
  if grep -E -q "${smoke_regex}" "${log_file}"; then
    echo "[godot_import_smoke] Smoke detected parse/resource errors."
    return 1
  fi
  return 0
}

import_ok=0
if run_import_once; then
  import_ok=1
fi

if run_smoke_once "${SMOKE_LOG}"; then
  if [[ "${import_ok}" -eq 0 ]]; then
    echo "[godot_import_smoke] Import failed/timed out, but smoke passed."
  fi
  echo "[godot_import_smoke] Preimport + smoke OK."
  exit 0
fi

if is_truthy "${ALLOW_SMOKE_RETRY}"; then
  echo "[godot_import_smoke] First smoke failed, retrying once..."
  if run_smoke_once "${SMOKE_RETRY_LOG}"; then
    echo "[godot_import_smoke] Smoke retry OK."
    exit 0
  fi
fi

echo "[godot_import_smoke] Preimport/smoke failed."
exit 1
