#!/usr/bin/env python3
"""
SINGLE ENV MAX SPEED - Simple and stable
"""
import sys, os, time

LOG_FILE = '/tmp/single_fast.log'

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# Best settings for max FPS
PHYSICS_FPS = 4000
BASE_PORT = 13000

log("=" * 50)
log("SINGLE ENV MAX SPEED")
log("=" * 50)

# Set max speed env vars
os.environ['OMP_NUM_THREADS'] = '8'
os.environ['MKL_NUM_THREADS'] = '8'
os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'

# Stage 1: RL
log("\n📚 RL (50k)")
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL.tscn', port=BASE_PORT, launch_godot=True, headless=True)])

model = PPO('MlpPolicy', env,
    n_steps=4096,
    batch_size=512,
    n_epochs=3,
    learning_rate=6e-4,
    ent_coef=0.08,
    policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])},
    verbose=1,
    device='cpu')

t0 = time.time()
model.learn(total_timesteps=50000, progress_bar=True)
log(f"RL done in {time.time()-t0:.0f}s")
env.close()

# Stage 2: RL2
log("\n📚 RL2 (100k)")
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=BASE_PORT+1, launch_godot=True, headless=True)])
model.set_env(env)

t0 = time.time()
model.learn(total_timesteps=100000, progress_bar=True)
log(f"RL2 done in {time.time()-t0:.0f}s")
env.close()

# Stage 3: RL3_Door
log("\n📚 RL3_Door (200k)")
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_3_Door.tscn', port=BASE_PORT+2, launch_godot=True, headless=True)])
model.set_env(env)

t0 = time.time()
model.learn(total_timesteps=200000, progress_bar=True)
log(f"RL3_Door done in {time.time()-t0:.0f}s")
env.close()

# Stage 4: RL4
log("\n📚 RL4 (500k)")
env = DummyVecEnv([lambda: AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=BASE_PORT+3, launch_godot=True, headless=True)])
model.set_env(env)

t0 = time.time()
model.learn(total_timesteps=500000, progress_bar=True)
log(f"RL4 done in {time.time()-t0:.0f}s")
env.close()

model.save(f"{MODELS_DIR}/single_fast.zip")
log("\n✅ DONE")
