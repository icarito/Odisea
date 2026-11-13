#!/usr/bin/env python3
"""
Overnight Training Script for Odisea Agent
- Trains on RL -> RL2 -> RL3_Door (NOT RL3 which has multi-height issues)
- Uses genetic algorithm for hyperparameter variations
- Keeps CPU under 90C
- Targets ~0.5MB model
"""

import sys
import os
import time
import random
import signal
import subprocess
from pathlib import Path

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import numpy as np

# === CONFIG ===
MODELS_DIR = Path('agents/models')
MODELS_DIR.mkdir(exist_ok=True)

# Thermal management - check CPU temp every N steps
TEMP_LIMIT = 90
TEMP_CHECK_INTERVAL = 30

# Target scenes in order of difficulty
SCENES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', 20000),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', 30000),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', 50000),
]

# Genetic algorithm population
POPULATION = 3
GENERATIONS = 4

# Base architecture (128x128 = ~150KB, fits 0.5MB with optimizer)
BASE_ARCH = [128, 128]

# === THERMAL MANAGEMENT ===
def get_cpu_temp():
    """Get CPU temperature. Returns None if unavailable."""
    try:
        result = subprocess.run(
            ['cat', '/sys/class/thermal/thermal_zone0/temp'],
            capture_output=True, text=True, timeout=1
        )
        if result.returncode == 0:
            return int(result.stdout.strip()) / 1000.0
    except:
        pass
    return None

def should_throttle():
    """Check if we should throttle due to heat."""
    temp = get_cpu_temp()
    if temp and temp > TEMP_LIMIT:
        print(f"⚠️  CPU at {temp:.1f}°C - throttling...")
        return True
    return False

def thermal_throttle():
    """Wait for CPU to cool down."""
    while should_throttle():
        time.sleep(10)
    print(f"✅ CPU temp OK, continuing...")

# === GENETIC ALGORITHM ===
def create_hyperparams(variant_id):
    """Create hyperparameters with genetic variation."""
    random.seed(variant_id * 12345)
    
    # Mutation of base hyperparameters
    lr = 3e-4 * random.uniform(0.5, 1.5)
    ent_coef = 0.02 * random.uniform(0.5, 2.0)
    n_steps = int(256 * random.choice([1, 2]))
    batch_size = int(64 * random.choice([1, 2]))
    n_epochs = random.choice([2, 3, 4])
    
    # Small network variations
    depth = random.choice([1, 2])
    width = random.choice([96, 128, 160])
    arch = [width] * depth
    
    return {
        'learning_rate': lr,
        'ent_coef': ent_coef,
        'n_steps': n_steps,
        'batch_size': batch_size,
        'n_epochs': n_epochs,
        'net_arch': dict(pi=arch, vf=arch),
    }

def train_model(scene_path, total_timesteps, hyperparams, variant_id, port):
    """Train a model on a single scene."""
    print(f"\n{'='*60}")
    print(f"Training {variant_id} on {scene_path}")
    print(f"Hyperparams: lr={hyperparams['learning_rate']:.2e}, ent={hyperparams['ent_coef']:.3f}")
    print(f"{'='*60}")
    
    env = AnnaGymEnv(
        scene_path=scene_path,
        port=port,
        launch_godot=True,
        headless=True,
    )
    
    model = PPO(
        'MlpPolicy',
        env,
        verbose=1,
        n_steps=hyperparams['n_steps'],
        batch_size=hyperparams['batch_size'],
        n_epochs=hyperparams['n_epochs'],
        learning_rate=hyperparams['learning_rate'],
        ent_coef=hyperparams['ent_coef'],
        policy_kwargs={'net_arch': hyperparams['net_arch']},
        device='cpu',
    )
    
    # Train with thermal monitoring
    steps_done = 0
    chunk_size = 5000
    while steps_done < total_timesteps:
        thermal_throttle()
        
        remaining = total_timesteps - steps_done
        train_steps = min(chunk_size, remaining)
        
        model.learn(
            total_timesteps=steps_done + train_steps,
            progress_bar=False,
            reset_num_timesteps=False
        )
        steps_done += train_steps
        
        temp = get_cpu_temp()
        if temp:
            print(f"  [{steps_done}/{total_timesteps}] temp={temp:.1f}°C", flush=True)
    
    env.close()
    return model

def evaluate_model(model, scene_path, port, num_episodes=5):
    """Quick evaluation of model."""
    env = AnnaGymEnv(
        scene_path=scene_path,
        port=port,
        launch_godot=True,
        headless=True,
    )
    
    successes = 0
    total_reward = 0
    
    for ep in range(num_episodes):
        obs, _ = env.reset()
        done = False
        steps = 0
        max_steps = 1500
        
        while not done and steps < max_steps:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            steps += 1
            
            if terminated and reward > 0:
                successes += 1
                total_reward += reward
                break
        
        if not done:
            total_reward += reward  # timeout reward
    
    env.close()
    
    success_rate = successes / num_episodes
    avg_reward = total_reward / num_episodes
    
    return success_rate, avg_reward

def run_curriculum(variant_id, hyperparams):
    """Run full curriculum: RL -> RL2 -> RL3_Door"""
    base_port = 7000 + (variant_id * 100)
    
    model = None
    total_score = 0
    
    for stage_idx, (stage_name, scene_path, timesteps) in enumerate(SCENES):
        print(f"\n🎯 Stage {stage_idx+1}/{len(SCENES)}: {stage_name}")
        
        # Train
        if model is None:
            model = train_model(scene_path, timesteps, hyperparams, f"v{variant_id}_{stage_name}", base_port + stage_idx)
        else:
            env = AnnaGymEnv(scene_path=scene_path, port=base_port + stage_idx + 10, launch_godot=True, headless=True)
            model.set_env(env)
            
            # Thermal check
            thermal_throttle()
            model.learn(total_timesteps=timesteps, progress_bar=False)
            env.close()
        
        # Evaluate
        success_rate, avg_reward = evaluate_model(model, scene_path, base_port + stage_idx + 20)
        print(f"  📊 {stage_name}: success={success_rate*100:.0f}%, reward={avg_reward:.0f}")
        
        total_score += success_rate * 100
        
        # Save checkpoint
        model.save(f"{MODELS_DIR}/anna_v{variant_id}_{stage_name}", exclude=['policy.optimizer'])
    
    return total_score / len(SCENES)

def main():
    print("🌙 Overnight Training for Odisea Agent")
    print(f"=" * 60)
    print(f"Scenes: {[s[0] for s in SCENES]}")
    print(f"Population: {POPULATION}, Generations: {GENERATIONS}")
    print(f"Architecture: {BASE_ARCH}")
    print(f"Thermal limit: {TEMP_LIMIT}°C")
    print(f"=" * 60)
    
    # Check initial temp
    temp = get_cpu_temp()
    if temp:
        print(f"Initial CPU temp: {temp:.1f}°C")
    
    # Track best model
    best_score = -1
    best_variant = -1
    
    # Genetic algorithm
    for gen in range(GENERATIONS):
        print(f"\n{'#'*60}")
        print(f"🧬 GENERATION {gen+1}/{GENERATIONS}")
        print(f"{'#'*60}")
        
        for variant in range(POPULATION):
            variant_id = gen * POPULATION + variant
            
            # Create hyperparameters with mutation
            hyperparams = create_hyperparams(variant_id)
            
            # Run curriculum
            score = run_curriculum(variant_id, hyperparams)
            
            print(f"\n🏆 Variant {variant_id} (gen {gen}): score={score:.1f}")
            
            # Save if best
            if score > best_score:
                best_score = score
                best_variant = variant_id
                # Copy best model
                import shutil
                src = f"{MODELS_DIR}/anna_v{variant_id}_RL3_Door.zip"
                dst = f"{MODELS_DIR}/anna_best_overnight.zip"
                if os.path.exists(src):
                    shutil.copy(src, dst)
                    print(f"  ⭐ New best! Saved to {dst}")
        
        print(f"\n📊 Generation {gen+1} complete. Best: variant {best_variant} ({best_score:.1f})")
        
        # Save population summary
        with open(MODELS_DIR / "training_log.txt", "a") as f:
            f.write(f"Generation {gen+1}: best_variant={best_variant}, score={best_score}\n")
    
    print(f"\n🎉 Training complete!")
    print(f"Best variant: {best_variant} with score {best_score:.1f}")
    
    # Final evaluation
    if os.path.exists(f"{MODELS_DIR}/anna_best_overnight.zip"):
        print("\n📋 Final evaluation:")
        model = PPO.load(f"{MODELS_DIR}/anna_best_overnight.zip")
        
        for stage_name, scene_path, _ in SCENES:
            success, reward = evaluate_model(model, scene_path, 8999)
            print(f"  {stage_name}: {success*100:.0f}% success, {reward:.0f} avg reward")

if __name__ == '__main__':
    main()
