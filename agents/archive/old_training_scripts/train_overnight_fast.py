#!/usr/bin/env python3
"""
Overnight Training - FAST MODE (3000+ FPS)
"""

import sys
import os
import time
import random
from pathlib import Path

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO

MODELS_DIR = Path('agents/models')
MODELS_DIR.mkdir(exist_ok=True)

# FAST MODE - High FPS training
PHYSICS_FPS = 3000
TARGET_FPS = 3000

# Scenes: RL -> RL2 -> RL3_Door (NOT multi-height RL3)
SCENES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 30000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 50000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 80000),
]

# Multiple variants
VARIANTS = [
    {'name': 'base', 'lr': 3e-4, 'ent': 0.02, 'arch': [128, 128]},
    {'name': 'high_ent', 'lr': 3e-4, 'ent': 0.05, 'arch': [128, 128]},
    {'name': 'deep', 'lr': 2e-4, 'ent': 0.02, 'arch': [128, 128, 64]},
    {'name': 'wide', 'lr': 5e-4, 'ent': 0.01, 'arch': [192, 96]},
    {'name': 'narrow', 'lr': 4e-4, 'ent': 0.03, 'arch': [96, 96, 96]},
]

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp') as f:
            return int(f.read()) / 1000.0
    except:
        return None

def train_variant(variant_config, variant_idx):
    """Train one variant through curriculum."""
    base_port = 7000 + variant_idx * 100
    
    env = AnnaGymEnv(
        scene_path=SCENES[0][1],
        port=base_port,
        launch_godot=True,
        headless=True,
    )
    
    model = PPO(
        'MlpPolicy', env,
        n_steps=512,
        batch_size=128,
        n_epochs=3,
        learning_rate=variant_config['lr'],
        ent_coef=variant_config['ent'],
        policy_kwargs={'net_arch': dict(pi=variant_config['arch'], vf=variant_config['arch'])},
        verbose=1,
    )
    
    scores = {}
    
    for stage_idx, (stage_name, scene_path, timesteps) in enumerate(SCENES):
        print(f"\n{'='*50}")
        print(f"Variant: {variant_config['name']} | Stage: {stage_name}")
        print(f"{'='*50}")
        
        # Switch scene
        if stage_idx > 0:
            env.close()
            env = AnnaGymEnv(scene_path=scene_path, port=base_port + stage_idx, launch_godot=True, headless=True)
            model.set_env(env)
        
        # Train with thermal monitoring
        start = time.time()
        model.learn(total_timesteps=timesteps, progress_bar=True)
        elapsed = time.time() - start
        
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
        
        success_rate = successes / 5
        scores[stage_name] = success_rate
        print(f"\n📊 {stage_name}: {success_rate*100:.0f}% success ({elapsed:.0f}s)")
        
        # Save checkpoint
        model.save(f"{MODELS_DIR}/anna_{variant_config['name']}_{stage_name}", exclude=['policy.optimizer'])
    
    env.close()
    return scores

def main():
    print("🚀 FAST OVERNIGHT TRAINING")
    print(f"=" * 50)
    print(f"FPS: {PHYSICS_FPS}")
    print(f"Scenes: {[s[0] for s in SCENES]}")
    print(f"Variants: {len(VARIANTS)}")
    print("=" * 50)
    
    all_scores = {}
    best_score = 0
    best_variant = None
    
    for idx, variant in enumerate(VARIANTS):
        print(f"\n{'#'*60}")
        print(f"🔬 Variant {idx+1}/{len(VARIANTS)}: {variant['name']}")
        print(f"{'#'*60}")
        
        scores = train_variant(variant, idx)
        all_scores[variant['name']] = scores
        
        # Track best (weighted: RL3_Door most important)
        score = scores.get('RL', 0) * 20 + scores.get('RL2', 0) * 30 + scores.get('RL3_Door', 0) * 50
        if score > best_score:
            best_score = score
            best_variant = variant['name']
            # Save best
            import shutil
            src = f"{MODELS_DIR}/anna_{variant['name']}_RL3_Door.zip"
            dst = f"{MODELS_DIR}/anna_best_fast.zip"
            if os.path.exists(src):
                shutil.copy(src, dst)
                print(f"⭐ New best! Saved to {dst}")
        
        # Thermal check
        temp = get_cpu_temp()
        if temp:
            print(f"CPU temp: {temp:.1f}°C")
    
    # Summary
    print("\n" + "="*50)
    print("📊 FINAL RESULTS")
    print("="*50)
    for name, scores in all_scores.items():
        print(f"{name}: RL={scores.get('RL',0)*100:.0f}% RL2={scores.get('RL2',0)*100:.0f}% RL3_Door={scores.get('RL3_Door',0)*100:.0f}%")
    
    print(f"\n🏆 Best variant: {best_variant}")
    print(f"Model saved: {MODELS_DIR}/anna_best_fast.zip")

if __name__ == '__main__':
    main()
