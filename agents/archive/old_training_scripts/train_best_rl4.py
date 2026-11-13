#!/usr/bin/env python3
"""Train best RL4 model with 13D observations (height)"""
import sys, os
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

# Best params from earlier (62.5% on RL4 without height!)
# With height (13D) we should do even better!

def main():
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    # RL2 first
    os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
    
    print("=== Training RL2 (150k steps) ===")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=30000, launch_godot=True, headless=True)
    print(f"Obs space: {env.observation_space.shape}")
    
    model = PPO('MlpPolicy', env,
                 n_steps=1024, batch_size=256, n_epochs=3,
                 learning_rate=6e-4, ent_coef=0.08,
                 policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])}, verbose=1)
    
    model.learn(total_timesteps=150000, progress_bar=True)
    model.save(f"{MODELS_DIR}/best13d_rl2", exclude=['policy.optimizer'])
    env.close()
    
    # RL4
    print("\n=== Training RL4 (800k steps) ===")
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=30001, launch_godot=True, headless=True)
    model.set_env(env)
    model.learn(total_timesteps=800000, progress_bar=True)
    model.save(f"{MODELS_DIR}/best13d_rl4", exclude=['policy.optimizer'])
    env.close()
    
    # Eval at 60fps
    os.environ['ANNA_RL_PHYSICS_FPS'] = '60'
    env = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=30002, launch_godot=True, headless=True)
    
    success = 0
    for ep in range(10):
        obs, _ = env.reset()
        done = False
        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, _ = env.step(int(action))
            done = terminated or truncated
            if terminated and reward > 0:
                success += 1
                print(f"Ep {ep+1}: SUCCESS")
                break
        else:
            print(f"Ep {ep+1}: FAIL")
    
    env.close()
    print(f"\n=== RL4 Result: {success}/10 = {success*10}% ===")

if __name__ == '__main__':
    main()
