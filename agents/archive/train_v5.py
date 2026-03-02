#!/usr/bin/env python3
"""
Training with raw stats printing - no processing
"""
import sys, os, time

LOG_FILE = '/tmp/train_v5.log'

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

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

PHYSICS_FPS = 4000
BASE_PORT = 9500

STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 50000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 100000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 200000),
    ('RL4', 'core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', 500000),
]


class RawStatsCallback(BaseCallback):
    def __init__(self):
        super().__init__()
        self.last_time = time.time()
        
    def _on_step(self) -> bool:
        if self.n_calls % 500 == 0:
            elapsed = time.time() - self.last_time
            fps = 500 / (elapsed + 0.001)
            
            # Print raw stats directly - no processing
            log(f"Step {self.n_calls} | FPS={fps:.0f}")
            log(f"  rollout/ep_rew_mean={self.model.logger.name_to_value.get('rollout/ep_rew_mean', 'N/A')}")
            log(f"  rollout/ep_len_mean={self.model.logger.name_to_value.get('rollout/ep_len_mean', 'N/A')}")
            log(f"  train/approx_kl={self.model.logger.name_to_value.get('train/approx_kl', 'N/A')}")
            log(f"  train/clip_range={self.model.logger.name_to_value.get('train/clip_range', 'N/A')}")
            log(f"  train/entropy={self.model.logger.name_to_value.get('train/entropy', 'N/A')}")
            log(f"  train/explained_variance={self.model.logger.name_to_value.get('train/explained_variance', 'N/A')}")
            log(f"  train/loss={self.model.logger.name_to_value.get('train/loss', 'N/A')}")
            log(f"  train/policy_loss={self.model.logger.name_to_value.get('train/policy_loss', 'N/A')}")
            log(f"  train/value_loss={self.model.logger.name_to_value.get('train/value_loss', 'N/A')}")
            
            self.last_time = time.time()
        return True


def make_env(scene_path, port_offset):
    def _init():
        port = BASE_PORT + port_offset
        os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
        os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
        os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
        return AnnaGymEnv(scene_path, port=port, launch_godot=True, headless=True)
    return _init


def eval_model(model, scene, port, episodes=10):
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
    open(LOG_FILE, 'w').close()
    
    log("=" * 60)
    log("V5 TRAINING - Raw Stats")
    log("=" * 60)
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    callback = RawStatsCallback()
    
    # RL
    log(f"\n📚 RL ({STAGES[0][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[0][1], 0)])
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=4096,
        batch_size=512,
        n_epochs=3,
        learning_rate=6e-4,
        ent_coef=0.08,
        policy_kwargs={'net_arch': dict(pi=[128, 128], vf=[128, 128])},
        verbose=0,
        device='cpu',
    )
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[0][2], callback=callback, progress_bar=True)
    log(f"RL done in {time.time()-t0:.0f}s")
    env.close()
    
    # RL2
    log(f"\n📚 RL2 ({STAGES[1][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[1][1], 1)])
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[1][2], callback=callback, progress_bar=True)
    log(f"RL2 done in {time.time()-t0:.0f}s")
    
    r2 = eval_model(model, STAGES[1][1], BASE_PORT+10, episodes=10)
    log(f"RL2 eval: {r2:.0f}%")
    env.close()
    
    # RL3_Door
    log(f"\n📚 RL3_Door ({STAGES[2][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[2][1], 2)])
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[2][2], callback=callback, progress_bar=True)
    log(f"RL3_Door done in {time.time()-t0:.0f}s")
    
    r3 = eval_model(model, STAGES[2][1], BASE_PORT+11, episodes=10)
    log(f"RL3_Door eval: {r3:.0f}%")
    env.close()
    
    # RL4
    log(f"\n📚 RL4 ({STAGES[3][2]} steps)")
    env = DummyVecEnv([make_env(STAGES[3][1], 3)])
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[3][2], callback=callback, progress_bar=True)
    log(f"RL4 done in {time.time()-t0:.0f}s")
    
    r4 = eval_model(model, STAGES[3][1], BASE_PORT+12, episodes=20)
    log(f"RL4 FINAL: {r4:.0f}%")
    env.close()
    
    model.save(f"{MODELS_DIR}/v5_final.zip")
    log("DONE")


if __name__ == '__main__':
    main()
