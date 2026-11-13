#!/usr/bin/env python3
"""
8 PARALLEL ENVIRONMENTS - Full CPU utilization
"""
import sys, os, time

LOG_FILE = '/tmp/train_8env.log'

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
from stable_baselines3.common.vec_env import SubprocVecEnv
from stable_baselines3.common.callbacks import BaseCallback

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

N_ENVS = 8
PHYSICS_FPS = 3000
BASE_PORT = 9700

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


class StatsCallback(BaseCallback):
    def __init__(self):
        super().__init__()
        self.last_time = time.time()
        
    def _on_step(self) -> bool:
        if self.n_calls % 200 == 0:
            elapsed = time.time() - self.last_time
            fps = 200 * N_ENVS / (elapsed + 0.001)  # Account for 8 envs
            log(f"Step {self.n_calls} | FPS={fps:.0f} ({N_ENVS} envs)")
            self.last_time = time.time()
        return True


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
    log("8 PARALLEL ENVIRONMENTS")
    log("=" * 60)
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    callback = StatsCallback()
    
    # RL with 8 envs
    log(f"\n📚 RL ({STAGES[0][2]} steps) x {N_ENVS}")
    env = SubprocVecEnv([make_env(STAGES[0][1], i) for i in range(N_ENVS)], start_method='fork')
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=1024,
        batch_size=256,
        n_epochs=3,
        learning_rate=6e-4,
        ent_coef=0.08,
        policy_kwargs={'net_arch': dict(pi=[128, 128], vf=[128, 128])},
        verbose=1,
        device='cpu',
    )
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[0][2], callback=callback, progress_bar=True)
    log(f"RL done in {time.time()-t0:.0f}s")
    env.close()
    
    # RL2
    log(f"\n📚 RL2 ({STAGES[1][2]} steps) x {N_ENVS}")
    env = SubprocVecEnv([make_env(STAGES[1][1], i) for i in range(N_ENVS)], start_method='fork')
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[1][2], callback=callback, progress_bar=True)
    log(f"RL2 done in {time.time()-t0:.0f}s")
    
    r2 = eval_model(model, STAGES[1][1], BASE_PORT+100, episodes=10)
    log(f"RL2 eval: {r2:.0f}%")
    env.close()
    
    # RL3_Door
    log(f"\n📚 RL3_Door ({STAGES[2][2]} steps) x {N_ENVS}")
    env = SubprocVecEnv([make_env(STAGES[2][1], i) for i in range(N_ENVS)], start_method='fork')
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[2][2], callback=callback, progress_bar=True)
    log(f"RL3_Door done in {time.time()-t0:.0f}s")
    
    r3 = eval_model(model, STAGES[2][1], BASE_PORT+101, episodes=10)
    log(f"RL3_Door eval: {r3:.0f}%")
    env.close()
    
    # RL4
    log(f"\n📚 RL4 ({STAGES[3][2]} steps) x {N_ENVS}")
    env = SubprocVecEnv([make_env(STAGES[3][1], i) for i in range(N_ENVS)], start_method='fork')
    model.set_env(env)
    
    t0 = time.time()
    model.learn(total_timesteps=STAGES[3][2], callback=callback, progress_bar=True)
    log(f"RL4 done in {time.time()-t0:.0f}s")
    
    r4 = eval_model(model, STAGES[3][1], BASE_PORT+102, episodes=20)
    log(f"RL4 FINAL: {r4:.0f}%")
    env.close()
    
    model.save(f"{MODELS_DIR}/8env_final.zip")
    log("DONE")


if __name__ == '__main__':
    main()
