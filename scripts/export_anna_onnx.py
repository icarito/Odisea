#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import torch
from stable_baselines3 import PPO


class OnnxablePolicy(torch.nn.Module):
    def __init__(self, extractor, action_net):
        super().__init__()
        self.extractor = extractor
        self.action_net = action_net

    def forward(self, observation):
        action_hidden, _value_hidden = self.extractor(observation)
        return self.action_net(action_hidden)


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Export PPO policy to ONNX for ANNA native inference.")
    p.add_argument("--model", default="core_v2/trained_models/final_rl4_13d.zip", help="Input PPO .zip model")
    p.add_argument("--output", default="", help="Output .onnx path (default: same stem as model)")
    p.add_argument("--opset", type=int, default=11)
    return p.parse_args()


def _default_output(model_path: Path) -> Path:
    return model_path.with_suffix(".onnx")


def export_ppo_onnx(model_path: Path, onnx_path: Path, opset: int) -> None:
    print(f"[export_onnx] loading model: {model_path}")
    model = PPO.load(str(model_path), device="cpu")
    obs_shape = tuple(model.observation_space.shape or ())
    if len(obs_shape) != 1:
        raise RuntimeError(f"[export_onnx] unsupported observation shape: {obs_shape}")
    obs_dim = int(obs_shape[0])
    if obs_dim <= 0:
        raise RuntimeError(f"[export_onnx] invalid observation dimension: {obs_dim}")

    onnxable_model = OnnxablePolicy(
        model.policy.mlp_extractor,
        model.policy.action_net,
    )
    dummy_obs = torch.zeros((1, obs_dim), dtype=torch.float32)

    onnx_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[export_onnx] exporting to: {onnx_path} (obs_dim={obs_dim}, opset={opset})")

    base_kwargs = dict(
        model=onnxable_model,
        args=dummy_obs,
        f=str(onnx_path),
        export_params=True,
        opset_version=int(opset),
        do_constant_folding=True,
        input_names=["obs"],
        output_names=["output"],
        dynamic_axes={
            "obs": {0: "batch_size"},
            "output": {0: "batch_size"},
        },
    )

    try:
        # Prefer a single .onnx file (no external .onnx.data sidecar).
        torch.onnx.export(external_data=False, **base_kwargs)
    except TypeError:
        torch.onnx.export(**base_kwargs)

    size_mb = onnx_path.stat().st_size / (1024.0 * 1024.0)
    print(f"[export_onnx] done: {onnx_path} ({size_mb:.3f} MB)")


def main() -> int:
    args = _parse_args()
    model_path = Path(args.model).resolve()
    if not model_path.exists():
        raise FileNotFoundError(f"model not found: {model_path}")
    onnx_path = Path(args.output).resolve() if str(args.output).strip() else _default_output(model_path)
    export_ppo_onnx(model_path=model_path, onnx_path=onnx_path, opset=int(args.opset))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
