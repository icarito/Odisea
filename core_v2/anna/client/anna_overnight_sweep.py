#!/usr/bin/env python3
"""
ANNA Overnight Training Sweep Runner

This script runs a hyperparameter sweep for ANNA RL training,
testing multiple algorithms (PPO, A2C, DQN) with different configurations and seeds.
"""

import os
import sys
import json
import time
import subprocess
import signal
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
import csv
import numpy as np

# Add this client directory to sys.path for importing anna_gym.
CLIENT_PATH = os.path.dirname(__file__)
sys.path.insert(0, CLIENT_PATH)

# Constants
ARTIFACTS_DIR = Path("artifacts/anna_overnight").resolve()
RUNS_DIR = ARTIFACTS_DIR / "runs"
LOGS_DIR = ARTIFACTS_DIR / "logs"
BEST_DIR = ARTIFACTS_DIR / "best"
LEADERBOARD_FILE = ARTIFACTS_DIR / "leaderboard.csv"
SUMMARY_FILE = ARTIFACTS_DIR / "summary.md"
MANIFEST_FILE = ARTIFACTS_DIR / "run_manifest.json"

# Training scene
DEFAULT_SCENE = "core_v2/tests/TestScene_RL.tscn"

# Algorithm configurations to sweep
SWEEP_CONFIGS = [
    # PPO configurations
    {"algo": "PPO", "config": {"learning_rate": 3e-4, "n_steps": 2048, "batch_size": 64, "n_epochs": 10, "gamma": 0.99, "gae_lambda": 0.95, "clip_range": 0.2}, "seeds": [42, 43, 44], "timesteps": 50000},
    {"algo": "PPO", "config": {"learning_rate": 1e-3, "n_steps": 512, "batch_size": 32, "n_epochs": 5, "gamma": 0.99, "gae_lambda": 0.95, "clip_range": 0.1}, "seeds": [42, 43], "timesteps": 50000},
    {"algo": "PPO", "config": {"learning_rate": 1e-4, "n_steps": 4096, "batch_size": 128, "n_epochs": 20, "gamma": 0.995, "gae_lambda": 0.98, "clip_range": 0.3}, "seeds": [42], "timesteps": 50000},
    
    # A2C configurations
    {"algo": "A2C", "config": {"learning_rate": 7e-4, "n_steps": 5, "gamma": 0.99, "gae_lambda": 0.99}, "seeds": [42, 43], "timesteps": 50000},
    {"algo": "A2C", "config": {"learning_rate": 1e-3, "n_steps": 10, "gamma": 0.995, "gae_lambda": 0.95}, "seeds": [42], "timesteps": 50000},
    
    # DQN configurations
    {"algo": "DQN", "config": {"learning_rate": 1e-3, "buffer_size": 10000, "learning_starts": 1000, "batch_size": 32, "gamma": 0.99, "exploration_fraction": 0.1, "exploration_final_eps": 0.01}, "seeds": [42, 43], "timesteps": 50000},
    {"algo": "DQN", "config": {"learning_rate": 5e-4, "buffer_size": 50000, "learning_starts": 500, "batch_size": 64, "gamma": 0.99, "exploration_fraction": 0.2, "exploration_final_eps": 0.05}, "seeds": [42], "timesteps": 50000},
]


@dataclass
class RunResult:
    """Results from a single training run"""
    run_id: str
    algo: str
    config: Dict[str, Any]
    seed: int
    timesteps: int
    status: str  # "running", "completed", "failed"
    start_time: str
    end_time: Optional[str] = None
    final_reward: Optional[float] = None
    mean_episode_reward_eval: Optional[float] = None
    p25_episode_reward_eval: Optional[float] = None
    std_episode_reward_eval: Optional[float] = None
    episode_rewards_eval: Optional[List[float]] = None
    model_path: Optional[str] = None
    error_message: Optional[str] = None


class AnnaOvernightSweep:
    """Main class for running overnight ANNA training sweeps"""
    
    def __init__(self, scene: str = DEFAULT_SCENE, godot_bin: str = "godot3-server"):
        self.scene = scene
        self.godot_bin = godot_bin
        self.runs: List[RunResult] = []
        self.start_time = datetime.now().isoformat()
        
        # Get MCP version
        mcp_version_path = Path("core_v2/anna/mcp_version.json")
        if mcp_version_path.exists():
            with open(mcp_version_path) as f:
                self.mcp_version = json.load(f)
        else:
            self.mcp_version = {"error": "mcp_version.json not found"}
        
        # Get git commit
        try:
            result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                capture_output=True, text=True, cwd="."
            )
            self.git_commit = result.stdout.strip()
        except Exception:
            self.git_commit = "unknown"
        
        print(f"=== ANNA Overnight Sweep ===")
        print(f"Scene: {scene}")
        print(f"Git commit: {self.git_commit}")
        print(f"MCP version: {self.mcp_version.get('bundle_version', 'unknown')}")
        print(f"Start time: {self.start_time}")
        
        # Create directories
        RUNS_DIR.mkdir(parents=True, exist_ok=True)
        LOGS_DIR.mkdir(parents=True, exist_ok=True)
        BEST_DIR.mkdir(parents=True, exist_ok=True)
    
    def run_single_training(self, config: Dict, seed: int, run_id: str) -> RunResult:
        """Run a single training configuration"""
        algo = config["algo"]
        algo_config = config["config"]
        timesteps = config["timesteps"]
        
        result = RunResult(
            run_id=run_id,
            algo=algo,
            config=algo_config,
            seed=seed,
            timesteps=timesteps,
            status="running",
            start_time=datetime.now().isoformat()
        )
        
        # Model save path
        model_path = RUNS_DIR / run_id / "model"
        run_log_path = LOGS_DIR / f"{run_id}.log"
        
        # Create directories
        (RUNS_DIR / run_id).mkdir(parents=True, exist_ok=True)
        
        print(f"\n--- Starting run {run_id} ---")
        print(f"Algorithm: {algo}")
        print(f"Config: {algo_config}")
        print(f"Seed: {seed}")
        print(f"Timesteps: {timesteps}")
        
        # Build command
        cmd = self._build_training_command(algo, algo_config, seed, timesteps, str(model_path))
        
        # Run training
        start_time = time.time()
        env = os.environ.copy()
        env["ANNA_SCENE"] = self.scene
        env["GODOT_BIN"] = self.godot_bin
        
        try:
            with open(run_log_path, "w") as log_file:
                process = subprocess.Popen(
                    cmd,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    env=env,
                    cwd="."
                )
                
                # Wait for completion (with timeout)
                return_code = process.wait(timeout=3600 * 3)  # 3 hour timeout per run
                
            result.end_time = datetime.now().isoformat()
            
            # Check if model was saved even if process returned non-zero
            model_file = Path(model_path)
            model_saved = (model_file.with_suffix('.zip').exists() or 
                          model_file.exists() or
                          list((RUNS_DIR / run_id).glob("*.zip")))
            
            if model_saved:
                result.status = "completed"
                result.model_path = str(model_path)
                print(f"Run {run_id} completed (model saved)")
                
                # Evaluate the model
                eval_result = self._evaluate_model(algo, str(model_path), seed)
                result.mean_episode_reward_eval = eval_result.get("mean_reward")
                result.p25_episode_reward_eval = eval_result.get("p25_reward")
                result.std_episode_reward_eval = eval_result.get("std_reward")
                result.episode_rewards_eval = eval_result.get("rewards")
                result.final_reward = eval_result.get("mean_reward")
            elif return_code == 0:
                result.status = "completed"
                result.model_path = str(model_path)
                print(f"Run {run_id} completed successfully")
                
                # Evaluate the model
                eval_result = self._evaluate_model(algo, str(model_path), seed)
                result.mean_episode_reward_eval = eval_result.get("mean_reward")
                result.p25_episode_reward_eval = eval_result.get("p25_reward")
                result.std_episode_reward_eval = eval_result.get("std_reward")
                result.episode_rewards_eval = eval_result.get("rewards")
                result.final_reward = eval_result.get("mean_reward")
            else:
                result.status = "failed"
                result.error_message = f"Process exited with code {return_code}"
                print(f"Run {run_id} failed: {result.error_message}")
                
        except subprocess.TimeoutExpired:
            result.status = "failed"
            result.error_message = "Training timed out"
            result.end_time = datetime.now().isoformat()
            print(f"Run {run_id} timed out")
            
        except Exception as e:
            result.status = "failed"
            result.error_message = str(e)
            result.end_time = datetime.now().isoformat()
            print(f"Run {run_id} failed with exception: {e}")
        
        # Save result
        self._save_run_result(result)
        
        return result
    
    def _build_training_command(self, algo: str, config: Dict, seed: int, timesteps: int, model_path: str) -> List[str]:
        """Build the training command based on algorithm"""
        
        # Get absolute path to project root
        project_root = os.path.abspath(".")
        client_path = os.path.join(project_root, "core_v2", "anna", "client")
        
        # Import stable baselines and create training script inline
        python_code = f"""
import sys
import os
import json
import numpy as np

# Add client path
sys.path.insert(0, '{client_path}')
from anna_gym import AnnaGymEnv
from stable_baselines3 import {algo}
from stable_baselines3.common.vec_env import SubprocVecEnv

num_envs = max(1, int(os.environ.get("ANNA_NUM_ENVS", "1")))
port_base = int(os.environ.get("ANNA_PORT_BASE", "5000"))

def _make_env(rank: int):
    def _init():
        return AnnaGymEnv(
            scene_path='{self.scene}',
            port=port_base + rank,
            launch_godot=True,
            headless=True,
            godot_bin='{self.godot_bin}'
        )
    return _init

# Environment
if num_envs == 1:
    env = _make_env(0)()
else:
    start_method = str(os.environ.get("ANNA_VEC_START_METHOD", "fork")).strip() or "fork"
    env = SubprocVecEnv([_make_env(i) for i in range(num_envs)], start_method=start_method)
print(f"[SweepTrain] num_envs={{num_envs}} port_base={{port_base}}")

# Model config
model_config = {json.dumps(config)}
model_config['seed'] = {seed}
model_config['verbose'] = 1
model_config['tensorboard_log'] = '{RUNS_DIR}/tensorboard'

try:
    # Create model
    model = {algo}("MlpPolicy", env, **model_config)
    
    # Train
    model.learn(total_timesteps={timesteps}, progress_bar=True)
    
    # Save model
    model.save('{model_path}')
    print(f"Model saved to {model_path}")
    
    # Get training stats if available
    if hasattr(model, 'logger'):
        print(f"Training complete.")
    
except Exception as e:
    print(f"Training failed: {{e}}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
finally:
    env.close()
"""
        # Write training script to temp file
        train_script_path = RUNS_DIR / "_temp_train.py"
        with open(train_script_path, "w") as f:
            f.write(python_code)
        
        return [sys.executable, str(train_script_path)]
    
    def _evaluate_model(self, algo: str, model_path: str, seed: int, n_episodes: int = 30) -> Dict[str, Any]:
        """Evaluate a trained model"""
        
        # Get absolute path to project root
        project_root = os.path.abspath(".")
        client_path = os.path.join(project_root, "core_v2", "anna", "client")
        
        eval_code = f"""
import sys
import os
import json
import numpy as np

sys.path.insert(0, '{client_path}')
from anna_gym import AnnaGymEnv
from stable_baselines3 import {algo}

env = AnnaGymEnv(
    scene_path='{self.scene}',
    port=5001,  # Different port for eval
    launch_godot=True,
    headless=True,
    godot_bin='{self.godot_bin}'
)

try:
    # Load model
    model = {algo}.load('{model_path}')
    
    # Evaluate
    rewards = []
    for episode in range({n_episodes}):
        obs, _ = env.reset()
        episode_reward = 0
        done = False
        steps = 0
        max_steps = 1000
        
        while not done and steps < max_steps:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(action)
            episode_reward += reward
            done = terminated or truncated
            steps += 1
        
        rewards.append(episode_reward)
        print(f"Episode {{episode + 1}}: reward={{episode_reward:.2f}}")
    
    # Compute stats
    rewards = np.array(rewards)
    result = {{
        'mean_reward': float(np.mean(rewards)),
        'std_reward': float(np.std(rewards)),
        'p25_reward': float(np.percentile(rewards, 25)),
        'p50_reward': float(np.median(rewards)),
        'p75_reward': float(np.percentile(rewards, 75)),
        'rewards': rewards.tolist()
    }}
    
    print(f"Evaluation results: {{result}}")
    print(json.dumps(result))
    
except Exception as e:
    print(f"Evaluation failed: {{e}}")
    import traceback
    traceback.print_exc()
    print(json.dumps({{'error': str(e)}}))
finally:
    env.close()
"""
        # Write eval script
        eval_script_path = RUNS_DIR / "_temp_eval.py"
        with open(eval_script_path, "w") as f:
            f.write(eval_code)
        
        env = os.environ.copy()
        env["ANNA_SCENE"] = self.scene
        env["GODOT_BIN"] = self.godot_bin
        
        try:
            result = subprocess.run(
                [sys.executable, str(eval_script_path)],
                capture_output=True, text=True,
                env=env, cwd=".",
                timeout=1800  # 30 min timeout
            )
            
            # Parse JSON output
            for line in result.stdout.strip().split('\n'):
                try:
                    data = json.loads(line)
                    if 'mean_reward' in data:
                        return data
                except json.JSONDecodeError:
                    continue
            
            return {"error": "Could not parse evaluation results", "stdout": result.stdout}
            
        except subprocess.TimeoutExpired:
            return {"error": "Evaluation timed out"}
        except Exception as e:
            return {"error": str(e)}
        finally:
            # Cleanup
            if eval_script_path.exists():
                eval_script_path.unlink()
    
    def _save_run_result(self, result: RunResult):
        """Save run result to JSON"""
        result_path = RUNS_DIR / result.run_id / "result.json"
        with open(result_path, "w") as f:
            json.dump(asdict(result), f, indent=2)
        
        self.runs.append(result)
    
    def run_sweep(self):
        """Run the full sweep of configurations"""
        print("\n=== Starting Sweep ===")
        
        run_index = 0
        for config in SWEEP_CONFIGS:
            for seed in config["seeds"]:
                run_id = f"run_{run_index:03d}_{config['algo']}_s{seed}"
                result = self.run_single_training(config, seed, run_id)
                run_index += 1
                
                # Save intermediate leaderboard
                self._save_leaderboard()
        
        print("\n=== Sweep Complete ===")
        self._select_best_models()
    
    def _save_leaderboard(self):
        """Save current leaderboard"""
        with open(LEADERBOARD_FILE, "w", newline="") as f:
            if not self.runs:
                return
            
            fieldnames = ["run_id", "algo", "seed", "timesteps", "status", 
                         "mean_episode_reward_eval", "p25_episode_reward_eval", 
                         "std_episode_reward_eval", "start_time", "end_time"]
            
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            
            for result in self.runs:
                row = {
                    "run_id": result.run_id,
                    "algo": result.algo,
                    "seed": result.seed,
                    "timesteps": result.timesteps,
                    "status": result.status,
                    "mean_episode_reward_eval": result.mean_episode_reward_eval,
                    "p25_episode_reward_eval": result.p25_episode_reward_eval,
                    "std_episode_reward_eval": result.std_episode_reward_eval,
                    "start_time": result.start_time,
                    "end_time": result.end_time
                }
                writer.writerow(row)
        
        print(f"Leaderboard saved to {LEADERBOARD_FILE}")
    
    def _select_best_models(self):
        """Select top-2 models for final evaluation"""
        # Filter completed runs with valid evaluation
        valid_runs = [r for r in self.runs 
                     if r.status == "completed" and r.mean_episode_reward_eval is not None]
        
        if not valid_runs:
            print("No completed runs with valid evaluation found!")
            return
        
        # Sort by: 1) mean_episode_reward_eval (desc), 2) p25_episode_reward_eval (desc), 3) std (asc)
        valid_runs.sort(key=lambda r: (-r.mean_episode_reward_eval, 
                                       -r.p25_episode_reward_eval, 
                                       r.std_episode_reward_eval or float('inf')))
        
        top_2 = valid_runs[:2]
        
        print("\n=== Top 2 Models ===")
        for i, run in enumerate(top_2):
            print(f"{i+1}. {run.run_id}: {run.algo} seed={run.seed}, reward={run.mean_episode_reward_eval:.2f}")
        
        # Return top 2 for extended training
        return top_2
    
    def run_final_evaluation(self, model_paths: List[str], n_episodes: int = 30):
        """Run final evaluation on top models"""
        print(f"\n=== Final Evaluation ({n_episodes} episodes each) ===")
        
        results = []
        for model_path in model_paths:
            run_id = Path(model_path).parent.name
            
            # Determine algorithm from config
            config_path = Path(model_path).parent / "result.json"
            if config_path.exists():
                with open(config_path) as f:
                    config = json.load(f)
                    algo = config.get("algo", "PPO")
                    seed = config.get("seed", 42)
            else:
                algo = "PPO"  # Default
                seed = 42
            
            eval_result = self._evaluate_model(algo, model_path, seed, n_episodes)
            results.append({
                "model_path": model_path,
                "eval_result": eval_result
            })
            
            print(f"Model {model_path}: mean_reward={eval_result.get('mean_reward', 'N/A')}")
        
        return results
    
    def save_manifest(self):
        """Save run manifest with metadata"""
        manifest = {
            "git_commit": self.git_commit,
            "mcp_version": self.mcp_version,
            "start_time": self.start_time,
            "end_time": datetime.now().isoformat(),
            "scene": self.scene,
            "godot_bin": self.godot_bin,
            "total_runs": len(self.runs),
            "completed_runs": len([r for r in self.runs if r.status == "completed"]),
            "failed_runs": len([r for r in self.runs if r.status == "failed"]),
        }
        
        with open(MANIFEST_FILE, "w") as f:
            json.dump(manifest, f, indent=2)
        
        print(f"Manifest saved to {MANIFEST_FILE}")


def run_smoke_test():
    """Run a quick smoke test to validate the pipeline"""
    print("\n=== Running Smoke Test (PPO, 5k steps) ===")
    
    sweeper = AnnaOvernightSweep()
    
    # Quick test config
    config = {
        "algo": "PPO",
        "config": {"learning_rate": 3e-4, "n_steps": 512, "batch_size": 32, "n_epochs": 4},
        "seeds": [42],
        "timesteps": 5000
    }
    
    result = sweeper.run_single_training(config, 42, "smoke_test")
    
    if result.status == "completed":
        print("Smoke test PASSED")
        return True
    else:
        print(f"Smoke test FAILED: {result.error_message}")
        return False


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="ANNA Overnight Training Sweep")
    parser.add_argument("--smoke", action="store_true", help="Run smoke test only")
    parser.add_argument("--scene", default=DEFAULT_SCENE, help="RL scene path")
    parser.add_argument("--godot-bin", default="godot3-server", help="Godot binary")
    parser.add_argument("--timesteps", type=int, default=50000, help="Training timesteps per config")
    
    args = parser.parse_args()
    
    if args.smoke:
        success = run_smoke_test()
        sys.exit(0 if success else 1)
    
    # Full sweep
    sweeper = AnnaOvernightSweep(scene=args.scene, godot_bin=args.godot_bin)
    sweeper.run_sweep()
    sweeper._save_leaderboard()
    sweeper.save_manifest()
