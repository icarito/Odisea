#!/usr/bin/env python3
"""
3 INDEPENDENT TRAINING JOBS - Each with its own godot
"""
import sys, os, time
import subprocess
import multiprocessing

def run_job(job_id, base_port, lr, ent, arch):
    """Run one training job."""
    log_file = f"/tmp/job{job_id}.log"
    
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '8'
    env['MKL_NUM_THREADS'] = '8'
    env['ANNA_RL_PHYSICS_FPS'] = '3000'
    env['ANNA_RL_TARGET_FPS'] = '3000'
    env['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    env['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    script = f'''
import sys
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO

log = open("{log_file}", "w")
def msg(m):
    import time
    line = f"[{{time.strftime('%H:%M:%S')}}] {{m}}"
    print(line)
    log.write(line + "\\n")
    log.flush()

msg("JOB {job_id} START: lr={lr}, ent={ent}, arch={arch}")

# RL
msg("RL stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL.tscn", port={base_port}, launch_godot=True, headless=True)
model = PPO("MlpPolicy", env, n_steps=2048, batch_size=512, n_epochs=3, learning_rate={lr}, ent_coef={ent}, policy_kwargs={{"net_arch": dict(pi={arch}, vf={arch})}}, verbose=1, device="cpu")
model.learn(total_timesteps=50000, progress_bar=True)
msg("RL done")
env.close()

# RL2
msg("RL2 stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_2.tscn", port={base_port+1}, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=100000, progress_bar=True)
msg("RL2 done")
env.close()

# RL3_Door
msg("RL3_Door stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_3_Door.tscn", port={base_port+2}, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=200000, progress_bar=True)
msg("RL3_Door done")

# Eval
s = 0
for _ in range(10):
    obs, _ = env.reset()
    done = False
    while not done:
        a, _ = model.predict(obs, deterministic=True)
        obs, r, t, tr, _ = env.step(int(a))
        done = t or tr
        if t and r > 0:
            s += 1
            break
msg(f"RL3_Door eval: {{s/10*100:.0f}}%")
env.close()

# RL4
msg("RL4 stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn", port={base_port+3}, launch_godot=True, headless=True)
model.set_env(env)
model.learn(total_timesteps=300000, progress_bar=True)
msg("RL4 done")

s = 0
for _ in range(20):
    obs, _ = env.reset()
    done = False
    while not done:
        a, _ = model.predict(obs, deterministic=True)
        obs, r, t, tr, _ = env.step(int(a))
        done = t or tr
        if t and r > 0:
            s += 1
            break
msg(f"RL4 FINAL: {{s/20*100:.0f}}%")
env.close()

model.save("core_v2/trained_models/job{job_id}.zip")
msg("DONE")
'''
    
    result = subprocess.run(['python3', '-c', script], env=env, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


jobs = [
    (1, 11000, 6e-4, 0.08, [128, 128]),
    (2, 11100, 8e-4, 0.10, [128, 128]),
    (3, 11200, 5e-4, 0.06, [160, 128, 64]),
]

print("Starting 3 parallel training jobs...")

with multiprocessing.Pool(3) as pool:
    results = pool.starmap(run_job, jobs)

print("\n=== RESULTS ===")
for i, (code, out) in enumerate(results):
    print(f"\nJob {i+1}: exit={code}")
    for line in out.split('\n'):
        if 'FINAL' in line or 'eval' in line:
            print(f"  {line}")
