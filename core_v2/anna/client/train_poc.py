from stable_baselines3 import PPO
from anna_gym import AnnaGymEnv
import os

def main():
    scene_path = os.environ.get("ANNA_SCENE", "core_v2/tests/TestScene_RL.tscn")
    port = int(os.environ.get("ANNA_PORT", "5000"))
    timesteps = int(os.environ.get("ANNA_TIMESTEPS", "2000"))
    print(f"Starting training with scene: {scene_path}")

    env = AnnaGymEnv(scene_path=scene_path, port=port, launch_godot=True, headless=True)

    try:
        model = PPO("MlpPolicy", env, verbose=1)
        print("Model created. Starting learning...")
        model.learn(total_timesteps=timesteps)
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
