#!/usr/bin/env python3
"""
GA COMPETITION - Find best small model
Multiple variants racing in parallel
"""
import sys, os, time
import subprocess

LOG_FILE = '/tmp/ga_comp.log'

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, 'a') as f:
        f.write(line + '\n')

# Variants to test
VARIANTS = [
    {'name': 'v1', 'lr': 6e-4, 'ent': 0.08, 'arch': [128,128], 'port': 14000},
    {'name': 'v2', 'lr': 8e-4, 'ent': 0.10, 'arch': [128,128], 'port': 14100},
    {'name': 'v3', 'lr': 5e-4, 'ent': 0.06, 'arch': [160,128,64], 'port': 14200},
    {'name': 'v4', 'lr': 4e-4, 'ent': 0.05, 'arch': [256,128], 'port': 14300},
]

def run_variant(v):
    """Run one variant"""
    port = v['port']
    name = v['name']
    lr = v['lr']
    ent = v['ent']
    arch = v['arch']
    
    log(f"\n{'='*40}")
    log(f"STARTING: {name} lr={lr} ent={ent} arch={arch}")
    log(f"{'='*40}")
    
    # Build script inline
    script = f'''
import sys, os, time
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.vec_env import DummyVecEnv

os.environ['OMP_NUM_THREADS'] = '8'
os.environ['MKL_NUM_THREADS'] = '8'
os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
os.environ['ANNA_RL_TARGET_FPS'] = '4000'
os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'

log_file = open("/tmp/ga_{name}.log", "w")
def log(msg):
    line = f"[{{time.strftime('%H:%M:%S')}}] {{msg}}"
    print(line)
    log_file.write(line + "\\n")
    log_file.flush()

log(f"VARIANT {name}: lr={{lr}}, ent={{ent}}, arch={{arch}}")

# RL - quick
log("RL")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL.tscn", port={port}, launch_godot=True, headless=True)])
model = PPO("MlpPolicy", env, n_steps=2048, batch_size=512, n_epochs=3, learning_rate={lr}, ent_coef={ent}, policy_kwargs={{"net_arch": dict(pi={arch}, vf={arch})}}, verbose=1, device="cpu")
model.learn(total_timesteps=30000, progress_bar=True)
log("RL done")
env.close()

# RL2
log("RL2")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_2.tscn", port={port+1}, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=60000, progress_bar=True)
log("RL2 done")
env.close()

# RL3_Door
log("RL3_Door")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_3_Door.tscn", port={port+2}, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=100000, progress_bar=True)

# Quick eval
s=0
for _ in range(5):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0:
            s+=1
            break
log(f"RL3_Door eval: {{s/5*100:.0f}}%")
rl3_score = s/5*100
env.close()

# RL4
log("RL4")
env = DummyVecEnv([lambda: AnnaGymEnv("core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn", port={port+3}, launch_godot=True, headless=True)])
model.set_env(env)
model.learn(total_timesteps=150000, progress_bar=True)

# Final eval
s=0
for _ in range(10):
    obs,_=env.reset()
    done=False
    while not done:
        a,_=model.predict(obs,deterministic=True)
        obs,r,t,tr,_=env.step(int(a))
        done=t or tr
        if t and r>0:
            s+=1
            break
log(f"RL4 FINAL: {{s/10*100:.0f}}%")
rl4_score = s/10*100
env.close()

model.save(f"core_v2/trained_models/ga_{name}.zip")
log(f"SAVED: ga_{name}.zip")
log(f"SCORES: RL3={{rl3_score:.0f}}% RL4={{rl4_score:.0f}}%")
'''
    
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '8'
    env['MKL_NUM_THREADS'] = '8'
    env['ANNA_RL_PHYSICS_FPS'] = '4000'
    env['ANNA_RL_TARGET_FPS'] = '4000'
    env['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    env['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    result = subprocess.run(['python3', '-c', script], env=env, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr

log("="*60)
log("GA COMPETITION STARTING")
log("="*60)
log(f"Variants: {len(VARIANTS)}")

# Run all variants
results = []
for v in VARIANTS:
    code, out = run_variant(v)
    results.append((v['name'], code, out))
    # Extract score
    for line in out.split('\n'):
        if 'RL4 FINAL' in line:
            log(f"RESULT: {line}")

# Find best
log("\n" + "="*60)
log("FINAL STANDINGS")
log("="*60)
for name, code, out in results:
    score = 0
    for line in out.split('\n'):
        if 'RL4 FINAL' in line:
            score = line
    log(f"{name}: {score}")

log("\nDONE")
