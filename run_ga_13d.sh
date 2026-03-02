#!/usr/bin/env bash
# run_ga_13d.sh
# Quickly kicks off genetic search for 13D model parameters.

echo "==========================================="
echo "🧬 Launching ANNA 13D Genetic Algorithm"
echo "==========================================="

mkdir -p agents/runs/ga_13d

# Execute GA evolution for 13D Model limits
# Reduced rounds for faster initial exploration, max CPU utilization.
export ANNA_GODOT_PREFER_SERVER=1
export PYTHONUNBUFFERED=1
export OMP_NUM_THREADS=8
export GODOT_THREADS=2

.venv/bin/python agents/evolve_anna_ga.py \
    --population 12 \
    --generations 8 \
    --elite 2 \
    --mutation-rate 0.4 \
    --cpu-threads 8 \
    --python-bin .venv/bin/python \
    --parallel-jobs 1 \
    --eval-episodes 15 \
    --rl-max-steps 1500 \
    --scene-stage1 "core_v2/tests/TestScene_RL.tscn" \
    --scene-stage2 "core_v2/tests/TestScene_RL_2.tscn" \
    --scene-stage3 "core_v2/tests/TestScene_RL_3_Door.tscn" \
    --rounds 2 \
    --min-rounds 2 \
    --output-prefix "agents/models/anna_ga_13d" \
    --work-dir "agents/runs/ga_13d" 2>&1 | tee /tmp/13d_ga_evolution.log

echo "✅ GA completed. Best parameters written to agents/runs/ga_13d"
