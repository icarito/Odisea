#!/usr/bin/env python3
"""Full curriculum: RL -> RL2 -> RL3_Door -> RL4 with max CPU"""
import sys, os
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

def main():
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
    
    print("=== Full Curriculum: RL -> RL2 -> RL3_Door -> RL4 ===")
    print("Best params: lr=6e-4, ent=0.08, arch=[128,128]")
    
    # RL (flat)
    print("\n[1/4] RL (50k steps)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL.tscn', port=40000, launch_godot=True, headless=True)
    model = PPO('MlpPolicy', env, n_steps=1024, batch_size=256, n_epochs=3,
                 learning_rate=6e-4, ent_coef=0.08,
                 policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])}, verbose=0)
    model.learn(total_timesteps=50000, progress_bar=True)
    model.save(f"{MODELS_DIR}/curr_rl", exclude=['policy.optimizer'])
    env.close()
    
    # RL2
    print("\n[2/4] RL2 (100k steps)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=40001, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=100000, progress_bar=True)
    model.save(f"{MODELS_DIR}/curr_rl2", exclude=['policy.optimizer'])
    env.close()
    
    # RL3_Door
    print("\n[3/4] RL3_Door (200k steps)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_3_Door.tscn', port=40002, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=200000, progress_bar=True)
    model.save(f"{MODELS_DIR}/curr_rl3_door", exclude=['policy.optimizer'])
    env.close()
    
    # RL4 - longer episodes
    print("\n[4/4] RL4 (500k steps, longer max_steps)")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=40003, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=500000, progress_bar=True)
    model.save(f"{MODELS_DIR}/curr_rl4", exclude=['policy.optimizer'])
    env.close()
    
    # Eval at 60fps
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    print("\n=== Evaluation at 60 FPS ===")
    
    for scene, name in [('TestScene_RL_2', 'RL2'), 
                        ('TestScene_RL_3_Door', 'RL3_Door'),
                        ('TestScene_RL_4_TwoFloorRoom', 'RL4')]:
        env = AnnaGymEnv(f'core_v2/tests/{scene}.tscn', port=40010, launch_godot=True, headless=True)
        s = 0
        for ep in range(10):
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
        print(f"{name}: {s}/10 = {s*10}%")

if __name__ == '__main__':
    main()
