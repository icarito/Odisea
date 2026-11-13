#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PY_BIN="${PY_BIN:-.venv/bin/python}"
GODOT_BIN="${GODOT_BIN:-godot3-server}"
CPU_THREADS="${CPU_THREADS:-4}"
INIT_MODEL="${INIT_MODEL:-core_v2/trained_models/v3_deep_rl2.zip}"
STAGE_OPEN_RETRIES="${STAGE_OPEN_RETRIES:-4}"
STAGE_OPEN_RETRY_SLEEP="${STAGE_OPEN_RETRY_SLEEP:-1.25}"
RETRY_FAILED="${RETRY_FAILED:-2}"
START_SUPERVISOR="${START_SUPERVISOR:-1}"

echo "[didactic-ga] root=$ROOT_DIR"
echo "[didactic-ga] python=$PY_BIN godot=$GODOT_BIN cpu_threads=$CPU_THREADS init_model=$INIT_MODEL"
echo "[didactic-ga] retries stage_open=$STAGE_OPEN_RETRIES retry_sleep=${STAGE_OPEN_RETRY_SLEEP}s candidate_retry=$RETRY_FAILED"

export ANNA_GODOT_BIN="$GODOT_BIN"
export ANNA_GODOT_STDIO="null"
export ANNA_RL_BINARY_PROTOCOL="1"
export ANNA_RL_DIDACTIC="1"
export PYTHONUNBUFFERED="1"

nohup timeout --signal=INT 7200 "$PY_BIN" agents/evolve_anna_ga.py \
  --population 6 \
  --generations 999 \
  --elite 2 \
  --mutation-rate 0.34 \
  --mutation-rate-max 0.62 \
  --mutation-boost 0.10 \
  --seed 9001 \
  --cpu-threads "$CPU_THREADS" \
  --num-envs 1 \
  --parallel-jobs 1 \
  --eval-episodes 10 \
  --eval-max-steps 1200 \
  --rl-max-steps 1200 \
  --live-report-steps 10000 \
  --live-eval-episodes 0 \
  --live-eval-max-steps 300 \
  --train-physics-fps 0 \
  --eval-physics-fps 60 \
  --rounds 6 \
  --min-rounds 5 \
  --arch-limit 3 \
  --max-model-mb 1.0 \
  --target-model-mb 0.60 \
  --model-size-weight 70 \
  --success-target 0.42 \
  --direction-target 0.66 \
  --fast-success-target 0.40 \
  --timesteps-stage4 18000 \
  --timesteps-stage5 16000 \
  --stage-unlock-target 0.50 \
  --stage-growth 0.20 \
  --max-stage-scale 1.9 \
  --init-model "$INIT_MODEL" \
  --port-base 47000 \
  --work-dir agents/runs/ga_rl4_didactic_long_a \
  --output-prefix agents/models/anna_ga_rl4_didactic_long_a \
  --python-bin "$PY_BIN" \
  --timeout-sec 1800 \
  --retry-failed "$RETRY_FAILED" \
  --stage-open-retries "$STAGE_OPEN_RETRIES" \
  --stage-open-retry-sleep "$STAGE_OPEN_RETRY_SLEEP" \
  --top-k-log 6 \
  --verbose 1 \
  > /tmp/anna_ga_rl4_didactic_long_a.log 2>&1 &

PID_A=$!

nohup timeout --signal=INT 7200 "$PY_BIN" agents/evolve_anna_ga.py \
  --population 6 \
  --generations 999 \
  --elite 2 \
  --mutation-rate 0.34 \
  --mutation-rate-max 0.62 \
  --mutation-boost 0.10 \
  --seed 13337 \
  --cpu-threads "$CPU_THREADS" \
  --num-envs 1 \
  --parallel-jobs 1 \
  --eval-episodes 10 \
  --eval-max-steps 1200 \
  --rl-max-steps 1200 \
  --live-report-steps 10000 \
  --live-eval-episodes 0 \
  --live-eval-max-steps 300 \
  --train-physics-fps 0 \
  --eval-physics-fps 60 \
  --rounds 6 \
  --min-rounds 5 \
  --arch-limit 3 \
  --max-model-mb 1.0 \
  --target-model-mb 0.60 \
  --model-size-weight 70 \
  --success-target 0.42 \
  --direction-target 0.66 \
  --fast-success-target 0.40 \
  --timesteps-stage4 18000 \
  --timesteps-stage5 16000 \
  --stage-unlock-target 0.50 \
  --stage-growth 0.20 \
  --max-stage-scale 1.9 \
  --init-model "$INIT_MODEL" \
  --port-base 54000 \
  --work-dir agents/runs/ga_rl4_didactic_long_b \
  --output-prefix agents/models/anna_ga_rl4_didactic_long_b \
  --python-bin "$PY_BIN" \
  --timeout-sec 1800 \
  --retry-failed "$RETRY_FAILED" \
  --stage-open-retries "$STAGE_OPEN_RETRIES" \
  --stage-open-retry-sleep "$STAGE_OPEN_RETRY_SLEEP" \
  --top-k-log 6 \
  --verbose 1 \
  > /tmp/anna_ga_rl4_didactic_long_b.log 2>&1 &

PID_B=$!

echo "[didactic-ga] started PID_A=$PID_A PID_B=$PID_B"
echo "[didactic-ga] logs: /tmp/anna_ga_rl4_didactic_long_a.log /tmp/anna_ga_rl4_didactic_long_b.log"

if [[ "$START_SUPERVISOR" == "1" ]]; then
  nohup bash agents/supervise_ga_overnight.sh \
    /tmp/anna_ga_rl4_didactic_long_a.log \
    /tmp/anna_ga_rl4_didactic_long_b.log \
    > /tmp/anna_ga_rl4_didactic_supervisor.log 2>&1 &
  echo "[didactic-ga] supervisor pid=$! log=/tmp/anna_ga_rl4_didactic_supervisor.log"
fi
