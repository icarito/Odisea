import gymnasium as gym
from stable_baselines3 import PPO
from anna_gym_env import OdiseaEnv
import os

def main():
    # Ensure log directory exists
    log_dir = "./odisea_tensorboard/"
    os.makedirs(log_dir, exist_ok=True)

    # 1. Instantiate the environment connected to Godot
    print("Connecting to Godot environment...")
    try:
        env = OdiseaEnv()
    except ConnectionError as e:
        print(f"Failed to connect: {e}")
        print("Make sure Godot is running with ANNA enabled.")
        return

    # 2. Initialize the PPO model
    # MlpPolicy uses a simple feed-forward neural network
    model = PPO("MlpPolicy", env, verbose=1, tensorboard_log=log_dir)

    # 3. Start training loop
    # For PoC, we use a small number of steps
    total_timesteps = 1000
    print(f"Starting training for {total_timesteps} steps...")

    try:
        model.learn(total_timesteps=total_timesteps)

        # 4. Save the trained brain
        model.save("odisea_generic_agent")
        print("Model saved successfully.")

    except KeyboardInterrupt:
        print("Training interrupted.")
        model.save("odisea_generic_agent_interrupted")
        print("Saved interrupted model.")
    except Exception as e:
        print(f"Training failed: {e}")
    finally:
        env.close()

if __name__ == "__main__":
    main()
