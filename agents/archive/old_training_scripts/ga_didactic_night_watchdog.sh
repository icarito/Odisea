#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PY_BIN="${PY_BIN:-.venv/bin/python}"
GODOT_BIN="${GODOT_BIN:-godot3-server}"
CPU_THREADS="${CPU_THREADS:-3}"
INIT_MODEL="${INIT_MODEL:-core_v2/trained_models/best13d_rl2.zip}"
STAGE_OPEN_RETRIES="${STAGE_OPEN_RETRIES:-4}"
STAGE_OPEN_RETRY_SLEEP="${STAGE_OPEN_RETRY_SLEEP:-1.25}"
RETRY_FAILED="${RETRY_FAILED:-2}"
RUN_TIMEOUT_SEC="${RUN_TIMEOUT_SEC:-7200}"
CHECK_SEC="${CHECK_SEC:-60}"
WATCHDOG_LOG="${WATCHDOG_LOG:-/tmp/anna_ga_rl4_didactic_watchdog.log}"
GA_POPULATION="${GA_POPULATION:-6}"
GA_ELITE="${GA_ELITE:-2}"
GA_MUTATION_RATE="${GA_MUTATION_RATE:-0.40}"
GA_MUTATION_RATE_MAX="${GA_MUTATION_RATE_MAX:-0.72}"
GA_MUTATION_BOOST="${GA_MUTATION_BOOST:-0.14}"
GA_EVAL_EPISODES="${GA_EVAL_EPISODES:-10}"
GA_RL_MAX_STEPS="${GA_RL_MAX_STEPS:-1400}"
GA_EVAL_MAX_STEPS="${GA_EVAL_MAX_STEPS:-1400}"
GA_LIVE_EVAL_MAX_STEPS="${GA_LIVE_EVAL_MAX_STEPS:-600}"
GA_STAGE4_TIMESTEPS="${GA_STAGE4_TIMESTEPS:-22000}"
GA_STAGE5_TIMESTEPS="${GA_STAGE5_TIMESTEPS:-26000}"
GA_SCENE_STAGE1="${GA_SCENE_STAGE1:-core_v2/tests/TestScene_RL.tscn}"
GA_SCENE_STAGE2="${GA_SCENE_STAGE2:-core_v2/tests/TestScene_RL_2.tscn}"
GA_SCENE_STAGE3="${GA_SCENE_STAGE3:-core_v2/tests/TestScene_RL_3.tscn}"
GA_SCENE_STAGE4="${GA_SCENE_STAGE4:-core_v2/tests/TestScene_RL_3_Door.tscn}"
GA_SCENE_STAGE5="${GA_SCENE_STAGE5:-core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn}"
GA_SUCCESS_TARGET="${GA_SUCCESS_TARGET:-0.50}"
GA_DIRECTION_TARGET="${GA_DIRECTION_TARGET:-0.68}"
GA_FAST_SUCCESS_TARGET="${GA_FAST_SUCCESS_TARGET:-0.40}"
GA_TRAIN_PHYSICS_FPS="${GA_TRAIN_PHYSICS_FPS:-4000}"
GA_EVAL_PHYSICS_FPS="${GA_EVAL_PHYSICS_FPS:-60}"
GA_NUM_ENVS="${GA_NUM_ENVS:-1}"
GA_PARALLEL_JOBS="${GA_PARALLEL_JOBS:-1}"
GA_WORKERS="${GA_WORKERS:-2}"

export ANNA_GODOT_BIN="$GODOT_BIN"
export ANNA_GODOT_STDIO="null"
export ANNA_RL_BINARY_PROTOCOL="1"
export ANNA_RL_DIDACTIC="1"
export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-4000}"
export ANNA_RL_TARGET_FPS="${ANNA_RL_TARGET_FPS:-4000}"
export ANNA_RL_PHYSICS_FPS_CAP="${ANNA_RL_PHYSICS_FPS_CAP:-6000}"
export ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME="${ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME:-128}"
export ANNA_RL_POLL_SLEEP_USEC="${ANNA_RL_POLL_SLEEP_USEC:-0}"
export ANNA_RL_DISABLE_CPU_SLEEP="${ANNA_RL_DISABLE_CPU_SLEEP:-1}"
export PYTHONUNBUFFERED="1"

log() {
  local msg="$1"
  printf '[ga-watchdog] %s %s\n' "$(date '+%F %T')" "$msg" | tee -a "$WATCHDOG_LOG"
}

worker_pattern() {
  local label="$1"
  printf 'agents/evolve_anna_ga.py.*--work-dir agents/runs/ga_rl4_didactic_long_%s' "$label"
}

worker_running() {
  local label="$1"
  pgrep -f "$(worker_pattern "$label")" >/dev/null 2>&1
}

start_worker() {
  local label="$1"
  local seed="$2"
  local port_base="$3"
  local log_file="/tmp/anna_ga_rl4_didactic_long_${label}.log"

  log "starting worker=${label} seed=${seed} port_base=${port_base}"
  nohup timeout --signal=INT "$RUN_TIMEOUT_SEC" "$PY_BIN" agents/evolve_anna_ga.py \
    --population "$GA_POPULATION" \
    --generations 999 \
    --elite "$GA_ELITE" \
    --mutation-rate "$GA_MUTATION_RATE" \
    --mutation-rate-max "$GA_MUTATION_RATE_MAX" \
    --mutation-boost "$GA_MUTATION_BOOST" \
    --seed "$seed" \
    --cpu-threads "$CPU_THREADS" \
    --num-envs "$GA_NUM_ENVS" \
    --parallel-jobs "$GA_PARALLEL_JOBS" \
    --eval-episodes "$GA_EVAL_EPISODES" \
    --eval-max-steps "$GA_EVAL_MAX_STEPS" \
    --rl-max-steps "$GA_RL_MAX_STEPS" \
    --live-report-steps 10000 \
    --live-eval-episodes 0 \
    --live-eval-max-steps "$GA_LIVE_EVAL_MAX_STEPS" \
    --scene-stage1 "$GA_SCENE_STAGE1" \
    --scene-stage2 "$GA_SCENE_STAGE2" \
    --scene-stage3 "$GA_SCENE_STAGE3" \
    --scene-stage4 "$GA_SCENE_STAGE4" \
    --scene-stage5 "$GA_SCENE_STAGE5" \
    --train-physics-fps "$GA_TRAIN_PHYSICS_FPS" \
    --eval-physics-fps "$GA_EVAL_PHYSICS_FPS" \
    --rounds 6 \
    --min-rounds 5 \
    --arch-limit 3 \
    --max-model-mb 1.0 \
    --target-model-mb 0.60 \
    --model-size-weight 70 \
    --success-target "$GA_SUCCESS_TARGET" \
    --direction-target "$GA_DIRECTION_TARGET" \
    --fast-success-target "$GA_FAST_SUCCESS_TARGET" \
    --timesteps-stage4 "$GA_STAGE4_TIMESTEPS" \
    --timesteps-stage5 "$GA_STAGE5_TIMESTEPS" \
    --stage-unlock-target 0.50 \
    --stage-growth 0.20 \
    --max-stage-scale 1.9 \
    --init-model "$INIT_MODEL" \
    --port-base "$port_base" \
    --work-dir "agents/runs/ga_rl4_didactic_long_${label}" \
    --output-prefix "agents/models/anna_ga_rl4_didactic_long_${label}" \
    --python-bin "$PY_BIN" \
    --timeout-sec 1800 \
    --retry-failed "$RETRY_FAILED" \
    --stage-open-retries "$STAGE_OPEN_RETRIES" \
    --stage-open-retry-sleep "$STAGE_OPEN_RETRY_SLEEP" \
    --top-k-log 6 \
    --verbose 1 \
    > "$log_file" 2>&1 &

  log "worker=${label} started pid=$!"
}

latest_marker() {
  local label="$1"
  local log_file="/tmp/anna_ga_rl4_didactic_long_${label}.log"
  if [[ ! -f "$log_file" ]]; then
    printf 'log_missing'
    return
  fi
  local marker
  marker="$(rg -n '\[auto_train_anna\]\[live\]|round=[0-9]+ score=|\[ga\] gen=' "$log_file" | tail -n 1 || true)"
  if [[ -z "$marker" ]]; then
    marker="$(tail -n 1 "$log_file" 2>/dev/null || true)"
  fi
  printf '%s' "${marker:-no_marker}"
}

log "boot root=$ROOT_DIR py=$PY_BIN godot=$GODOT_BIN timeout=${RUN_TIMEOUT_SEC}s check=${CHECK_SEC}s"
log "init_model=$INIT_MODEL cpu_threads=$CPU_THREADS retries(stage_open=$STAGE_OPEN_RETRIES candidate=$RETRY_FAILED)"
log "creative_profile population=$GA_POPULATION elite=$GA_ELITE mut=[$GA_MUTATION_RATE,$GA_MUTATION_RATE_MAX] boost=$GA_MUTATION_BOOST eval_ep=$GA_EVAL_EPISODES rl_steps=$GA_RL_MAX_STEPS eval_steps=$GA_EVAL_MAX_STEPS stage45=[$GA_STAGE4_TIMESTEPS,$GA_STAGE5_TIMESTEPS] scenes=[$GA_SCENE_STAGE1,$GA_SCENE_STAGE2,$GA_SCENE_STAGE3,$GA_SCENE_STAGE4,$GA_SCENE_STAGE5] physics(train=$GA_TRAIN_PHYSICS_FPS eval=$GA_EVAL_PHYSICS_FPS) envs=$GA_NUM_ENVS jobs=$GA_PARALLEL_JOBS workers=$GA_WORKERS cpu_threads=$CPU_THREADS"

while true; do
  if worker_running "a"; then
    pid_a="$(pgrep -f "$(worker_pattern "a")" | head -n1 || true)"
    log "worker=a healthy pid=${pid_a:-unknown} marker='$(latest_marker "a")'"
  else
    start_worker "a" "9001" "47000"
  fi

  if [[ "$GA_WORKERS" -ge 2 ]]; then
    if worker_running "b"; then
      pid_b="$(pgrep -f "$(worker_pattern "b")" | head -n1 || true)"
      log "worker=b healthy pid=${pid_b:-unknown} marker='$(latest_marker "b")'"
    else
      start_worker "b" "13337" "54000"
    fi
  fi

  sleep "$CHECK_SEC"
done
