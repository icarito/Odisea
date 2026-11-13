#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f ".venv311/bin/activate" ]]; then
  source .venv311/bin/activate
elif [[ -f ".venv/bin/activate" ]]; then
  source .venv/bin/activate
fi

STAMP="${STAMP:-$(date +%Y%m%d_%H%M%S)}"
RUN_DIR="${RUN_DIR:-agents/runs/lunch_${STAMP}}"
LOG_DIR="${RUN_DIR}/logs"
MODEL_DIR="${RUN_DIR}/models"
mkdir -p "${LOG_DIR}" "${MODEL_DIR}"

TOTAL_TIMESTEPS="${TOTAL_TIMESTEPS:-256000}"
CHUNK_TIMESTEPS="${CHUNK_TIMESTEPS:-16000}"
RUN_MINUTES="${RUN_MINUTES:-0}"
SCENE_STAGE1="${SCENE_STAGE1:-core_v2/tests/TestScene_RL.tscn}"
SCENE_STAGE2="${SCENE_STAGE2:-core_v2/tests/TestScene_RL_2.tscn}"
SCENE_STAGE3="${SCENE_STAGE3:-core_v2/tests/TestScene_RL_3.tscn}"
STAGES_CSV="${STAGES_CSV:-}"

CPU_THREADS="${CPU_THREADS:-6}"
TRAIN_DEVICE="${TRAIN_DEVICE:-cpu}"
NUM_ENVS="${NUM_ENVS:-1}"
NUM_ENVS_STAGE1="${NUM_ENVS_STAGE1:-${NUM_ENVS}}"
NUM_ENVS_STAGE2="${NUM_ENVS_STAGE2:-${NUM_ENVS}}"
NUM_ENVS_STAGE3="${NUM_ENVS_STAGE3:-${NUM_ENVS}}"
MAX_CPU_TEMP_C="${MAX_CPU_TEMP_C:-84}"
RESUME_CPU_TEMP_C="${RESUME_CPU_TEMP_C:-79}"
TEMP_POLL_SEC="${TEMP_POLL_SEC:-20}"
ALLOW_STAGE3="${ALLOW_STAGE3:-0}"
PROMOTE_MIN_DELTA="${PROMOTE_MIN_DELTA:-150}"
PROMOTE_MIN_SUCCESS_PCT="${PROMOTE_MIN_SUCCESS_PCT:-2.0}"
N_STEPS="${N_STEPS:-2048}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
N_EPOCHS="${N_EPOCHS:-2}"
NET_ARCH="${NET_ARCH:-192,192}"

export OMP_NUM_THREADS="${CPU_THREADS}"
export MKL_NUM_THREADS="${CPU_THREADS}"
export OPENBLAS_NUM_THREADS="${CPU_THREADS}"
export NUMEXPR_NUM_THREADS="${CPU_THREADS}"

# Fast runtime defaults (headless RL throughput). Thermal guard will pause if needed.
export GODOT_BIN="${GODOT_BIN:-godot3-server}"
export ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}"
export ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}"
export ANNA_GODOT_DISABLE_RENDER_LOOP="${ANNA_GODOT_DISABLE_RENDER_LOOP:-1}"
export ANNA_GODOT_SERVER_VIDEO_DRIVER="${ANNA_GODOT_SERVER_VIDEO_DRIVER:-}"
export ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG="${ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG:-1}"
export ANNA_RL_DISABLE_QODOT="${ANNA_RL_DISABLE_QODOT:-1}"
export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-2000}"
export ANNA_RL_TARGET_FPS="${ANNA_RL_TARGET_FPS:-2000}"
export ANNA_RL_PHYSICS_FPS_CAP="${ANNA_RL_PHYSICS_FPS_CAP:-2000}"
export ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME="${ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME:-64}"
export ANNA_RL_DISABLE_CPU_SLEEP="${ANNA_RL_DISABLE_CPU_SLEEP:-1}"
export ANNA_RL_POLL_SLEEP_USEC="${ANNA_RL_POLL_SLEEP_USEC:-0}"
export ANNA_RL_EXIT_ON_DISCONNECT="${ANNA_RL_EXIT_ON_DISCONNECT:-0}"
TRAIN_RETRIES="${TRAIN_RETRIES:-3}"
START_STAGE_IDX="${START_STAGE_IDX:-0}"
CHECKPOINT_EVERY="${CHECKPOINT_EVERY:-16000}"
EVAL_EPISODES="${EVAL_EPISODES:-4}"
EVAL_MAX_STEPS="${EVAL_MAX_STEPS:-1200}"

if [[ -n "${STAGES_CSV}" ]]; then
  IFS=',' read -r -a STAGES <<< "${STAGES_CSV}"
elif [[ "${ALLOW_STAGE3}" == "1" ]]; then
  STAGES=("${SCENE_STAGE1}" "${SCENE_STAGE2}" "${SCENE_STAGE3}")
else
  STAGES=("${SCENE_STAGE1}" "${SCENE_STAGE2}")
fi
stage_idx="${START_STAGE_IDX}"
if [[ "${stage_idx}" -lt 0 ]]; then
  stage_idx=0
fi
max_stage_idx=$(( ${#STAGES[@]} - 1 ))
if [[ "${stage_idx}" -gt "${max_stage_idx}" ]]; then
  stage_idx="${max_stage_idx}"
fi
spent=0
chunk_id=0
model_in=""
model_in="${MODEL_IN:-}"
best_stage_score="-999999999"

deadline_epoch=0
if [[ "${RUN_MINUTES}" -gt 0 ]]; then
  deadline_epoch=$(( $(date +%s) + (RUN_MINUTES * 60) ))
fi

echo "[lunch256] run_dir=${RUN_DIR}" | tee "${RUN_DIR}/manifest.log"
echo "[lunch256] total=${TOTAL_TIMESTEPS} chunk=${CHUNK_TIMESTEPS} cpu_threads=${CPU_THREADS} device=${TRAIN_DEVICE}" | tee -a "${RUN_DIR}/manifest.log"
echo "[lunch256] envs: num_envs=${NUM_ENVS} stage1=${NUM_ENVS_STAGE1} stage2=${NUM_ENVS_STAGE2} stage3=${NUM_ENVS_STAGE3}" | tee -a "${RUN_DIR}/manifest.log"
echo "[lunch256] curriculum: stages=${STAGES[*]} promote_min_delta=${PROMOTE_MIN_DELTA} promote_min_success=${PROMOTE_MIN_SUCCESS_PCT}" | tee -a "${RUN_DIR}/manifest.log"
echo "[lunch256] stage_start_idx=${stage_idx} stage_start=${STAGES[${stage_idx}]}" | tee -a "${RUN_DIR}/manifest.log"
echo "[lunch256] train cfg: n_steps=${N_STEPS} batch=${BATCH_SIZE} epochs=${N_EPOCHS} net=${NET_ARCH}" | tee -a "${RUN_DIR}/manifest.log"
if [[ -n "${model_in}" ]]; then
  echo "[lunch256] resume seed model=${model_in}" | tee -a "${RUN_DIR}/manifest.log"
fi
if [[ "${RUN_MINUTES}" -gt 0 ]]; then
  echo "[lunch256] wall_clock_limit=${RUN_MINUTES}m deadline_epoch=${deadline_epoch}" | tee -a "${RUN_DIR}/manifest.log"
fi
echo "[lunch256] speed cfg: physics=${ANNA_RL_PHYSICS_FPS} target=${ANNA_RL_TARGET_FPS} cap=${ANNA_RL_PHYSICS_FPS_CAP} poll_usec=${ANNA_RL_POLL_SLEEP_USEC} cpu_sleep=${ANNA_RL_DISABLE_CPU_SLEEP}" | tee -a "${RUN_DIR}/manifest.log"

get_cpu_temp_c() {
  if ! command -v sensors >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  python3 - <<'PY'
import re, subprocess
try:
    out = subprocess.check_output(["sensors"], text=True, stderr=subprocess.STDOUT)
except Exception:
    print("")
    raise SystemExit(0)
vals = []
for line in out.splitlines():
    head = line.split("(", 1)[0]
    m = re.search(r'([+-]?[0-9]+(?:\.[0-9]+)?)°C', head)
    if not m:
        continue
    v = float(m.group(1))
    if 0.0 < v < 130.0:
        vals.append(v)
print(max(vals) if vals else "")
PY
}

thermal_guard() {
  while true; do
    temp="$(get_cpu_temp_c)"
    if [[ -z "${temp}" ]]; then
      return 0
    fi
    over="$(python3 - <<PY
t=float("${temp}")
print(1 if t >= float("${MAX_CPU_TEMP_C}") else 0)
PY
)"
    if [[ "${over}" != "1" ]]; then
      return 0
    fi
    echo "[lunch256] thermal guard: ${temp}C >= ${MAX_CPU_TEMP_C}C; waiting..." | tee -a "${RUN_DIR}/manifest.log"
    sleep "${TEMP_POLL_SEC}"
    temp2="$(get_cpu_temp_c)"
    if [[ -n "${temp2}" ]]; then
      resume="$(python3 - <<PY
t=float("${temp2}")
print(1 if t <= float("${RESUME_CPU_TEMP_C}") else 0)
PY
)"
      if [[ "${resume}" == "1" ]]; then
        echo "[lunch256] thermal guard: resumed at ${temp2}C" | tee -a "${RUN_DIR}/manifest.log"
        return 0
      fi
    fi
  done
}

score_from_eval_log() {
  local eval_log="$1"
  python3 - <<PY
import re, pathlib
txt = pathlib.Path("${eval_log}").read_text(encoding="utf-8", errors="ignore")
m = re.search(r"summary episodes=\\d+ avg_reward=([-0-9.]+).*success_rate=([-0-9.]+)%", txt)
if not m:
    print("-999999999")
    raise SystemExit(0)
avg_reward = float(m.group(1))
success = float(m.group(2))
score = (success * 1000.0) + avg_reward
print(score)
PY
}

metrics_from_eval_log() {
  local eval_log="$1"
  python3 - <<PY
import re, pathlib
txt = pathlib.Path("${eval_log}").read_text(encoding="utf-8", errors="ignore")
m = re.search(r"summary episodes=\\d+ avg_reward=([-0-9.]+).*success_rate=([-0-9.]+)%", txt)
if not m:
    print("-999999999 0")
    raise SystemExit(0)
print(f"{float(m.group(1))} {float(m.group(2))}")
PY
}

while [[ "${spent}" -lt "${TOTAL_TIMESTEPS}" ]]; do
  if [[ "${deadline_epoch}" -gt 0 && "$(date +%s)" -ge "${deadline_epoch}" ]]; then
    echo "[lunch256] reached wall_clock_limit; stopping loop." | tee -a "${RUN_DIR}/manifest.log"
    break
  fi
  thermal_guard

  stage="${STAGES[${stage_idx}]}"
  rem=$((TOTAL_TIMESTEPS - spent))
  steps=$(( rem < CHUNK_TIMESTEPS ? rem : CHUNK_TIMESTEPS ))
  chunk_id=$((chunk_id + 1))

  s1=0; s2=0; s3=0
  scene_stage3_chunk="${SCENE_STAGE3}"
  if [[ "${stage_idx}" -eq 0 ]]; then s1="${steps}"; fi
  if [[ "${stage_idx}" -eq 1 ]]; then s2="${steps}"; fi
  if [[ "${stage_idx}" -ge 2 ]]; then
    s3="${steps}"
    scene_stage3_chunk="${stage}"
  fi

  model_out="${MODEL_DIR}/anna_lunch_${STAMP}_c$(printf '%03d' "${chunk_id}").zip"
  train_log="${LOG_DIR}/chunk_$(printf '%03d' "${chunk_id}")_train.log"
  eval_log="${LOG_DIR}/chunk_$(printf '%03d' "${chunk_id}")_eval.log"

  echo "[lunch256] chunk=${chunk_id} stage=${stage} steps=${steps} spent=${spent}/${TOTAL_TIMESTEPS}" | tee -a "${RUN_DIR}/manifest.log"

  cmd=(python -u agents/train_anna_cuda_big.py
    --godot-bin "${GODOT_BIN}"
    --device "${TRAIN_DEVICE}"
    --cpu-threads "${CPU_THREADS}"
    --num-envs "${NUM_ENVS}"
    --num-envs-stage1 "${NUM_ENVS_STAGE1}"
    --num-envs-stage2 "${NUM_ENVS_STAGE2}"
    --num-envs-stage3 "${NUM_ENVS_STAGE3}"
    --timesteps-stage1 "${s1}"
    --timesteps-stage2 "${s2}"
    --timesteps-stage3 "${s3}"
    --scene-stage1 "${SCENE_STAGE1}"
    --scene-stage2 "${SCENE_STAGE2}"
    --scene-stage3 "${scene_stage3_chunk}"
    --n-steps "${N_STEPS}"
    --batch-size "${BATCH_SIZE}"
    --n-epochs "${N_EPOCHS}"
    --net-arch "${NET_ARCH}"
    --learning-rate 0.0004
    --entropy-coef 0.02
    --checkpoint-every "${CHECKPOINT_EVERY}"
    --skip-import-prewarm
    --resume never
    --model-out "${model_out}"
    --verbose 1
  )
  if [[ -n "${model_in}" ]]; then
    cmd+=(--resume-from "${model_in}")
  fi

  ok=0
  for attempt in $(seq 1 "${TRAIN_RETRIES}"); do
    echo "[lunch256] train attempt ${attempt}/${TRAIN_RETRIES} for chunk=${chunk_id}" | tee -a "${RUN_DIR}/manifest.log"
    if "${cmd[@]}" 2>&1 | tee "${train_log}"; then
      ok=1
      break
    fi
    echo "[lunch256] train failed on attempt ${attempt}; cleaning stale godot and retrying..." | tee -a "${RUN_DIR}/manifest.log"
    # Use pkill here; awk regex escaping is fragile across distros/awk variants.
    pkill -TERM -f "godot3-server .*--disable-render-loop --quiet res://core_v2/tests/TestScene_RL" 2>/dev/null || true
    sleep 2
    thermal_guard
  done
  if [[ "${ok}" != "1" ]]; then
    echo "[lunch256] chunk=${chunk_id} failed after ${TRAIN_RETRIES} attempts; aborting run." | tee -a "${RUN_DIR}/manifest.log"
    exit 1
  fi

  python -u agents/eval_anna.py \
    --model "${model_out}" \
    --scene "${stage}" \
    --headless \
    --episodes "${EVAL_EPISODES}" \
    --max-steps "${EVAL_MAX_STEPS}" \
    --port $((5600 + chunk_id)) \
    > "${eval_log}" 2>&1 || true

  new_score="$(score_from_eval_log "${eval_log}")"
  metrics="$(metrics_from_eval_log "${eval_log}")"
  avg_reward="$(echo "${metrics}" | awk '{print $1}')"
  success_rate="$(echo "${metrics}" | awk '{print $2}')"
  improved="$(python3 - <<PY
prev=float("${best_stage_score}")
cur=float("${new_score}")
# Require a meaningful gain to promote curriculum.
print(1 if cur > (prev + float("${PROMOTE_MIN_DELTA}")) else 0)
PY
)"
  can_promote="$(python3 - <<PY
success=float("${success_rate}")
need=float("${PROMOTE_MIN_SUCCESS_PCT}")
print(1 if success >= need else 0)
PY
)"
  echo "[lunch256] chunk=${chunk_id} score=${new_score} avg=${avg_reward} success=${success_rate}% prev=${best_stage_score} improved=${improved} can_promote=${can_promote}" | tee -a "${RUN_DIR}/manifest.log"

  if [[ "${improved}" == "1" ]]; then
    best_stage_score="${new_score}"
    if [[ "${can_promote}" == "1" && "${stage_idx}" -lt "$(( ${#STAGES[@]} - 1 ))" ]]; then
      stage_idx=$((stage_idx + 1))
      best_stage_score="-999999999"
      echo "[lunch256] curriculum promoted -> ${STAGES[${stage_idx}]}" | tee -a "${RUN_DIR}/manifest.log"
    fi
  fi

  model_in="${model_out}"
  spent=$((spent + steps))
done

echo "[lunch256] done spent=${spent} model=${model_in}" | tee -a "${RUN_DIR}/manifest.log"
if [[ -n "${model_in}" ]]; then
  echo "${model_in}" > "${RUN_DIR}/final_model.txt"
fi
