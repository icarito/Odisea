#!/usr/bin/env python3
"""
PROPER TRAINING - Extended curriculum
- More time on RL and RL2
- Evaluate at 60Hz
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

# 60 FPS for evaluation
EVAL_FPS = 60

# EXTENDED curriculum - much more on early stages
STAGES = [
    ('RL', 'core_v2/tests/TestScene_RL.tscn', {
        'train_steps': 100000,  # A lot of RL
        'eval_max': 600,
    }),
    ('RL2', 'core_v2/tests/TestScene_RL_2.tscn', {
        'train_steps': 150000,  # A lot of RL2
        'eval_max': 900,
    }),
    ('RL3_Door', 'core_v2/tests/TestScene_RL_3_Door.tscn', {
        'train_steps': 150000,  # RL3_Door last
        'eval_max': 1400,
    }),
]

VARIANTS = [
    {'name': 'std', 'lr': 3e-4, 'ent': 0.02, 'arch': [128, 128]},
    {'name': 'explorer', 'lr': 5e-4, 'ent': 0.05, 'arch': [128, 128]},
]

def get_cpu_temp():
    try:
        with open('/sys/class/thermal/thermal_zone0/temp') as f:
            return int(f.read()) / 1000.0
    except:
        return None

def evaluate_at_60hz(model, scene_path, port, episodes=5):
    """Evaluate at 60 FPS for accurate results."""
    # Force 60 FPS evaluation
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    os.environ['ANNA_RL_TARGET_FPS'] = '60'
    
    env = AnnaGymEnv(scene_path=scene_path, port=port, launch_godot=True, headless=True)
    
    successes = 0
    rewards = []
    
    for ep in range(episodes):
        obs, _ = env.reset()
        done = False
        steps = 0
        
        while not done and steps < 1500:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            steps += 1
            
            if terminated:
                if reward > 0:
                    successes += 1
                break
        
        rewards.append(reward)
    
    env.close()
    
    return {
        'success_rate': successes / episodes,
        'avg_reward': np.mean(rewards),
    }

def train_variant(variant, idx):
    """Train one variant with proper curriculum."""
    base_port = 7300 + idx * 100
    
    print(f"\n{'='*60}")
    print(f"🧬 {variant['name']}")
    print(f"{'='*60}")
    
    # Training FPS - can be high
    os.environ['ANNA_RL_PHYSICS_FPS'] = '3000'
    os.environ['ANNA_RL_TARGET_FPS'] = '3000'
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
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
    
    for stage_idx, (name, path, config) in enumerate(STAGES):
        print(f"\n📚 {name} - {config['train_steps']} steps")
        
        # Train
        start = time.time()
        model.learn(total_timesteps=config['train_steps'], progress_bar=True)
        train_time = time.time() - start
        
        # Save checkpoint
        model.save(f"{MODELS_DIR}/anna_{variant['name']}_{name}", exclude=['policy.optimizer'])
        
        # Evaluate at 60 FPS
        eval_port = base_port + 50
        result = evaluate_at_60hz(model, path, eval_port)
        
        scores[name] = result['success_rate']
        
        print(f"  ⏱️  {train_time:.0f}s | 📊 {name}: {result['success_rate']*100:.0f}% success")
        
        # Move to next stage
        if stage_idx < len(STAGES) - 1:
            env.close()
            env = AnnaGymEnv(scene_path=path, port=base_port + stage_idx + 1, launch_godot=True, headless=True)
            model.set_env(env)
    
    env.close()
    
    print(f"\n✅ {variant['name']}: RL={scores.get('RL',0)*100:.0f}% RL2={scores.get('RL2',0)*100:.0f}% RL3_Door={scores.get('RL3_Door',0)*100:.0f}%")
    
    return {'name': variant['name'], 'scores': scores}

def main():
    print("🚀 PROPER TRAINING - Extended Curriculum")
    print(f"=" * 50)
    print(f"RL: {STAGES[0][2]['train_steps']} steps")
    print(f"RL2: {STAGES[1][2]['train_steps']} steps")
    print(f"RL3_Door: {STAGES[2][2]['train_steps']} steps")
    print(f"Eval at: {EVAL_FPS} FPS")
    print("=" * 50)
    
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    
    results = []
    
    for idx, variant in enumerate(VARIANTS):
        result = train_variant(variant, idx)
        results.append(result)
        
        # Save best
        if result['scores'].get('RL3_Door', 0) > 0:
            src = f"{MODELS_DIR}/anna_{result['name']}_RL3_Door.zip"
            dst = f"{MODELS_DIR}/anna_best_proper.zip"
            if os.path.exists(src):
                shutil.copy(src, dst)
        
        temp = get_cpu_temp()
        if temp:
            print(f"🌡️  CPU: {temp:.1f}°C")
    
    # Summary
    print("\n" + "="*50)
    print("📊 FINAL RESULTS (evaluated at 60 FPS)")
    print("="*50)
    for r in results:
        s = r['scores']
        print(f"{r['name']:10s}: RL={s.get('RL',0)*100:5.0f}% RL2={s.get('RL2',0)*100:5.0f}% RL3_Door={s.get('RL3_Door',0)*100:5.0f}%")

if __name__ == '__main__':
    main()
