#!/usr/bin/env python3
import os, sys, time
os.environ["OMP_NUM_THREADS"] = "8"
os.environ["MKL_NUM_THREADS"] = "8"  
os.environ["ANNA_RL_PHYSICS_FPS"] = "4000"
os.environ["ANNA_RL_TARGET_FPS"] = "4000"
os.environ["ANNA_RL_DISABLE_CPU_SLEEP"] = "1"
sys.path.insert(0, "core_v2/anna/client")
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv

LOG_FILE = "/tmp/train_curr.log"

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")
    print(line)

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

log("START")

# RL
log("RL: 50k")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL.tscn", port=26000, launch_godot=True, headless=True)])
m = PPO("MlpPolicy", env, n_steps=4096, batch_size=512, n_epochs=3, learning_rate=6e-4, ent_coef=0.08, policy_kwargs={"net_arch": dict(pi=[128,128], vf=[128,128])}, verbose=1, device="cpu")
m.learn(total_timesteps=50000, progress_bar=True)
log("RL done")
env.close()

# RL2  
log("RL2: 100k")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_2.tscn", port=26001, launch_godot=True, headless=True)])
m.set_env(env)
m.learn(total_timesteps=100000, progress_bar=True)
r2 = eval_model(m, "core_v2/tests/TestScene_RL_2.tscn", 26100, 10)
log(f"RL2 eval: {r2:.0f}%")
env.close()

# RL3_Door
log("RL3_Door: 200k")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_3_Door.tscn", port=26002, launch_godot=True, headless=True)])
m.set_env(env)
m.learn(total_timesteps=200000, progress_bar=True)
r3 = eval_model(m, "core_v2/tests/TestScene_RL_3_Door.tscn", 26101, 10)
log(f"RL3_Door eval: {r3:.0f}%")
env.close()

# RL4
log("RL4: 400k")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn", port=26003, launch_godot=True, headless=True)])
m.set_env(env)
m.learn(total_timesteps=400000, progress_bar=True)
r4 = eval_model(m, "core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn", 26102, 20)
log(f"RL4 eval: {r4:.0f}%")

m.save("core_v2/trained_models/best_model.zip")
log(f"SAVED best_model.zip (RL2:{r2:.0f}% RL3:{r3:.0f}% RL4:{r4:.0f}%)")
log("DONE")
