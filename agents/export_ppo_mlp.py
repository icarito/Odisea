#!/usr/bin/env python3
"""Export a Stable-Baselines3 PPO MLP policy to a lightweight JSON + golden fixture.

The Godot export must not depend on torch/SB3. This tool converts a PPO checkpoint
(policy only; MLP with tanh activations) into:

  - core_v2/agents/<name>_weights.json
      Layers, hidden widths, activation and float weights (policy network only).
  - core_v2/tests/fixtures/<name>_golden.json
      Deterministic inputs + expected logits computed in float64 (double), i.e. the
      same arithmetic GDScript will run (GDScript floats are 64-bit).

Usage:
  python agents/export_ppo_mlp.py --model agents/models/anna_ppo_noorbit_lvl2_32k_fps120_v1.zip \
      --name anna_ppo_noorbit_v1

The script uses the project .venv (torch + stable_baselines3). It is dev tooling
only: nothing it writes is imported by the Godot export.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import torch
from stable_baselines3 import PPO


def _extract_policy_net(state_dict: dict) -> dict:
    """Gather the policy MLP layers (policy_net) + action head into plain dicts."""
    # policy_net: Sequential(Linear, Tanh, Linear, Tanh)
    layers = []
    for idx in range(0, 4, 2):
        w = state_dict[f"mlp_extractor.policy_net.{idx}.weight"].cpu().numpy()
        b = state_dict[f"mlp_extractor.policy_net.{idx}.bias"].cpu().numpy()
        layers.append({"in": int(w.shape[1]), "out": int(w.shape[0]), "W": w, "b": b})
    a_w = state_dict["action_net.weight"].cpu().numpy()
    a_b = state_dict["action_net.bias"].cpu().numpy()
    return {"hidden": layers, "head": {"in": int(a_w.shape[1]), "out": int(a_w.shape[0]), "W": a_w, "b": a_b}}


def _forward_double(net: dict, x: np.ndarray) -> np.ndarray:
    """Manual forward in float64, matching the MLP + tanh + linear head used by SB3."""
    x = np.asarray(x, dtype=np.float64).reshape(-1)
    h = x
    for layer in net["hidden"]:
        h = np.tanh(layer["W"] @ h + layer["b"])
    logits = net["head"]["W"] @ h + net["head"]["b"]
    return logits


def _round7(x):
    if isinstance(x, (list, tuple)):
        return [_round7(v) for v in x]
    return round(float(x), 7)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--name", required=True, help="Output basename, e.g. anna_ppo_noorbit_v1")
    ap.add_argument("--golden-inputs", type=int, default=5)
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    model_path = Path(args.model)
    if not model_path.is_absolute():
        model_path = repo / model_path

    model = PPO.load(str(model_path), device="cpu")
    obs_space = model.observation_space
    act_space = model.action_space
    assert getattr(model.policy.features_extractor.__class__, "__name__", "") in ("FlattenExtractor",)
    if not hasattr(obs_space, "shape"):
        raise SystemExit("Only Box observation spaces are supported")
    if not hasattr(act_space, "n"):
        raise SystemExit("Only Discrete action spaces are supported")

    net = _extract_policy_net(model.policy.state_dict())
    n_layers = len(net["hidden"])
    hidden = [int(net["hidden"][i]["out"]) for i in range(n_layers)]

    weights = {
        "model": args.name,
        "source": str(model_path),
        "obs_dim": int(obs_space.shape[0]),
        "num_actions": int(act_space.n),
        "activation": "tanh",
        "hidden": hidden,
        "layers": [
            {
                "in": int(net["hidden"][i]["in"]),
                "out": int(net["hidden"][i]["out"]),
                "W": _round7(net["hidden"][i]["W"].tolist()),
                "b": _round7(net["hidden"][i]["b"].tolist()),
            }
            for i in range(n_layers)
        ],
        "head": {
            "in": int(net["head"]["in"]),
            "out": int(net["head"]["out"]),
            "W": _round7(net["head"]["W"].tolist()),
            "b": _round7(net["head"]["b"].tolist()),
        },
    }

    # Golden fixtures: fixed deterministic inputs in [-1,1], forward in float64.
    dim = int(obs_space.shape[0])
    rng = np.random.RandomState(42)
    inputs = []
    inputs.append(np.zeros(dim, dtype=np.float64))
    inputs.append(np.full(dim, 0.5, dtype=np.float64))
    inputs.append(np.linspace(-1.0, 1.0, dim))
    for _ in range(max(0, args.golden_inputs - 3)):
        inputs.append(np.clip(rng.randn(dim), -1.0, 1.0))
    golden = {
        "model": args.name,
        "obs_dim": dim,
        "num_actions": int(act_space.n),
        "inputs": [list(np.round(v, 6)) for v in inputs],
        "logits": [_round7(_forward_double(net, v).tolist()) for v in inputs],
    }

    out_weights = repo / "core_v2" / "agents" / f"{args.name}_weights.json"
    out_golden = repo / "core_v2" / "tests" / "fixtures" / f"{args.name}_golden.json"
    out_weights.parent.mkdir(parents=True, exist_ok=True)
    out_golden.parent.mkdir(parents=True, exist_ok=True)
    out_weights.write_text(json.dumps(weights, indent=1) + "\n", encoding="utf-8")
    out_golden.write_text(json.dumps(golden, indent=1) + "\n", encoding="utf-8")
    print(f"[export_ppo_mlp] wrote {out_weights} ({out_weights.stat().st_size} bytes)")
    print(f"[export_ppo_mlp] wrote {out_golden} ({out_golden.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
