#!/usr/bin/env python3
"""Surgical action-bias edit of a SB3 PPO policy (no training).

Takes agents/models/anna_candidate.zip (obs13/act8) and nudges the action head:
  - boost Forward/SprintForward (prior: keep moving toward target)
  - suppress idle and jump-strafe actions (orbit / drift sources)
Features (128x128 trunk) stay untouched: the learned observation encoding is
preserved; only the output prior changes.

Writes agents/models/anna_candidate_biasfix.zip (SB3-compatible).
"""
from __future__ import annotations

import argparse
from pathlib import Path

import torch
from stable_baselines3 import PPO

BIAS_DELTA = {
    0: -0.30,  # idle
    1: +0.80,  # forward
    2: +0.40,  # sprint forward
    3: -0.10,  # jump forward
    4: 0.0,   # strafe left
    5: 0.0,   # strafe right
    6: -0.60,  # jump strafe left
    7: -0.60,  # jump strafe right
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="agents/models/anna_candidate.zip")
    ap.add_argument("--out", default="agents/models/anna_candidate_biasfix.zip")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    model_path = Path(args.model)
    if not model_path.is_absolute():
        model_path = repo / model_path

    model = PPO.load(str(model_path), device="cpu")
    n_actions = int(model.action_space.n)
    with torch.no_grad():
        bias = model.policy.action_net.bias
        print("[biasfix] before:", [round(float(b), 4) for b in bias])
        for idx, delta in BIAS_DELTA.items():
            if idx < n_actions and delta != 0.0:
                bias[idx] += float(delta)
        print("[biasfix] after :", [round(float(b), 4) for b in bias])

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = repo / out_path
    model.save(str(out_path))
    print(f"[biasfix] wrote {out_path} ({out_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
