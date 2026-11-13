#!/usr/bin/env python3
import sys, os, time
sys.path.insert(0, 'core_v2/anna/client')
from anna_gym import AnnaGymEnv
from stable_baselines3 import PPO

MODELS_DIR = 'core_v2/trained_models'
os.makedirs(MODELS_DIR, exist_ok=True)

def main():
    print("Training new 13D model (RL2 -> RL4)")
    os.environ['OMP_NUM_THREADS'] = '8'
    os.environ['MKL_NUM_THREADS'] = '8'
    os.environ['ANNA_RL_DISABLE_CPU_SLEEP'] = '1'
    os.environ['ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG'] = '1'
    
    # 1. Train on RL2
    print("Step 1/2: Training on RL2 (150k steps)")
    env_rl2 = AnnaGymEnv('core_v2/tests/TestScene_RL_2.tscn', port=11000, launch_godot=True, headless=True)
    model = PPO('MlpPolicy', env_rl2, n_steps=1024, batch_size=256, n_epochs=3,
                learning_rate=5e-4, ent_coef=0.06,
                policy_kwargs={'net_arch': dict(pi=[128,128], vf=[128,128])}, verbose=1)
    
    model.learn(total_timesteps=10000, progress_bar=True)
    model.save(f"{MODELS_DIR}/final_rl2_13d", exclude=['policy.optimizer'])
    env_rl2.close()
    
    # 2. Train on RL4
    print("Step 2/2: Training on RL4 (500k steps)")
    os.environ['ANNA_RL_PHYSICS_FPS'] = '4000'
    env_rl4 = AnnaGymEnv('core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn', port=11010, launch_godot=True, headless=True)
    model.set_env(env_rl4)
    model.learn(total_timesteps=30000, progress_bar=True)
    model.save(f"{MODELS_DIR}/final_rl4_13d", exclude=['policy.optimizer'])
    env_rl4.close()
    print("Training complete! Model saved to final_rl4_13d.zip")

if __name__ == '__main__':
    main()
