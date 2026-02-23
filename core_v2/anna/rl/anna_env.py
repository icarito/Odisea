import gymnasium as gym
from gymnasium import spaces
import numpy as np
import socket
import json
import time
import os

class AnnaEnv(gym.Env):
    """
    Custom Environment that follows gym interface.
    Connects to Godot A.N.N.A agent via TCP.
    """
    metadata = {'render_modes': ['human']}

    def __init__(self, host='127.0.0.1', port=5000, max_steps=1000):
        super(AnnaEnv, self).__init__()

        self.host = host
        self.port = port
        self.max_steps = max_steps
        self.socket = None

        # Define action and observation space
        # Actions: 0=Brake, 1=Fwd, 2=Back, 3=Left, 4=Right
        self.action_space = spaces.Discrete(5)

        # Observations: 12 floats
        # 0-7: Proximity (0-1)
        # 8: Dist to Target (0-1)
        # 9: Angle to Target (-1 to 1)
        # 10: Vel Fwd (-1 to 1)
        # 11: Vel Side (-1 to 1)
        self.observation_space = spaces.Box(low=-1.0, high=1.0, shape=(12,), dtype=np.float32)

        self.current_step = 0

    def _connect(self):
        if self.socket:
            return

        print(f"[AnnaEnv] Connecting to {self.host}:{self.port}...")
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.settimeout(5.0) # 5 seconds timeout

        retry_count = 0
        while retry_count < 10:
            try:
                self.socket.connect((self.host, self.port))
                print("[AnnaEnv] Connected.")
                return
            except Exception as e:
                print(f"[AnnaEnv] Connection failed ({e}), retrying...")
                time.sleep(1)
                retry_count += 1

        raise ConnectionError("Could not connect to Godot AnnaBridge.")

    def _send_command(self, cmd_dict):
        self._connect()
        try:
            msg = json.dumps(cmd_dict) + "\n"
            self.socket.sendall(msg.encode('utf-8'))

            # Read response (line delimited)
            # Simple buffering
            data = b""
            while True:
                chunk = self.socket.recv(4096)
                if not chunk:
                    raise ConnectionError("Socket closed remotely")
                data += chunk
                if b"\n" in data:
                    break

            line = data.split(b"\n")[0]
            return json.loads(line.decode('utf-8'))

        except Exception as e:
            print(f"[AnnaEnv] Communication error: {e}")
            self.close()
            raise e

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        self.current_step = 0

        try:
            resp = self._send_command({"type": "RESET"})
            obs = np.array(resp.get("obs", np.zeros(12)), dtype=np.float32)
            info = resp.get("info", {})
            return obs, info
        except Exception as e:
            print(f"[AnnaEnv] Reset failed: {e}. Returning safe zero tensor.")
            return np.zeros(12, dtype=np.float32), {"error": str(e)}

    def step(self, action):
        self.current_step += 1

        cmd = {
            "type": "STEP",
            "action": int(action)
        }

        try:
            resp = self._send_command(cmd)

            obs = np.array(resp.get("obs", np.zeros(12)), dtype=np.float32)
            reward = float(resp.get("reward", 0.0))
            done = bool(resp.get("done", False))
            info = resp.get("info", {})

            truncated = False
            if self.current_step >= self.max_steps:
                truncated = True

            return obs, reward, done, truncated, info

        except Exception as e:
            print(f"[AnnaEnv] Step failed: {e}. Returning safe zero tensor and Done.")
            # Return safe zero tensor, 0 reward, and Done=True to trigger reset
            return np.zeros(12, dtype=np.float32), 0.0, True, False, {"error": str(e)}

    def close(self):
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
