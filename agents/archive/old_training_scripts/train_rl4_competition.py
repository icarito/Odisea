#!/usr/bin/env python3
"""
RL4 Competition - Train multiple variants to find best
- RL2 first (learn jumps)
- Then RL4 with long episodes
- Keep CPU under 90C
"""

import sys, os, time, shutil
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import numpy as np

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# Variants to compete
VARIANTS = [
    {'name': 'v1_rl2_rl4', 'lr': 5e-4, 'ent': 0.06, 'rl2_steps': 150000, 'rl4_steps': 800000},
    {'name': 'v2_rl2_rl4', 'lr': 6e-4, 'ent': 0.08, 'rl2_steps': 200000, 'rl4_steps': 600000},
    {'name': 'v3_deep', 'lr': 4e-4, 'ent': 0.05, 'rl2_steps': 150000, 'rl4_steps': 1000000},
]

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp') as f:
            return int(f.read()) / 1000.0
    except:
        return None

def train_variant(variant, idx):
    base_port = 10000 + idx * 100
    
    print(f"\n{'='*60}")
    print(f"Training: {variant['name']}")
    print(f"{'='*60}")
    
    # RL2 first
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=base_port, launch_godot=True, headless=True)
    
    model = PPO('MlpPolicy', env, n_steps=1024, batch_size=256, n_epochs=3,
                learning_rate=variant['lr'], ent_coef=variant['ent'],
                policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])}, verbose=1)
    
    print(f"Training RL2 ({variant['rl2_steps']} steps)...")
    model.learn(total_timesteps=variant['rl2_steps'], progress_bar=True)
    model.save(f"{MODELS_DIR}/{variant['name']}_rl2", exclude=['policy.optimizer'])
    env.close()
    
    # Eval RL2 at 60fps
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=base_port+50, launch_godot=True, headless=True)
    s2 = 0
    for _ in range(5):
        o, _ = env.reset()
        done = False
        while not done:
            a, _ = model.predict(o, deterministic=True)
            o, r, t, tr, _ = env.step(int(a))
            done = t or tr
            if t and r > 0:
                s2 += 1
                break
    env.close()
    print(f"RL2: {s2}/5 = {s2*20}%")
    
    # Now RL4
    os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=base_port+1, launch_godot=True, headless=True)
    model.set_env(env)
    
    print(f"Training RL4 ({variant['rl4_steps']} steps)...")
    model.learn(total_timesteps=variant['rl4_steps'], progress_bar=True)
    model.save(f"{MODELS_DIR}/{variant['name']}_rl4", exclude=['policy.optimizer'])
    env.close()
    
    # Eval RL4 at 60fps
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=base_port+60, launch_godot=True, headless=True)
    
    s4 = 0
    for ep in range(10):
        o, _ = env.reset()
        done = False
        while not done:
            a, _ = model.predict(o, deterministic=True)
            o, r, t, tr, _ = env.step(int(a))
            done = t or tr
            if t and r > 0:
                s4 += 1
                print(f"  RL4 Ep{ep+1}: SUCCESS")
                break
        else:
            print(f"  RL4 Ep{ep+1}: FAILED")
    
    env.close()
    print(f"{variant['name']}: RL2={s2*20}% RL4={s4*10}%")
    
    return {'name': variant['name'], 'rl2': s2*20, 'rl4': s4*10}

def main():
    print("🏆 RL4 Competition Training")
    print(f"Variants: {[v['name'] for v in VARIANTS]}")
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    results = []
    best_rl4 = 0
    best_name = ""
    
    for idx, variant in enumerate(VARIANTS):
        result = train_variant(variant, idx)
        results.append(result)
        
        if result['rl4'] > best_rl4:
            best_rl4 = result['rl4']
            best_name = result['name']
            shutil.copy(f"{MODELS_DIR}/{result['name']}_rl4.zip", f"{MODELS_DIR}/anna_best_rl4_competition.zip")
        
        temp = get_cpu_temp()
        if temp:
            print(f"CPU temp: {temp:.1f}°C")
            if temp > 85:
                print("Cooling down...")
                time.sleep(30)
    
    print("\n" + "="*60)
    print("📊 FINAL RESULTS")
    print("="*60)
    for r in sorted(results, key=lambda x: x['rl4'], reverse=True):
        print(f"{r['name']}: RL2={r['rl2']}% RL4={r['rl4']}%")
    print(f"\n🏆 Best: {best_name} ({best_rl4}%)")

if __name__ == '__main__':
    main()
