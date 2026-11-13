#!/usr/bin/env python3
"""Evaluate a Stable-Baselines3 PPO policy (or a random/scripted baseline) on the ANNA RL bridge.

Current bridge contract (see core_v2/anna/AnnaInterface.gd):
  observation Box(13,) in [-1, 1]; action Discrete(8).

It launches one headless Godot per run over the ANNA TCP bridge and reports, per episode,
total reward, steps and the terminal reason (`success`, `timeout`, `wall_stuck`, `fall`, ...),
aggregated as mean reward / success rate / collision rate.

Dev tooling only (needs stable-baselines3 + torch). Compare a trained checkpoint against the
random baseline to get a before/after metric:

  python agents/eval_anna.py --model agents/models/anna_ppo_noorbit_v2_137640.zip --episodes 40
  python agents/eval_anna.py --model random --episodes 40
"""
from __future__ import annotations

import argparse
import os
import sys
from collections import Counter
from pathlib import Path

import numpy as np

COLLISION_REASONS = {"collision_front", "collision_slide", "wall_stuck", "killzone", "fall"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="random", help="SB3 .zip path or 'random'.")
    ap.add_argument("--episodes", type=int, default=20)
    ap.add_argument("--scene", default="core_v2/tests/TestScene_RL.tscn")
    ap.add_argument("--port", type=int, default=15120)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--max-steps", type=int, default=1500)
    ap.add_argument("--no-shim", action="store_true",
                    help="Do not adapt a stale (non 13/8) model to the current bridge.")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(repo / "core_v2" / "anna" / "client"))
    from anna_gym import AnnaGymEnv  # type: ignore

    policy = None
    obs_dim, n_act, shim = 13, 8, False
    if args.model != "random":
        from stable_baselines3 import PPO
        policy = PPO.load(args.model, device="cpu")
        obs_dim = int(np.prod(policy.observation_space.shape))
        n_act = int(policy.action_space.n)
        if not args.no_shim and (obs_dim != 13 or n_act != 8):
            shim = True  # take the first obs_dim components; identity-map actions
        print(f"[eval] model={args.model} obs={obs_dim} act={n_act} "
              f"timesteps={policy.num_timesteps} shim={shim}")

    os.environ.setdefault("ANNA_RL_MAX_STEPS", str(args.max_steps))
    env = AnnaGymEnv(scene_path=args.scene, port=args.port, launch_godot=True, headless=True)
    rng = np.random.default_rng(args.seed)
    rewards, steps, reasons = [], [], []
    try:
        for _ in range(args.episodes):
            obs, _ = env.reset()
            obs = np.asarray(obs, dtype=np.float32)
            total, n, reason = 0.0, 0, "running"
            while True:
                if policy is None:
                    action = int(rng.integers(0, 8))
                else:
                    o = obs[:obs_dim] if shim else obs
                    action = int(policy.predict(o, deterministic=True)[0])
                obs, r, term, trunc, info = env.step(action)
                obs = np.asarray(obs, dtype=np.float32)
                total += float(r)
                n += 1
                if term or trunc:
                    reason = str(info.get("done_reason", "terminated"))
                    break
            rewards.append(total)
            steps.append(n)
            reasons.append(reason)
    finally:
        env.close()

    rewards = np.array(rewards)
    counts = Counter(reasons)
    n = len(rewards)
    success = counts.get("success", 0)
    collisions = sum(v for k, v in counts.items() if k in COLLISION_REASONS)
    print(f"MODEL={args.model} shim={shim} episodes={n}")
    print(f"  reward mean={rewards.mean():+.3f} median={np.median(rewards):+.3f} "
          f"min={rewards.min():+.3f} max={rewards.max():+.3f} std={rewards.std():.3f}")
    print(f"  steps  mean={np.mean(steps):.1f}")
    print(f"  success={success}/{n} ({100.0*success/n:.0f}%)  "
          f"collisions={collisions}/{n} ({100.0*collisions/n:.0f}%)")
    print(f"  reasons={dict(counts)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
