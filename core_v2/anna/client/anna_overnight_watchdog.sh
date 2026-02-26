#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   core_v2/anna/client/anna_overnight_watchdog.sh [interval_seconds] [stale_minutes]
# Defaults:
#   interval_seconds = 1800 (30 min)
#   stale_minutes = 45

INTERVAL="${1:-1800}"
STALE_MINUTES="${2:-45}"

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${PYTHON_BIN:-}" ]]; then
  if [[ -x ".venv311/bin/python" ]]; then
    PYTHON_BIN=".venv311/bin/python"
  elif [[ -x ".venv/bin/python" ]]; then
    PYTHON_BIN=".venv/bin/python"
  else
    PYTHON_BIN="python3"
  fi
fi
SWEEP_SCRIPT="core_v2/anna/client/anna_overnight_sweep.py"
SCENE="${ANNA_SCENE:-core_v2/tests/TestScene_RL.tscn}"
GODOT_BIN="${GODOT_BIN:-godot3-server}"

ART_DIR="artifacts/anna_overnight"
LOG_DIR="$ART_DIR/logs"
WATCHDOG_LOG="$LOG_DIR/watchdog.log"
PID_FILE="$ART_DIR/watchdog_sweep.pid"
WATCHDOG_PID_FILE="$ART_DIR/watchdog.pid"

mkdir -p "$LOG_DIR"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" | tee -a "$WATCHDOG_LOG"; }

is_sweep_alive() {
  pgrep -fa "${SWEEP_SCRIPT}" >/dev/null 2>&1
}

is_worker_alive() {
  pgrep -fa "artifacts/anna_overnight/runs/_temp_(train|eval)\.py" >/dev/null 2>&1
}

kill_sweep_and_workers() {
  pkill -f "${SWEEP_SCRIPT}" >/dev/null 2>&1 || true
  pkill -f "artifacts/anna_overnight/runs/_temp_train\.py" >/dev/null 2>&1 || true
  pkill -f "artifacts/anna_overnight/runs/_temp_eval\.py" >/dev/null 2>&1 || true
}

latest_log_age_minutes() {
  local latest
  latest="$(ls -1t "$LOG_DIR"/run_*.log 2>/dev/null | head -n1 || true)"
  if [[ -z "$latest" ]]; then
    echo 999999
    return
  fi
  local now epoch
  now="$(date +%s)"
  epoch="$(stat -c %Y "$latest" 2>/dev/null || echo 0)"
  if [[ "$epoch" -le 0 ]]; then
    echo 999999
    return
  fi
  echo $(( (now - epoch) / 60 ))
}

start_sweep() {
  log "Starting takeover sweep: $PYTHON_BIN $SWEEP_SCRIPT --scene $SCENE --godot-bin $GODOT_BIN"
  nohup "$PYTHON_BIN" "$SWEEP_SCRIPT" --scene "$SCENE" --godot-bin "$GODOT_BIN" \
    >> "$LOG_DIR/watchdog_takeover.log" 2>&1 &
  echo $! > "$PID_FILE"
  log "Takeover process PID=$(cat "$PID_FILE")"
}

latest_run_log() {
  ls -1t "$LOG_DIR"/run_*.log 2>/dev/null | head -n1 || true
}

latest_run_stuck() {
  local latest age
  latest="$(latest_run_log)"
  if [[ -z "$latest" ]]; then
    return 1
  fi
  age="$(latest_log_age_minutes)"
  if [[ "$age" -lt "$STALE_MINUTES" ]]; then
    return 1
  fi
  tail -n 200 "$latest" | grep -E "(Timed out waiting for ANNA bridge|Godot failed to become ready|Training failed:)" >/dev/null 2>&1
}

failed_streak_high() {
  local lb
  local fail_count
  lb="$ART_DIR/leaderboard.csv"
  if [[ ! -f "$lb" ]]; then
    return 1
  fi
  fail_count="$(tail -n 8 "$lb" | grep -c ",failed," || true)"
  [[ "${fail_count:-0}" -ge 3 ]]
}

should_force_takeover() {
  if latest_run_stuck; then
    return 0
  fi
  if failed_streak_high; then
    return 0
  fi
  return 1
}

log "Watchdog started. interval=${INTERVAL}s stale=${STALE_MINUTES}m root=$ROOT_DIR"
echo $$ > "$WATCHDOG_PID_FILE"

while true; do
  if should_force_takeover; then
    log "ALERT: sweep appears unhealthy (stuck/fail-loop). Taking control."
    kill_sweep_and_workers
    sleep 2
    start_sweep
    sleep "$INTERVAL"
    continue
  fi

  if is_sweep_alive || is_worker_alive; then
    age="$(latest_log_age_minutes)"
    log "OK: sweep/worker alive (latest run log age=${age}m)."
  else
    age="$(latest_log_age_minutes)"
    if [[ "$age" -ge "$STALE_MINUTES" ]]; then
      log "ALERT: No sweep/worker process and logs stale (${age}m). Taking over."
      start_sweep
    else
      log "WARN: No sweep/worker process, but logs are recent (${age}m). Waiting."
    fi
  fi
  sleep "$INTERVAL"
done
