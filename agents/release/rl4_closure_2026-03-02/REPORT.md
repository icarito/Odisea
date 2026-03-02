# RL4 Closure Report (2026-03-02)

## Selection Rule
- 1) Highest `stage5_gate_best_success`
- 2) Highest number of stage5 gate passes
- 3) Highest `best_score`

## Selected Top 3
- Top 1: `fae3669a36f5` | stage5_best=1.0 | stage5_passes=1/1 | best_score=5.3212
  - best: `agents/release/rl4_closure_2026-03-02/models/top1_fae3669a36f5_best.zip` (482789 bytes)
  - base_r1: `agents/release/rl4_closure_2026-03-02/models/top1_fae3669a36f5_base_r1.zip` (482789 bytes)
- Top 2: `93d772d1eff0` | stage5_best=0.5 | stage5_passes=1/1 | best_score=5.3568
  - best: `agents/release/rl4_closure_2026-03-02/models/top2_93d772d1eff0_best.zip` (482789 bytes)
  - base_r1: `agents/release/rl4_closure_2026-03-02/models/top2_93d772d1eff0_base_r1.zip` (482789 bytes)
- Top 3: `e07c49641388` | stage5_best=0.0 | stage5_passes=0/2 | best_score=5.3757
  - best: `agents/release/rl4_closure_2026-03-02/models/top3_e07c49641388_best.zip` (482657 bytes)
  - base_r1: `agents/release/rl4_closure_2026-03-02/models/top3_e07c49641388_base_r1.zip` (482657 bytes)

## Shared Seed Base
- `agents/release/rl4_closure_2026-03-02/models/shared_seed_best13d_rl2.zip` (484907 bytes)

## Champion Watch Command
```bash
.venv/bin/python agents/eval_anna.py --model agents/release/rl4_closure_2026-03-02/models/top1_fae3669a36f5_best.zip --scene core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn --watch --render --port 62000
```

## Notes
- `base_r1` is the first-round checkpoint for the same GA lineage (model base for that candidate).
- Full metadata and traceability in `manifest.json`.
