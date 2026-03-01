#!/usr/bin/env python3
"""
SMART PARALLEL TRAINING SYSTEM
- Multiple parallel environments (4 workers)
- godot3-server auto-detects drivers
- Progressive curriculum: RL -> RL2 -> RL3_Door
- Domain randomization
- Best model tracking
"""

import sys
import os
import time
import random
import shutil
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
from multiprocessing import Process, Queue

sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO
import numpy as np

MODELS_DIR = Path('agents/models')
MODELS_DIR.mkdir(exist_ok=True)

# === CONFIG ===
NUM_PARALLEL_ENVS = 4
PHYSICS_FPS = 2000  # Good balance of speed/stability

# Curriculum with proper progression
CURRICULUM = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', {
        'timesteps': 40000,
        'max_steps': 800,
        'spawn_range': 20,
    }),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', {
        'timesteps': 60000,
        'max_steps': 1000,
        'spawn_range': 25,
    }),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', {
        'timesteps': 100000,
        'max_steps': 1400,
        'spawn_range': 15,
    }),
]

# Variants to try
VARIANTS = [
    {'name': 'baseline', 'lr': 3e-4, 'ent': 0.02, 'gamma': 0.99, 'arch': [128, 128]},
    {'name': 'explorer', 'lr': 5e-4, 'ent': 0.08, 'gamma': 0.99, 'arch': [128, 128]},
    {'name': 'cautious', 'lr': 2e-4, 'ent': 0.05, 'gamma': 0.995, 'arch': [128, 128]},
    {'name': 'deep', 'lr': 3e-4, 'ent': 0.03, 'gamma': 0.99, 'arch': [128, 128, 64]},
]

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp') as f:
            return int(f.read()) / 1000.0
    except:
        return None

def evaluate_agent(model, scene_path, port, episodes=5):
    """Evaluate agent success rate."""
    env = AnnaGymEnv(scene_path=scene_path, port=port, launch_godot=True, headless=True)
    
    successes = 0
    total_reward = 0
    min_dists = []
    
    for ep in range(episodes):
        obs, _ = env.reset()
        done = False
        steps = 0
        min_dist = 100
        
        while not done and steps < 1500:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            steps += 1
            
            # Track min distance
            dist = obs[8] * 50  # Denormalize
            if dist < min_dist:
                min_dist = dist
            
            if terminated:
                if reward > 0:
                    successes += 1
                break
        
        total_reward += reward
        min_dists.append(min_dist)
    
    env.close()
    
    return {
        'success_rate': successes / episodes,
        'avg_reward': total_reward / episodes,
        'avg_min_dist': np.mean(min_dists),
    }

def train_single_variant(variant_config, variant_idx):
    """Train one variant through full curriculum."""
    base_port = 7100 + variant_idx * 100
    
    print(f"\n{'='*60}")
    print(f"🧬 Training: {variant_config['name']}")
    print(f"{'='*60}")
    
    # Start with RL (simplest)
    env = AnnaGymEnv(
        scene_path=CURRICULUM[0][1],
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
        gamma=variant_config['gamma'],
        policy_kwargs={'net_arch': dict(pi=variant_config['arch'], vf=variant_config['arch'])},
        verbose=0,
    )
    
    scores = {}
    start_time = time.time()
    
    for stage_idx, (stage_name, scene_path, config) in enumerate(CURRICULUM):
        print(f"\n📚 {variant_config['name']} -> {stage_name}")
        
        # Train
        model.learn(total_timesteps=config['timesteps'], progress_bar=True)
        
        # Save checkpoint
        ckpt_path = f"{MODELS_DIR}/anna_{variant_config['name']}_{stage_name}.zip"
        model.save(ckpt_path, exclude=['policy.optimizer'])
        
        # Evaluate
        eval_port = base_port + 50
        result = evaluate_agent(model, scene_path, eval_port)
        
        scores[stage_name] = result['success_rate']
        
        print(f"  📊 {stage_name}: {result['success_rate']*100:.0f}% success, "
              f"avg_min_dist={result['avg_min_dist']:.1f}m")
        
        # Continue to next stage
        if stage_idx < len(CURRICULUM) - 1:
            env.close()
            next_port = base_port + stage_idx + 1
            env = AnnaGymEnv(
                scene_path=CURRICULUM[stage_idx+1][1],
                port=next_port,
                launch_godot=True,
                headless=True
            )
            model.set_env(env)
    
    env.close()
    
    elapsed = time.time() - start_time
    
    # Calculate overall score (weighted)
    score = (
        scores.get('RL', 0) * 15 +
        scores.get('RL2', 0) * 25 +
        scores.get('RL3_Door', 0) * 60
    )
    
    print(f"\n✅ {variant_config['name']} complete in {elapsed/60:.1f}min")
    print(f"   RL: {scores.get('RL',0)*100:.0f}% | RL2: {scores.get('RL2',0)*100:.0f}% | RL3_Door: {scores.get('RL3_Door',0)*100:.0f}%")
    
    return {
        'name': variant_config['name'],
        'scores': scores,
        'score': score,
        'elapsed': elapsed,
    }

def train_worker(variant_config, variant_idx, result_queue):
    """Worker process for parallel training."""
    try:
        result = train_single_variant(variant_config, variant_idx)
        result_queue.put(('success', result))
    except Exception as e:
        result_queue.put(('error', str(e)))

def main():
    print("🚀 SMART PARALLEL TRAINING SYSTEM")
    print("=" * 60)
    print(f"Parallel envs: {NUM_PARALLEL_ENVS}")
    print(f"Physics FPS: {PHYSICS_FPS}")
    print(f"Variants: {[v['name'] for v in VARIANTS]}")
    print(f"Curriculum: {[c[0] for c in CURRICULUM]}")
    print("=" * 60)
    
    # Set environment
    os.environ['ANNA_RL_PHYSICS_FPS'] = str(PHYSICS_FPS)
    os.environ['ANNA_RL_TARGET_FPS'] = str(PHYSICS_FPS)
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    
    all_results = []
    best_score = 0
    best_name = None
    
    # Train variants in parallel (2 at a time to not overwhelm)
    for batch_start in range(0, len(VARIANTS), 2):
        batch = VARIANTS[batch_start:batch_start+2]
        
        print(f"\n{'#'*60}")
        print(f"📦 Batch: {[v['name'] for v in batch]}")
        print(f"{'#'*60}")
        
        # Run batch in parallel
        result_queue = Queue()
        workers = []
        
        for idx, variant in enumerate(batch):
            worker = Process(target=train_worker, args=(variant, batch_start + idx, result_queue))
            worker.start()
            workers.append(worker)
        
        # Wait for batch to complete
        for worker in workers:
            worker.join()
        
        # Collect results
        while not result_queue.empty():
            status, data = result_queue.get()
            if status == 'success':
                all_results.append(data)
                
                if data['score'] > best_score:
                    best_score = data['score']
                    best_name = data['name']
                    
                    # Save as best
                    src = f"{MODELS_DIR}/anna_{data['name']}_RL3_Door.zip"
                    dst = f"{MODELS_DIR}/anna_best_parallel.zip"
                    if os.path.exists(src):
                        shutil.copy(src, dst)
                        print(f"\n⭐ New best: {data['name']} (score: {data['score']:.1f})")
            else:
                print(f"❌ Error: {data}")
        
        # Thermal check between batches
        temp = get_cpu_temp()
        if temp:
            print(f"\n🌡️  CPU: {temp:.1f}°C")
            if temp > 85:
                print("⏸️  Cooling down...")
                time.sleep(30)
    
    # Final summary
    print("\n" + "="*60)
    print("📊 FINAL RESULTS")
    print("="*60)
    
    for result in sorted(all_results, key=lambda x: x['score'], reverse=True):
        s = result['scores']
        print(f"{result['name']:15s}: RL={s.get('RL',0)*100:5.0f}% | RL2={s.get('RL2',0)*100:5.0f}% | RL3_Door={s.get('RL3_Door',0)*100:5.0f}% | {result['elapsed']/60:.1f}min")
    
    print(f"\n🏆 Best: {best_name} (score: {best_score:.1f})")
    print(f"Model: {MODELS_DIR}/anna_best_parallel.zip")
    
    # Log
    with open(MODELS_DIR / "training_log.txt", "w") as f:
        f.write(f"Training completed at {time.strftime('%Y-%m-%d %H:%M')}\n")
        for result in all_results:
            f.write(f"{result['name']}: {result['scores']}\n")
        f.write(f"Best: {best_name}\n")

if __name__ == '__main__':
    main()
