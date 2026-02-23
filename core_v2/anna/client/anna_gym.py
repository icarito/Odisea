import gymnasium as gym
from gymnasium import spaces
import numpy as np
import socket
import json
import subprocess
import os
import time
import shutil

class AnnaGymEnv(gym.Env):
    metadata = {"render_modes": ["human"], "render_fps": 60}

    def __init__(self, scene_path=None, port=5000, launch_godot=True, headless=True, godot_bin=None):
        self.port = port
        self.scene_path = scene_path
        self.launch_godot = launch_godot
        self.headless = headless
        self.godot_bin = godot_bin or os.environ.get("GODOT_BIN", "godot3-bin")
        self.godot_process = None
        self.sock = None
        self.buffer = ""

        # Action Space: 0=Idle, 1=Fwd, 2=Back, 3=Left, 4=Right
        self.action_space = spaces.Discrete(5)

        # Observation Space: 12 floats (normalized approx -1 to 1)
        self.observation_space = spaces.Box(
            low=-1.0, high=1.0, shape=(12,), dtype=np.float32
        )

        if self.launch_godot:
            self._launch_godot()

        # Connect logic handled on demand

    def _launch_godot(self):
        env = os.environ.copy()
        env["ANNA_RL_MODE"] = "1"
        env["ANNA_PORT"] = str(self.port)

        godot_bin = self.godot_bin
        if shutil.which(godot_bin) is None and godot_bin == "godot3-bin" and shutil.which("godot3"):
            godot_bin = "godot3"
            print("[AnnaGym] GODOT_BIN=godot3-bin not found, falling back to godot3.")

        cmd = []
        if self.headless:
            cmd = ["xvfb-run", "-a"]

        cmd.extend([godot_bin, "--no-window", "--audio-driver", "Dummy", "--path", "."])

        if self.scene_path:
            cmd.append(self.scene_path)

        print(f"[AnnaGym] Launching Godot: {' '.join(cmd)}")
        self.godot_process = subprocess.Popen(cmd, env=env)
        time.sleep(3) # Wait for engine start

    def _connect(self):
        if self.sock:
            return

        max_retries = 20
        for i in range(max_retries):
            try:
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.connect(("127.0.0.1", self.port))
                print("[AnnaGym] Connected to Godot ANNA Bridge.")
                return
            except ConnectionRefusedError:
                print(f"[AnnaGym] Connection refused, retrying ({i+1}/{max_retries})...")
                time.sleep(1)
            except Exception as e:
                print(f"[AnnaGym] Connection error: {e}")
                time.sleep(1)

        raise Exception("Could not connect to Godot.")

    def _send(self, data):
        if not self.sock:
            self._connect()
        try:
            msg = json.dumps(data) + "\n"
            self.sock.sendall(msg.encode('utf-8'))
        except (BrokenPipeError, OSError):
            print("[AnnaGym] Socket error while sending, attempting reconnect...")
            self.sock.close()
            self.sock = None
            self._connect()
            msg = json.dumps(data) + "\n"
            self.sock.sendall(msg.encode('utf-8'))

    def _recv(self):
        if not self.sock:
            self._connect() # Try reconnecting

        try:
            while "\n" not in self.buffer:
                chunk = self.sock.recv(4096)
                if not chunk:
                    raise Exception("Socket connection broken (Empty read)")
                self.buffer += chunk.decode('utf-8', errors='ignore')

            line, rest = self.buffer.split("\n", 1)
            self.buffer = rest
            if not line.strip():
                return self._recv() # Skip empty lines

            try:
                return json.loads(line)
            except json.JSONDecodeError:
                print(f"[AnnaGym] JSON Decode Error: {line}")
                return {"obs": [0.0]*12, "reward": 0.0, "done": True}

        except Exception as e:
            print(f"[AnnaGym] Recv Error: {e}")
            return {"obs": [0.0]*12, "reward": 0.0, "done": True}

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)

        # Send Reset Command
        self._send({"command": "RESET"})

        # Receive Initial Observation
        data = self._recv()
        obs = np.array(data.get("obs", np.zeros(12)), dtype=np.float32)
        info = {}

        return obs, info

    def step(self, action):
        # Send Action
        self._send({"action": int(action)})

        # Receive Result
        data = self._recv()

        obs = np.array(data.get("obs", np.zeros(12)), dtype=np.float32)
        reward = float(data.get("reward", 0.0))
        terminated = bool(data.get("done", False))
        truncated = False
        info = {}

        return obs, reward, terminated, truncated, info

    def close(self):
        if self.sock:
            self.sock.close()
        if self.godot_process:
            print("[AnnaGym] Terminating Godot process...")
            self.godot_process.terminate()
            try:
                self.godot_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.godot_process.kill()
