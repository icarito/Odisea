#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -d ".venv" ]]; then
  echo "[run_train_best_cuda] Missing .venv in ${REPO_ROOT}" >&2
  exit 1
fi

source .venv/bin/activate

export ANNA_RL_PHYSICS_FPS="${ANNA_RL_PHYSICS_FPS:-180}"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"

STAMP="$(date +%Y%m%d_%H%M%S)"
MODEL_OUT="${MODEL_OUT:-agents/models/anna_ppo_cuda_big_${STAMP}.zip}"

python agents/train_anna_cuda_big.py \
  --device auto \
  --cpu-threads "${CPU_THREADS:-16}" \
  --num-envs "${NUM_ENVS:-8}" \
  --scene-stage1 core_v2/tests/TestScene_RL.tscn \
  --scene-stage2 core_v2/tests/TestScene_RL_2.tscn \
  --scene-stage3 core_v2/tests/TestScene_RL_BaseTerrace.tscn \
  --timesteps-stage1 "${STAGE1_STEPS:-150000}" \
  --timesteps-stage2 "${STAGE2_STEPS:-650000}" \
  --timesteps-stage3 "${STAGE3_STEPS:-700000}" \
  --n-steps "${N_STEPS:-4096}" \
  --batch-size "${BATCH_SIZE:-4096}" \
  --n-epochs "${N_EPOCHS:-10}" \
  --learning-rate "${LR:-0.00025}" \
  --entropy-coef "${ENT_COEF:-0.015}" \
  --gamma "${GAMMA:-0.995}" \
  --gae-lambda "${GAE_LAMBDA:-0.98}" \
  --clip-range "${CLIP_RANGE:-0.2}" \
  --checkpoint-every "${CHECKPOINT_EVERY:-50000}" \
  --model-out "${MODEL_OUT}" \
  --verbose "${VERBOSE:-1}" \
  "$@"

echo "[run_train_best_cuda] done model=${MODEL_OUT}"
