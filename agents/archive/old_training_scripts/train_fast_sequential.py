#!/usr/bin/env python3
"""
FAST SEQUENTIAL TRAINING - DummyVecEnv (stable)
- Full curriculum: RL -> RL2 -> RL3_Door -> RL4  
- Maximum FPS with default audio driver
- Verbose logging + /tmp log
"""
import sys, os, time

LOG_FILE = '/tmp/train_sequential.log'

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(line + '\n')
    except:
        pass

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv
from stable_baselines3.common.callbacks import BaseCallback
import numpy as np

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# Config - SEQUENTIAL BUT STABLE
N_ENVS = 1  # Single env for stability
PHYSICS_FPS = 4000
BASE_PORT = 8000

BEST_PARAMS = {
    'lr': 6e-4,
    'ent': 0.08,
    'arch': [128, 128],
}

STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 50000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 100000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 200000),
    ('RL4', 'core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', 500000),
]


def make_env(scene_path, port_offset):
    def _init():
        port = BASE_PORT + port_offset
        os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
        os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
        return AnnaGymEnv(scene_path, port=port, launch_godot=True, headless=True)
    return _init


class VerboseCallback(BaseCallback):
    def __init__(self):
        super().__init__()
        self.last_time = time.time()
        
    def _on_step(self) -> bool:
        if self.n_calls % 500 == 0:
            fps = 500 / (time.time() - self.last_time + 0.001)
            loss_info = ""
            if hasattr(self.model, 'logger') and self.model.logger:
                lv = self.model.logger.name_to_value
                if 'train/policy_loss' in lv:
                    loss_info = f" | policy={lv['train/policy_loss']:.3f}"
                if 'train/explained_variance' in lv:
                    loss_info += f" | var={lv['train/explained_variance']:.2f}"
            log(f"Step {self.n_calls} | FPS={fps:.0f}{loss_info}")
            self.last_time = time.time()
        return True


def eval_model(model, scene, port, episodes=10):
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
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
    open(LOG_FILE, 'w').close()
    
    log("=" * 60)
    log("🚀 FAST SEQUENTIAL: DummyVecEnv (stable)")
    log("=" * 60)
    log(f"Config: lr={BEST_PARAMS['lr']}, ent={BEST_PARAMS['ent']}, arch={BEST_PARAMS['arch']}")
    log(f"Physics FPS: {PHYSICS_FPS}")
    log("=" * 60)
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    callback = VerboseCallback()
    total_start = time.time()
    
    # Start with RL
    log(f"\n📚 Stage 1: RL ({STAGES[0][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[0][1], 0)])
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=2048,  # Larger for sequential
        batch_size=512,
        n_epochs=3,
        learning_rate=BEST_PARAMS['lr'],
        ent_coef=BEST_PARAMS['ent'],
        policy_kwargs={'net_arch': dict(pi=BEST_PARAMS['arch'], vf=BEST_PARAMS['arch'])},
        verbose=0,
        device='cpu',
    )
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[0][2], callback=callback, progress_bar=True)
    log(f"   ⏱️  RL done in {time.time()-t0:.0f}s")
    env.close()
    
    # Subsequent stages
    for stage_idx, (name, path, steps) in enumerate(STAGES[1:], 1):
        log(f"\n📚 Stage {stage_idx+1}: {name} ({steps} steps)")
        
        env = DummyVecEnv([make_env(path, stage_idx)])
        model.set_env(env)
        
        t0 = time.time()
        model.learn(total_timesteps=steps, callback=callback, progress_bar=True)
        stage_time = time.time() - t0
        
        env.close()
        
        rate = eval_model(model, path, BASE_PORT + 100 + stage_idx, episodes=10)
        log(f"   📊 {name}: {rate:.0f}% | {stage_time:.0f}s")
        
        model.save(f"{MODELS_DIR}/chk_{name}.zip", exclude=['policy.optimizer'])
    
    # Final eval
    log("\n🎯 FINAL")
    final_rate = eval_model(model, STAGES[3][1], BASE_PORT + 200, episodes=20)
    log(f"   RL4: {final_rate:.0f}%")
    
    model.save(f"{MODELS_DIR}/fast_seq_final.zip")
    
    total = time.time() - total_start
    log(f"\n✅ Done in {total/60:.1f} min")


if __name__ == '__main__':
    main()
