import gymnasium as gym
from gymnasium import spaces
import numpy as np
from anna_client import AnnaTCPClient

class OdiseaEnv(gym.Env):
    metadata = {"render_modes": ["human"], "render_fps": 30}

    def __init__(self, port=5000):
        super(OdiseaEnv, self).__init__()
        self.anna = AnnaTCPClient(port=port)
        self.anna.connect()

        # Action Space: 4 discrete actions
        # 0: Forward, 1: Back, 2: Left, 3: Right
        self.action_space = spaces.Discrete(4)

        # Observation Space: 10 values
        # 0-7: Raycasts (normalized 0-1)
        # 8: Target Distance (normalized 0-1, assuming max 100m)
        # 9: Target Angle (normalized -1 to 1)
        self.observation_space = spaces.Box(low=-1.0, high=1.0, shape=(10,), dtype=np.float32)

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)

        # Send RESET_EPISODE
        self.anna.send_action({"command": "RESET_EPISODE"})

        # Read new state (flush until we get a fresh frame?)
        # Actually receive_state waits for next packet.
        # But we might need to skip one if it was already in flight.
        # For PoC, just reading next is usually fine if step/reset are synchronous enough.

        raw_state = self.anna.receive_state()
        obs = self._process_observation(raw_state)
        return obs, {}

    def step(self, action):
        # Map Discrete action to Anna Input
        # 0: Forward -> move.y = -1
        # 1: Back -> move.y = 1
        # 2: Left -> move.x = -1
        # 3: Right -> move.x = 1

        move_vec = [0.0, 0.0]
        if action == 0: move_vec = [0.0, -1.0]
        elif action == 1: move_vec = [0.0, 1.0]
        elif action == 2: move_vec = [-1.0, 0.0]
        elif action == 3: move_vec = [1.0, 0.0]

        action_dict = {
            "move": move_vec,
            "look": [0.0, 0.0] # No look for now
        }

        self.anna.send_action(action_dict)

        raw_state = self.anna.receive_state()
        obs = self._process_observation(raw_state)

        reward = raw_state.get("reward", 0.0)
        terminated = raw_state.get("done", False)
        truncated = False

        return obs, reward, terminated, truncated, {}

    def _process_observation(self, raw_state):
        # Extract Raycasts (8)
        raycasts = raw_state.get("raycasts", [20.0]*8)
        # Normalize raycasts (0-20m -> 0-1)
        raycasts_norm = [min(r / 20.0, 1.0) for r in raycasts]

        # Extract Target Info
        target = raw_state.get("target", {"distance": 100.0, "angle": 0.0})
        dist_norm = min(target.get("distance", 100.0) / 100.0, 1.0)
        angle_norm = target.get("angle", 0.0) # Already -1 to 1

        obs_list = raycasts_norm + [dist_norm, angle_norm]

        # Ensure exact shape
        if len(obs_list) != 10:
            # Pad or trim if raycast count mismatches
            obs_list = obs_list[:10] + [0.0]*(10-len(obs_list))

        return np.array(obs_list, dtype=np.float32)

    def close(self):
        self.anna.disconnect()
