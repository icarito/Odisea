#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

STATE_DIR="agents/runs/watchdog_state"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/watchdog.log"

RUN_MINUTES="${RUN_MINUTES:-120}"
TOTAL_TIMESTEPS="${TOTAL_TIMESTEPS:-3000000}"
CHUNK_TIMESTEPS="${CHUNK_TIMESTEPS:-16000}"
CPU_THREADS="${CPU_THREADS:-6}"
MAX_CPU_TEMP_C="${MAX_CPU_TEMP_C:-90}"
RESUME_CPU_TEMP_C="${RESUME_CPU_TEMP_C:-84}"
TEMP_POLL_SEC="${TEMP_POLL_SEC:-15}"
POLL_SEC="${POLL_SEC:-60}"
NUM_ENVS="${NUM_ENVS:-2}"
NUM_ENVS_STAGE1="${NUM_ENVS_STAGE1:-${NUM_ENVS}}"
NUM_ENVS_STAGE2="${NUM_ENVS_STAGE2:-${NUM_ENVS}}"
NUM_ENVS_STAGE3="${NUM_ENVS_STAGE3:-${NUM_ENVS}}"

latest_run_dir() {
  ls -dt agents/runs/lunch_smart_long90b_* agents/runs/lunch_smart_long90_* 2>/dev/null | head -n1
}

latest_model_any() {
  local dir="$1/models"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  local f
  f="$(find "$dir" -maxdepth 1 -type f -name '*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  echo "${f:-}"
}

latest_good_seed() {
  local f=""
  # Prefer latest model from recent long-run dirs.
  f="$(find agents/runs -maxdepth 3 -type f -path '*/models/*.zip' -name 'anna_lunch_*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  if [[ -n "${f:-}" ]]; then
    echo "$f"
    return 0
  fi
  # Fallback: models dir excluding probe/debug artifacts.
  f="$(find agents/models -maxdepth 1 -type f -name '*.zip' ! -name '_probe*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  echo "${f:-}"
}

launcher_alive() {
  local pid="$1"
  [[ -n "$pid" ]] && ps -p "$pid" >/dev/null 2>&1
}

start_run() {
  local seed_model="$1"
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  local run_dir="agents/runs/lunch_smart_long90b_${stamp}"
  mkdir -p "$run_dir"

  (
    export RUN_DIR="$run_dir"
    export RUN_MINUTES TOTAL_TIMESTEPS CHUNK_TIMESTEPS CPU_THREADS
    export NUM_ENVS NUM_ENVS_STAGE1 NUM_ENVS_STAGE2 NUM_ENVS_STAGE3
    export TRAIN_DEVICE=cpu
    export MAX_CPU_TEMP_C RESUME_CPU_TEMP_C TEMP_POLL_SEC
    export STAGES_CSV='core_v2/tests/TestScene_RL.tscn,core_v2/tests/TestScene_RL_2.tscn,core_v2/tests/TestScene_RL_3.tscn,core_v2/tests/TestScene_RL_3_Door.tscn'
    export START_STAGE_IDX=1
    export MODEL_IN="$seed_model"
    export PROMOTE_MIN_DELTA=60
    export PROMOTE_MIN_SUCCESS_PCT=0.0
    export N_STEPS=2048
    export BATCH_SIZE=2048
    export N_EPOCHS=3
    export NET_ARCH='192,192'
    export CHECKPOINT_EVERY=16000
    export EVAL_EPISODES=6
    export EVAL_MAX_STEPS=1400
    export ANNA_RL_MAX_STEPS=1400
    export ANNA_RL_DISABLE_QODOT=1
    export ANNA_RL_PHYSICS_FPS=2000
    export ANNA_RL_TARGET_FPS=2000
    export ANNA_RL_PHYSICS_FPS_CAP=2000
    export ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME=64
    export ANNA_RL_POLL_SLEEP_USEC=0
    export ANNA_RL_DISABLE_CPU_SLEEP=1
    export ANNA_GODOT_PREFER_SERVER=1
    export ANNA_GODOT_SERVER_FALLBACK=0
    export ANNA_GODOT_DISABLE_RENDER_LOOP=1
    export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG=1
    export GODOT_BIN=godot3-server
    nohup ./agents/run_lunch_adaptive_256k.sh > "$run_dir/launcher.log" 2>&1 &
    echo $! > "$run_dir/pid.txt"
  )

  echo "$(date '+%F %T') started run_dir=$run_dir seed=$seed_model" | tee -a "$LOG"
}

while true; do
  run_dir="$(latest_run_dir || true)"
  if [[ -z "${run_dir:-}" ]]; then
    seed="$(latest_good_seed)"
    if [[ -n "${seed:-}" ]]; then
      start_run "$seed"
    else
      echo "$(date '+%F %T') no run and no seed model found" | tee -a "$LOG"
    fi
    sleep "$POLL_SEC"
    continue
  fi

  pid=""
  if [[ -f "$run_dir/pid.txt" ]]; then
    pid="$(cat "$run_dir/pid.txt" 2>/dev/null || true)"
  fi

  if ! launcher_alive "$pid"; then
    seed="$(latest_model_any "$run_dir")"
    if [[ -z "${seed:-}" ]]; then
      seed="$(latest_good_seed)"
    fi
    if [[ -n "${seed:-}" ]]; then
      echo "$(date '+%F %T') detected stopped run pid=${pid:-none}; relaunching" | tee -a "$LOG"
      start_run "$seed"
    else
      echo "$(date '+%F %T') stopped run but no seed model available" | tee -a "$LOG"
    fi
  else
    chunk_line="$(tail -n 200 "$run_dir/manifest.log" 2>/dev/null | rg "chunk=.*score=" -n -S | tail -n1 || true)"
    temp_line=""
    if command -v sensors >/dev/null 2>&1; then
      temp_line="$(sensors | rg "Package id 0|CPU:" -n -S | tr '\n' ';' | sed 's/;$/ /' || true)"
    fi
    echo "$(date '+%F %T') healthy run_dir=$run_dir pid=$pid ${chunk_line:+last_eval='$chunk_line'} ${temp_line:+temps='$temp_line'}" >> "$LOG"
  fi

  sleep "$POLL_SEC"
done
