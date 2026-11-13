#!/usr/bin/env python3
"""
PARALLEL TRAINING - 16 ENVIRONMENTS (2x 8 CPUs)
- Full curriculum: RL -> RL2 -> RL3_Door -> RL4
- Verbose logging with FPS, loss, explained_variance
- Best hyperparameters from prior runs
"""
import sys, os, time
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
from stable_baselines3.common.callbacks import BaseCallback
import numpy as np

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# Config
N_ENVS = 16  # 2x CPUs
PHYSICS_FPS = 4000
BASE_PORT = 6000

# Best hyperparameters from prior runs
BEST_PARAMS = {
    'lr': 6e-4,
    'ent': 0.08,
    'arch': [128, 128],
}

# Curriculum stages
STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 50000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 100000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 200000),
    ('RL4', 'core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', 500000),
]


class VerboseCallback(BaseCallback):
    """Log FPS, loss, explained_variance every 100 steps."""
    def __init__(self):
        super().__init__()
        self.last_log_time = time.time()
        self.step_count = 0
        
    def _on_step(self) -> bool:
        self.step_count += 1
        if self.step_count % 100 == 0:
            # Get training stats
            if hasattr(self.model, 'logger') and self.model.logger is not None:
                # Try to get loss values
                loss_vals = self.model.logger.name_to_value
                fps = 100 / (time.time() - self.last_log_time + 0.001)
                
                log_str = f"Step {self.step_count} | FPS: {fps:.0f}"
                
                if 'train/policy_loss' in loss_vals:
                    log_str += f" | policy_loss: {loss_vals['train/policy_loss']:.4f}"
                if 'train/value_loss' in loss_vals:
                    log_str += f" | value_loss: {loss_vals['train/value_loss']:.4f}"
                if 'train/entropy_loss' in loss_vals:
                    log_str += f" | ent_loss: {loss_vals['train/entropy_loss']:.4f}"
                if 'train/explained_variance' in loss_vals:
                    log_str += f" | explained_var: {loss_vals['train/explained_variance']:.3f}"
                    
                print(log_str)
            
            self.last_log_time = time.time()
        return True


def make_env(scene_path, port_offset):
    """Factory for creating env instances."""
    def _init():
        port = BASE_PORT + port_offset
        os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
        # NOT using Dummy audio driver (per user request)
        return AnnaGymEnv(scene_path, port=port, launch_godot=True, headless=True)
    return _init


def eval_model(model, scene, port, episodes=10):
    """Evaluate model success rate."""
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    env = AnnaGymEnv(scene, port=port, launch_godot=True, headless=True)
    
    successes = 0
    for _ in range(episodes):
        obs, _ = env.reset()
        done = False
        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            if terminated and reward > 0:
                successes += 1
                break
    
    env.close()
    return successes / episodes * 100


def main():
    print("=" * 70)
    print("🚀 PARALLEL TRAINING: 16 ENVIRONMENTS (2x 8 CPUs)")
    print("=" * 70)
    print(f"Config: lr={BEST_PARAMS['lr']}, ent={BEST_PARAMS['ent']}, arch={BEST_PARAMS['arch']}")
    print(f"Physics FPS: {PHYSICS_FPS}")
    print("=" * 70)
    
    # Set thread env vars
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    callback = VerboseCallback()
    total_start = time.time()
    
    # Start with RL stage
    print(f"\n📚 Stage 1: RL ({STAGES[0][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[0][1], i) for i in range(N_ENVS)])
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=1024,
        batch_size=256,
        n_epochs=3,
        learning_rate=BEST_PARAMS['lr'],
        ent_coef=BEST_PARAMS['ent'],
        policy_kwargs={'net_arch': dict(pi=BEST_PARAMS['arch'], vf=BEST_PARAMS['arch'])},
        verbose=1,
        device='cpu',
    )
    
    stage_start = time.time()
    model.learn(total_timesteps=STAGES[0][2], callback=callback, progress_bar=True)
    rl_time = time.time() - stage_start
    print(f"   ⏱️ RL done in {rl_time:.0f}s")
    
    env.close()
    
    # Subsequent stages
    for stage_idx, (name, path, steps) in enumerate(STAGES[1:], 1):
        print(f"\n📚 Stage {stage_idx+1}: {name} ({steps} steps)")
        
        env = DummyVecEnv([make_env(path, i) for i in range(N_ENVS)])
        model.set_env(env)
        
        stage_start = time.time()
        model.learn(total_timesteps=steps, callback=callback, progress_bar=True)
        stage_time = time.time() - stage_start
        
        env.close()
        
        # Eval
        eval_port = BASE_PORT + 1000 + stage_idx
        rate = eval_model(model, path, eval_port, episodes=10)
        print(f"   📊 {name} eval: {rate:.0f}% in {stage_time:.0f}s")
        
        # Save checkpoint
        model.save(f"{MODELS_DIR}/rl_checkpoint_{name}.zip", exclude=['policy.optimizer'])
    
    # Final eval on RL4
    print("\n🎯 FINAL EVALUATION")
    final_rate = eval_model(model, STAGES[3][1], BASE_PORT + 3000, episodes=20)
    print(f"   RL4: {final_rate:.0f}%")
    
    # Save final model
    model.save(f"{MODELS_DIR}/rl_16env_final.zip", exclude=['policy.optimizer'])
    print(f"\n💾 Saved to {MODELS_DIR}/rl_16env_final.zip")
    
    total_time = time.time() - total_start
    print(f"\n✅ Training complete in {total_time/60:.1f} minutes")


if __name__ == '__main__':
    main()
