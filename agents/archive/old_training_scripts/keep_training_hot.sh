#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

STATE_DIR="agents/runs/keeper_state"
mkdir -p "${STATE_DIR}"
LOG="${STATE_DIR}/keeper.log"

latest_seed() {
  local f=""
  f="$(find agents/runs -maxdepth 3 -type f -path '*/models/*.zip' -name 'anna_lunch_*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  if [[ -n "${f:-}" ]]; then
    echo "$f"
    return 0
  fi
  f="$(find agents/models -maxdepth 1 -type f -name '*.zip' ! -name '_probe*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
  echo "${f:-}"
}

while true; do
  seed="$(latest_seed)"
  if [[ -z "${seed:-}" ]]; then
    echo "$(date '+%F %T') no seed model found; retry in 30s" | tee -a "${LOG}"
    sleep 30
    continue
  fi

  stamp="$(date +%Y%m%d_%H%M%S)"
  run_dir="agents/runs/lunch_hot_${stamp}"
  mkdir -p "${run_dir}"
  echo "$(date '+%F %T') starting run=${run_dir} seed=${seed}" | tee -a "${LOG}"

  env \
    RUN_DIR="${run_dir}" \
    RUN_MINUTES=360 \
    TOTAL_TIMESTEPS=8000000 \
    CHUNK_TIMESTEPS=32000 \
    CPU_THREADS=10 \
    TRAIN_DEVICE=cpu \
    NUM_ENVS=2 \
    NUM_ENVS_STAGE1=2 \
    NUM_ENVS_STAGE2=2 \
    NUM_ENVS_STAGE3=2 \
    MAX_CPU_TEMP_C=90 \
    RESUME_CPU_TEMP_C=84 \
    TEMP_POLL_SEC=15 \
    STAGES_CSV='core_v2/tests/TestScene_RL.tscn,core_v2/tests/TestScene_RL_2.tscn,core_v2/tests/TestScene_RL_3.tscn,core_v2/tests/TestScene_RL_3_Door.tscn' \
    START_STAGE_IDX=1 \
    MODEL_IN="${seed}" \
    PROMOTE_MIN_DELTA=60 \
    PROMOTE_MIN_SUCCESS_PCT=0.0 \
    N_STEPS=2048 \
    BATCH_SIZE=2048 \
    N_EPOCHS=3 \
    NET_ARCH='192,192' \
    CHECKPOINT_EVERY=16000 \
    EVAL_EPISODES=6 \
    EVAL_MAX_STEPS=2200 \
    ANNA_RL_MAX_STEPS=2200 \
    ANNA_RL_DISABLE_QODOT=1 \
    ANNA_RL_PHYSICS_FPS=2000 \
    ANNA_RL_TARGET_FPS=2000 \
    ANNA_RL_PHYSICS_FPS_CAP=2000 \
    ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME=64 \
    ANNA_RL_POLL_SLEEP_USEC=0 \
    ANNA_RL_DISABLE_CPU_SLEEP=1 \
    ANNA_GODOT_PREFER_SERVER=1 \
    ANNA_GODOT_SERVER_FALLBACK=0 \
    ANNA_GODOT_DISABLE_RENDER_LOOP=1 \
    ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG=1 \
    GODOT_BIN=godot3-server \
    ./agents/run_lunch_adaptive_256k.sh > "${run_dir}/launcher.log" 2>&1 || true

  echo "$(date '+%F %T') run ended=${run_dir}; restart in 5s" | tee -a "${LOG}"
  sleep 5
done
