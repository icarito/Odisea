import torch
import stable_baselines3
from stable_baselines3 import PPO
import argparse
import os

class OnnxablePolicy(torch.nn.Module):
    def __init__(self, extractor, action_net, value_net):
        super(OnnxablePolicy, self).__init__()
        self.extractor = extractor
        self.action_net = action_net
        self.value_net = value_net

    def forward(self, observation):
        action_hidden, value_hidden = self.extractor(observation)
        return self.action_net(action_hidden)

def export_ppo_onnx(model_path, onnx_path):
    print(f"Loading model {model_path}...")
    model = PPO.load(model_path, device="cpu")
    onnxable_model = OnnxablePolicy(
        model.policy.mlp_extractor,
        model.policy.action_net, 
        model.policy.value_net
    )

    # Observation space is 13 shape Box. Create dummy inputs.
    dummy_obs = torch.randn(1, 13, dtype=torch.float32)

    print(f"Exporting to {onnx_path}...")
    torch.onnx.export(
        onnxable_model,
        dummy_obs,
        onnx_path,
        export_params=True,    # Store the trained parameter weights inside the model file
        opset_version=9,
        do_constant_folding=True,
        input_names=["obs"],
        output_names=["output"],
        dynamic_axes={'obs' : {0 : 'batch_size'},
                      'output' : {0 : 'batch_size'}}
    )
    print(f"Exported to {onnx_path} successfully!")

if __name__ == "__main__":
    export_ppo_onnx("core_v2/trained_models/final_rl4_13d.zip", "core_v2/trained_models/final_rl4_13d.onnx")
