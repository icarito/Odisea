#!/usr/bin/env python3
"""
FULL POWER TRAINING - 4000+ FPS
- No audio driver overhead
- Max physics FPS
- All CPU cores
"""

import sys
import os
import time
import shutil
from pathlib import Path

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import numpy as np

MODELS_DIR = Path('agents/models')
MODELS_DIR.mkdir(exist_ok=True)

# SUPER FAST SETTINGS
PHYSICS_FPS = 4000
TARGET_FPS = 4000

# Curriculum
STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 50000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 80000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 120000),
]

# Variants
VARIANTS = [
    {'name': 'std', 'lr': 3e-4, 'ent': 0.02, 'arch': [128, 128]},
    {'name': 'explorer', 'lr': 5e-4, 'ent': 0.06, 'arch': [128, 128]},
    {'name': 'deep', 'lr': 2e-4, 'ent': 0.03, 'arch': [160, 128, 64]},
]

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp') as f:
            return int(f.read()) / 1000.0
    except:
        return None

def train_variant(variant, idx):
    """Train one variant through curriculum."""
    base_port = 7200 + idx * 100
    
    # Environment for max speed
    env_config = {
        'ANNA_RL_PHYSICS_FPS': str(PHYSICS_FPS),
        'ANNA_RL_TARGET_FPS': str(TARGET_FPS),
        'ANNA_RL_DISABLE_CPU_SLEEP': '1',
        'ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG': '1',
    }
    
    for k, v in env_config.items():
        os.environ[k] = v
    
    print(f"\n{'='*60}")
    print(f"🧬 {variant['name']}")
    print(f"{'='*60}")
    
    # Start with RL
    env = AnnaGymEnv(
        scene_path=STAGES[0][1],
        port=base_port,
        launch_godot=True,
        headless=True,
    )
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=1024,
        batch_size=256,
        n_epochs=3,
        learning_rate=variant['lr'],
        ent_coef=variant['ent'],
        policy_kwargs={'net_arch': dict(pi=variant['arch'], vf=variant['arch'])},
        verbose=1,
    )
    
    scores = {}
    
    for stage_idx, (name, path, steps) in enumerate(STAGES):
        print(f"\n📚 {name} ({steps} steps)")
        
        if stage_idx > 0:
            env.close()
            env = AnnaGymEnv(scene_path=path, port=base_port + stage_idx, launch_godot=True, headless=True)
            model.set_env(env)
        
        start = time.time()
        model.learn(total_timesteps=steps, progress_bar=True)
        elapsed = time.time() - start
        
        print(f"  ⏱️  {elapsed:.0f}s ({steps/elapsed:.0f} steps/sec)")
        
        # Quick eval
        successes = 0
        for _ in range(5):
            obs, _ = env.reset()
            done = False
            while not done:
                action, _ = model.predict(obs, deterministic=True)
                obs, reward, terminated, truncated, _ = env.step(int(action))
                done = terminated or truncated
                if terminated and reward > 0:
                    successes += 1
                    break
        
        rate = successes / 5
        scores[name] = rate
        print(f"  📊 {name}: {rate*100:.0f}% success")
        
        # Save
        model.save(f"{MODELS_DIR}/anna_{variant['name']}_{name}", exclude=['policy.optimizer'])
    
    env.close()
    
    score = scores.get('RL',0)*10 + scores.get('RL2',0)*30 + scores.get('RL3_Door',0)*60
    print(f"\n✅ {variant['name']}: RL={scores.get('RL',0)*100:.0f}% RL2={scores.get('RL2',0)*100:.0f}% RL3_Door={scores.get('RL3_Door',0)*100:.0f}%")
    
    return {'name': variant['name'], 'scores': scores, 'score': score}

def main():
    print("🚀 FULL POWER TRAINING")
    print(f"=" * 50)
    print(f"FPS: {PHYSICS_FPS}")
    print(f"Variants: {[v['name'] for v in VARIANTS]}")
    print(f"Stages: {[s[0] for s in STAGES]}")
    print("=" * 50)
    
    # Set env vars globally
    os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
    os.environ['ANNA_RL_TARGET_FPS'] = str(TARGET_FPS)
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    results = []
    
    for idx, variant in enumerate(VARIANTS):
        result = train_variant(variant, idx)
        results.append(result)
        
        # Save best
        if result['score'] > 0:
            src = f"{MODELS_DIR}/anna_{result['name']}_RL3_Door.zip"
            dst = f"{MODELS_DIR}/anna_best_full.zip"
            if os.path.exists(src):
                shutil.copy(src, dst)
                print(f"⭐ Saved best: {dst}")
        
        temp = get_cpu_temp()
        if temp:
            print(f"🌡️  CPU: {temp:.1f}°C")
    
    # Summary
    print("\n" + "="*50)
    print("📊 FINAL")
    print("="*50)
    for r in sorted(results, key=lambda x: x['score'], reverse=True):
        s = r['scores']
        print(f"{r['name']:10s}: RL={s.get('RL',0)*100:5.0f}% RL2={s.get('RL2',0)*100:5.0f}% RL3_Door={s.get('RL3_Door',0)*100:5.0f}%")

if __name__ == '__main__':
    main()
