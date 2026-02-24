#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

run_id="$(date +%Y%m%d_%H%M%S)"
base_prefix="agents/models/anna_auto_1mb_vast_${run_id}"

mkdir -p reports agents/models

run_case() {
  local label="$1"
  local lr="$2"
  local ent="$3"
  local prefix="${base_prefix}_${label}"
  local log="reports/anna_auto_1mb_vast_${run_id}_${label}.log"

  echo "[run_auto_1mb_vast] starting ${label} lr=${lr} ent=${ent}"
  env \
    PYTHONUNBUFFERED=1 \
    GODOT_SILENCE_ROOT_WARNING=1 \
    vblank_mode=0 \
    GODOT_BIN="${GODOT_BIN:-godot3-server}" \
    ANNA_GODOT_PREFER_SERVER="${ANNA_GODOT_PREFER_SERVER:-1}" \
    ANNA_GODOT_SERVER_FALLBACK="${ANNA_GODOT_SERVER_FALLBACK:-0}" \
    ANNA_RL_POLL_SLEEP_USEC="${ANNA_RL_POLL_SLEEP_USEC:-0}" \
    ANNA_RL_MAX_STEPS="${ANNA_RL_MAX_STEPS:-900}" \
    OMP_NUM_THREADS="${OMP_NUM_THREADS:-8}" \
    MKL_NUM_THREADS="${MKL_NUM_THREADS:-8}" \
    OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-8}" \
    NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-8}" \
    "${PYTHON_BIN:-python3}" agents/auto_train_anna.py \
      --scene-stage1 core_v2/tests/TestScene_RL.tscn \
      --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
      --scene-stage3 core_v2/tests/TestScene_RL_3_Door.tscn \
      --timesteps-stage1 8000 \
      --timesteps-stage2 12000 \
      --timesteps-stage3 16000 \
      --stage1-round-steps 8000,4000,2000 \
      --stage2-round-steps 12000,12000,8000 \
      --stage3-round-steps 16000,32000,48000 \
      --rounds 3 \
      --min-rounds 3 \
      --cpu-threads 8 \
      --eval-episodes 20 \
      --eval-max-steps 1500 \
      --output-prefix "${prefix}" \
      --max-model-mb 1.0 \
      --policy-widths 128,160 \
      --policy-depths 2 \
      --arch-limit 2 \
      --ppo-n-steps 1024 \
      --ppo-batch-size 512 \
      --ppo-n-epochs 3 \
      --ppo-device cpu \
      --learning-rate "${lr}" \
      --entropy-coef "${ent}" \
      --rl-physics-fps 0 \
      --rl-max-steps "${ANNA_RL_MAX_STEPS:-900}" \
      --rl-disable-cpu-sleep \
      --success-target 0.20 \
      --direction-target 0.62 \
      --fast-success-target 0.35 \
      --wall-contact-max 0.20 \
      --verbose 1 \
      | tee "${log}"
}

run_case "A" "0.0005" "0.03"
run_case "B" "0.0007" "0.035"

winner_label="$("${PYTHON_BIN:-python3}" - <<PY
import json
from pathlib import Path
base = Path("${base_prefix}")
items = []
for label in ("A", "B"):
    s = Path(f"{base}_{label}_summary.json")
    if not s.exists():
        continue
    data = json.loads(s.read_text(encoding="utf-8"))
    m = data.get("best_metrics", {}) or {}
    items.append((label, float(m.get("success_rate", 0.0)), float(m.get("avg_success_len", 1e9)), float(m.get("direction_score", 0.0)), float(m.get("wall_touch_ratio", 1.0))))
if not items:
    raise SystemExit(1)
items.sort(key=lambda x: (x[1], -x[2], x[3], -x[4]), reverse=True)
print(items[0][0])
PY
)"

winner_prefix="${base_prefix}_${winner_label}"
winner_zip="${winner_prefix}_best.zip"
winner_summary="${winner_prefix}_summary.json"
final_zip="${base_prefix}_winner.zip"
final_summary="${base_prefix}_winner_summary.json"
cp -f "${winner_zip}" "${final_zip}"
cp -f "${winner_summary}" "${final_summary}"

echo "DONE_WINNER_LABEL=${winner_label}"
echo "DONE_WINNER_ZIP=${final_zip}"
echo "DONE_WINNER_SUMMARY=${final_summary}"
echo "DONE_PREFIX=${base_prefix}"
