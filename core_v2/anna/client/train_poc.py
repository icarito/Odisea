import gymnasium as gym
from stable_baselines3 import PPO
from anna_gym import AnnaGymEnv
import os
import sys

def main():
    # Assume script is run from repo root, so path is relative to root
    scene_path = "core_v2/tests/TestScene_RL.tscn"
    print(f"Starting training with scene: {scene_path}")

    # Create environment
    # Use xvfb-run in wrapper, so just pass launch_godot=True
    env = AnnaGymEnv(scene_path=scene_path, port=5000, launch_godot=True, headless=True)

    try:
        model = PPO("MlpPolicy", env, verbose=1)
        print("Model created. Starting learning...")
        model.learn(total_timesteps=2000)
        print("Training finished.")

        model.save("ppo_anna_poc")
        print("Model saved to ppo_anna_poc.zip")

    except Exception as e:
        print(f"Training failed: {e}")
        import traceback
        traceback.print_exc()
    finally:
        env.close()

if __name__ == "__main__":
    main()
