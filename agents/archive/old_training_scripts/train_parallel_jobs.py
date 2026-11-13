#!/usr/bin/env python3
"""
PARALLEL TRAINING JOBS - Multiple independent processes
Each runs a different variant in parallel for 4x speed
"""
import sys, os, time, subprocess, multiprocessing

LOG_DIR = '/tmp/train_parallel'

def run_variant(variant_name, lr, ent, arch, base_port):
    """Run training for one variant."""
    log_file = f"{LOG_DIR}_{variant_name}.log"
    
    env = os.environ.copy()
    env['OMP_NUM_THREADS'] = '8'
    env['MKL_NUM_THREADS'] = '8'
    env['ANNA_RL_PHYSICS_FPS'] = '4000'
    env['ANNA_RL_TARGET_FPS'] = '4000'
    env['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    env['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    # Run training script
    cmd = [
        'python3', '-c', f'''
import sys
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import BaseCallback
import time

LOG_FILE = "{log_file}"
def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{{ts}}] {{msg}}"
    print(line)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\\n")
    except: pass

class VCb(BaseCallback):
    def __init__(self):
        super().__init__()
        self.last = time.time()
    def _on_step(self):
        if self.n_calls % 500 == 0:
            fps = 500 / (time.time() - self.last + 0.001)
            lv = self.model.logger.name_to_value if hasattr(self.model, "logger") and self.model.logger else {{}}
            stats = f"Step {{self.n_calls}} | FPS={{fps:.0f}}"
            for k in ["train/policy_loss", "train/value_loss", "train/entropy_loss", "train/explained_variance", "train/loss"]:
                if k in lv:
                    stats += f" | {{k.split('/')[-1]}}={{lv[k]}}"
            log(stats)
            self.last = time.time()
        return True

log("Starting variant {variant_name}: lr={lr}, ent={ent}, arch={arch}")

# RL
log("RL stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL.tscn", port={base_port}, launch_godot=True, headless=True)
model = PPO("MlpPolicy", env, n_steps=2048, batch_size=512, n_epochs=3, learning_rate={lr}, ent_coef={ent}, policy_kwargs={{"net_arch": dict(pi={arch}, vf={arch})}}, verbose=0, device="cpu")
t0 = time.time()
model.learn(total_timesteps=50000, callback=VCb(), progress_bar=True)
log(f"RL done in {{time.time()-t0:.0f}}s")
env.close()

# RL2
log("RL2 stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_2.tscn", port={base_port+1}, launch_godot=True, headless=True)
model.set_env(env)
t0 = time.time()
model.learn(total_timesteps=100000, callback=VCb(), progress_bar=True)
log(f"RL2 done in {{time.time()-t0:.0f}}s")
env.close()

# RL3_Door
log("RL3_Door stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_3_Door.tscn", port={base_port+2}, launch_godot=True, headless=True)
model.set_env(env)
t0 = time.time()
model.learn(total_timesteps=200000, callback=VCb(), progress_bar=True)
log(f"RL3_Door done in {{time.time()-t0:.0f}}s")

# Eval
success = 0
for _ in range(10):
    obs, _ = env.reset()
    done = False
    while not done:
        a, _ = model.predict(obs, deterministic=True)
        obs, r, t, tr, _ = env.step(int(a))
        done = t or tr
        if t and r > 0:
            success += 1
            break
log(f"RL3_Door eval: {{success/10*100:.0f}}%")
env.close()

# RL4
log("RL4 stage")
env = AnnaGymEnv("core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn", port={base_port+3}, launch_godot=True, headless=True)
model.set_env(env)
t0 = time.time()
model.learn(total_timesteps=300000, callback=VCb(), progress_bar=True)
log(f"RL4 done in {{time.time()-t0:.0f}}s")

# Final eval
success = 0
for _ in range(20):
    obs, _ = env.reset()
    done = False
    while not done:
        a, _ = model.predict(obs, deterministic=True)
        obs, r, t, tr, _ = env.step(int(a))
        done = t or tr
        if t and r > 0:
            success += 1
            break
log(f"RL4 FINAL: {{success/20*100:.0f}}%")
env.close()

model.save("core_v2/trained_models/parallel_{{variant_name}}.zip")
log("DONE")
'''
    ]
    
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def main():
    os.makedirs(LOG_DIR, exist_ok=True)
    
    # 4 variants in parallel
    variants = [
        ('v1', 6e-4, 0.08, [128, 128], 10000),
        ('v2', 8e-4, 0.10, [128, 128], 10100),
        ('v3', 5e-4, 0.06, [160, 128, 64], 10200),
        ('v4', 4e-4, 0.05, [256, 128], 10300),
    ]
    
    print(f"Starting {len(variants)} parallel training jobs...")
    
    with multiprocessing.Pool(len(variants)) as pool:
        results = pool.starmap(run_variant, variants)
    
    # Collect results
    print("\n=== RESULTS ===")
    for (name, _, _, _, _), (code, out, err) in zip(variants, results):
        print(f"\n{name}: exit={code}")
        # Find final result
        for line in out.split('\n'):
            if 'FINAL' in line or 'DONE' in line:
                print(f"  {line}")


if __name__ == '__main__':
    main()
