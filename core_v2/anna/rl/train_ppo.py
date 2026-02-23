import gymnasium as gym
from stable_baselines3 import PPO
from stable_baselines3.common.env_util import make_vec_env
from stable_baselines3.common.monitor import Monitor
from stable_baselines3.common.callbacks import CheckpointCallback
import os
import sys

# Ensure correct path to access core_v2
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../")))

from core_v2.anna.rl.anna_env import AnnaEnv

def main():
    # Create environment
    env = AnnaEnv(max_steps=500)
    # env = Monitor(env) # Monitor handled by make_vec_env usually or manual wrapper

    # Instantiate the agent
    model = PPO("MlpPolicy", env, verbose=1, tensorboard_log="./anna_tensorboard/")

    print("Starting training...")
    # Train the agent
    try:
        model.learn(total_timesteps=10000, progress_bar=True)
    except KeyboardInterrupt:
        print("Training interrupted.")
    except Exception as e:
        print(f"Training failed: {e}")

    print("Saving model...")
    model.save("anna_ppo_poc")

    print("Closing environment...")
    env.close()
    print("Done.")

if __name__ == "__main__":
    main()
