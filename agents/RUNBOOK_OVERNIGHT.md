# Overnight RL Runbook (Odisea / ANNA)

Date baseline: 2026-02-26

## Goal

Run a stable overnight training session with high SPS on `godot3-server`, and keep artifacts grouped per run.

## Key throughput rule

Do not pass `--max-fps 0` to `godot3-server`.

Reason: in local probes this dropped throughput from ~2000 SPS to ~250 SPS on `TestScene_RL`.

## Recommended launch

```bash
./agents/run_overnight_best.sh
```

The launcher does:

1. Creates a run folder:
   - `agents/runs/overnight/YYYYMMDD_HHMMSS/`
2. Saves metadata:
   - `run_manifest.env`
   - `git_head.txt`
   - `git_status.txt`
3. Runs a pre-flight FPS probe (default min 1500 SPS on `TestScene_RL`).
4. Starts `./agents/run_train_best_cuda.sh` with robust defaults.
5. Saves logs in:
   - `agents/runs/overnight/YYYYMMDD_HHMMSS/logs/`

`agents/runs/overnight/latest` points to the most recent run directory.

## Important defaults

- `GODOT_BIN=godot3-server`
- `ANNA_GODOT_PREFER_SERVER=1`
- `ANNA_GODOT_SERVER_FALLBACK=0`
- `ANNA_GODOT_DISABLE_RENDER_LOOP=1`
- `ANNA_GODOT_SERVER_VIDEO_DRIVER=` (vacío: no forzar `--video-driver` en `godot3-server`)
- `ANNA_GODOT_QUIET=1`
- `ANNA_RL_DISABLE_CPU_SLEEP=1`
- `ANNA_RL_PHYSICS_FPS=0` (AnnaBridge uncapped preset)
- `ANNA_RL_POLL_SLEEP_USEC=0`
- `ANNA_RL_DISABLE_QODOT=1`
- single-process defaults for overnight script:
  - `NUM_ENVS=1`
  - `NUM_ENVS_STAGE3=1`
  - `CPU_THREADS=8`

## Common overrides

More envs:

```bash
NUM_ENVS=4 NUM_ENVS_STAGE3=2 ./agents/run_overnight_best.sh
```

Skip FPS probe:

```bash
SKIP_FPS_PROBE=1 ./agents/run_overnight_best.sh
```

Custom FPS gate:

```bash
FPS_MIN=1700 FPS_STEPS=3000 ./agents/run_overnight_best.sh
```

Custom output model:

```bash
MODEL_OUT=agents/models/anna_ppo_overnight_custom.zip ./agents/run_overnight_best.sh
```

## Manual probe only

```bash
PYTHONPATH=. python3 agents/probe_rl_fps.py \
  --scene core_v2/tests/TestScene_RL.tscn \
  --steps 2000 \
  --min-sps 1500
```

## Fast sanity checks after launch

Tail probe/training logs:

```bash
tail -n 80 agents/runs/overnight/latest/logs/fps_probe.log
tail -n 120 agents/runs/overnight/latest/logs/train.log
```

Show selected model:

```bash
cat agents/runs/overnight/latest/model_out.txt
cat agents/runs/overnight/latest/last_model.txt
```
