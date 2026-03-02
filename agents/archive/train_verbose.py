#!/usr/bin/env python3
"""Verbose training with GA and eval"""
import sys, os, time, random
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import numpy as np

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

def eval_model(model, scene, port, episodes=5):
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    env = AnnaGymEnv(scene, port=port, launch_godot=True, headless=True)
    s = 0
    for _ in range(episodes):
        o, _ = env.reset()
        done = False
        while not done:
            a, _ = model.predict(o, deterministic=True)
            o, r, t, tr, _ = env.step(int(a))
            done = t or tr
            if t and r > 0:
                s += 1
                break
    env.close()
    return s / episodes * 100

def train_variant(variant, idx):
    base_port = 60000 + idx * 100
    os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
    
    print(f"\n{'='*60}")
    print(f"VARIANT: lr={variant['lr']}, ent={variant['ent']}, arch={variant['arch']}")
    print(f"{'='*60}")
    
    # RL
    print(f"\n>>> RL (50k)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL.tscn', port=base_port, launch_godot=True, headless=True)
    model = PPO('MlpPolicy', env, n_steps=1024, batch_size=256, n_epochs=3,
                learning_rate=variant['lr'], ent_coef=variant['ent'],
                policy_kwargs={'net_arch': dict(pi=variant['arch'], vf=variant['arch'])}, verbose=1)
    model.learn(total_timesteps=50000, progress_bar=True)
    env.close()
    
    # RL2
    print(f"\n>>> RL2 (100k)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=base_port+1, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=100000, progress_bar=True)
    env.close()
    
    r2 = eval_model(model, 'core_v2/tests/TestScene_RL_2.tscn', base_port+10)
    print(f"   RL2 eval: {r2:.0f}%")
    
    # RL3_Door
    print(f"\n>>> RL3_Door (200k)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_3_Door.tscn', port=base_port+2, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=200000, progress_bar=True)
    env.close()
    
    r3 = eval_model(model, 'core_v2/tests/TestScene_RL_3_Door.tscn', base_port+11)
    print(f"   RL3_Door eval: {r3:.0f}%")
    
    # RL4
    print(f"\n>>> RL4 (500k)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=base_port+3, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=500000, progress_bar=True)
    env.close()
    
    r4 = eval_model(model, 'core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', base_port+12)
    print(f"   RL4 eval: {r4:.0f}%")
    
    model.save(f"{MODELS_DIR}/variant_{variant['name']}", exclude=['policy.optimizer'])
    
    return {'name': variant['name'], 'rl2': r2, 'rl3_door': r3, 'rl4': r4}

def main():
    print("=== VERBOSE GA TRAINING: RL -> RL2 -> RL3_Door -> RL4 ===")
    print(f"CPU threads: 8, Physics FPS: 4000")
    
    # GA variants
    variants = [
        {'name': 'baseline', 'lr': 6e-4, 'ent': 0.08, 'arch': [128, 128]},
        {'name': 'explorer', 'lr': 8e-4, 'ent': 0.10, 'arch': [128, 128]},
        {'name': 'deep', 'lr': 5e-4, 'ent': 0.06, 'arch': [160, 128, 64]},
    ]
    
    results = []
    best = 0
    best_name = ""
    
    for i, v in enumerate(variants):
        result = train_variant(v, i)
        results.append(result)
        
        score = result['rl2'] * 0.2 + result['rl3_door'] * 0.3 + result['rl4'] * 0.5
        if score > best:
            best = score
            best_name = result['name']
            import shutil
            shutil.copy(f"{MODELS_DIR}/variant_{result['name']}.zip", 
                       f"{MODELS_DIR}/best_ga_rl4.zip")
    
    print("\n=== FINAL RESULTS ===")
    for r in sorted(results, key=lambda x: x['rl4'], reverse=True):
        print(f"{r['name']}: RL2={r['rl2']:.0f}% RL3={r['rl3_door']:.0f}% RL4={r['rl4']:.0f}%")
    print(f"\nBest: {best_name} ({best:.0f}%)")

if __name__ == '__main__':
    main()
