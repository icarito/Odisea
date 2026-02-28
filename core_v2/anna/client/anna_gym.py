import gymnasium as gym
from gymnasium import spaces
import numpy as np
import socket
import json
import subprocess
import os
import time
import shutil
import signal
import random
import struct
from typing import Optional

class AnnaGymEnv(gym.Env):
    metadata = {"render_modes": ["human"], "render_fps": 60}

    def __init__(
        self,
        scene_path=None,
        port=5000,
        launch_godot=True,
        headless=True,
        godot_bin=None,
        auto_relaunch_on_disconnect: Optional[bool] = None,
    ):
        self.port = port
        self.scene_path = scene_path
        self.launch_godot = launch_godot
        self.headless = headless
        env_godot_bin = os.environ.get("ANNA_GODOT_BIN") or os.environ.get("GODOT_BIN")
        default_godot_bin = "godot3-server" if headless else "godot3-bin"
        self.godot_bin = godot_bin or env_godot_bin or default_godot_bin
        self.video_driver = os.environ.get("ANNA_GODOT_VIDEO_DRIVER", "GLES2")
        self.audio_driver = str(os.environ.get("ANNA_GODOT_AUDIO_DRIVER", "Dummy")).strip()
        self.disable_audio_driver_flag = str(os.environ.get("ANNA_GODOT_DISABLE_AUDIO_DRIVER_FLAG", "0")).lower() in ("1", "true", "yes", "on")
        self.prefer_server_bin = str(os.environ.get("ANNA_GODOT_PREFER_SERVER", "1")).lower() not in ("0", "false", "no")
        self.require_server_bin = str(os.environ.get("ANNA_GODOT_REQUIRE_SERVER", "1")).lower() not in ("0", "false", "no")
        # For godot3-server, don't force --video-driver by default.
        # Some setups perform better when this flag is omitted entirely.
        self.server_video_driver = str(os.environ.get("ANNA_GODOT_SERVER_VIDEO_DRIVER", "")).strip()
        self.disable_render_loop = str(os.environ.get("ANNA_GODOT_DISABLE_RENDER_LOOP", "1")).lower() not in ("0", "false", "no")
        # Keep empty by default. Passing --max-fps 0 to godot3-server can cap RL throughput hard.
        self.godot_max_fps = str(os.environ.get("ANNA_GODOT_MAX_FPS", "")).strip()
        self.godot_quiet = str(os.environ.get("ANNA_GODOT_QUIET", "1")).lower() not in ("0", "false", "no")
        self.use_binary_protocol = str(os.environ.get("ANNA_RL_BINARY_PROTOCOL", "0")).lower() not in ("0", "false", "no")
        self.godot_process = None
        self.sock = None
        self.buffer = ""
        self.max_recovery_attempts = 3
        self._connect_max_retries = max(5, int(os.environ.get("ANNA_CONNECT_MAX_RETRIES", "60")))
        self._connect_retry_delay_sec = max(0.1, float(os.environ.get("ANNA_CONNECT_RETRY_DELAY_SEC", "1.0")))
        self._launch_ready_timeout_sec = max(5.0, float(os.environ.get("ANNA_GODOT_READY_TIMEOUT_SEC", "45.0")))
        self._launch_stagger_sec = max(0.0, float(os.environ.get("ANNA_GODOT_LAUNCH_STAGGER_SEC", "0.35")))
        self._allow_server_fallback = str(os.environ.get("ANNA_GODOT_SERVER_FALLBACK", "0")).lower() not in ("0", "false", "no")
        if auto_relaunch_on_disconnect is None:
            self.auto_relaunch_on_disconnect = str(os.environ.get("ANNA_GODOT_AUTO_RELAUNCH", "1")).lower() not in ("0", "false", "no")
        else:
            self.auto_relaunch_on_disconnect = bool(auto_relaunch_on_disconnect)

        # Action Space:
        # Compact action set (steering is assisted in-engine):
        # 0=SteerOnly (contextual INTERACT when an interactable is in front/in range)
        # 1=Forward
        # 2=SprintForward
        # 3=JumpForward
        # 4=StrafeLeft
        # 5=StrafeRight
        # 6=JumpStrafeLeft
        # 7=JumpStrafeRight
        self.action_space = spaces.Discrete(8)

        # Observation Space: 12 floats (normalized approx -1 to 1)
        self.observation_space = spaces.Box(
            low=-1.0, high=1.0, shape=(12,), dtype=np.float32
        )

        # If we are launching Godot ourselves, avoid attaching to a stale bridge process.
        if self.launch_godot and self._is_port_busy(self.port):
            new_port = self._find_free_port(start=self.port + 1)
            if new_port is None:
                raise RuntimeError(
                    f"[AnnaGym] Port {self.port} is busy and no free nearby port was found."
                )
            print(f"[AnnaGym] Port {self.port} busy, switching to free port {new_port}.")
            self.port = new_port

        if self.launch_godot:
            self._launch_godot()

        # Connect logic handled on demand

    def _resolve_godot_binary(self) -> str:
        candidate = str(self.godot_bin).strip() or "godot3-bin"
        if self.headless and self.prefer_server_bin:
            server_candidates = []
            if candidate:
                if candidate in ("godot3-bin", "godot3"):
                    server_candidates.append("godot3-server")
                elif candidate == "godot":
                    server_candidates.append("godot-server")
                elif candidate.endswith("-bin"):
                    server_candidates.append(candidate.replace("-bin", "-server"))
                else:
                    server_candidates.append(candidate + "-server")
            server_candidates.extend(["godot3-server", "godot-server", "godot_server"])
            for sc in server_candidates:
                if sc and shutil.which(sc):
                    print(f"[AnnaGym] Using headless server binary: {sc}")
                    return sc
        if not self.headless and "server" in os.path.basename(candidate):
            if shutil.which("godot3-bin"):
                print("[AnnaGym] Render mode requested; switching from server binary to godot3-bin.")
                candidate = "godot3-bin"
            elif shutil.which("godot3"):
                print("[AnnaGym] Render mode requested; switching from server binary to godot3.")
                candidate = "godot3"

        if shutil.which(candidate):
            return candidate
        if candidate == "godot3-bin" and shutil.which("godot3"):
            print("[AnnaGym] GODOT_BIN=godot3-bin not found, falling back to godot3.")
            return "godot3"
        if shutil.which("godot"):
            print("[AnnaGym] Falling back to godot.")
            return "godot"
        raise RuntimeError(f"[AnnaGym] Could not find Godot binary (requested: {candidate}).")

    def _launch_godot(self):
        attempted_server = False
        for launch_try in range(2):
            launched, used_server = self._launch_godot_once()
            if launched:
                return
            # If launch probe failed, do not leave orphaned processes alive
            # before attempting a fallback launch.
            self._terminate_godot_process()
            if used_server and self._allow_server_fallback and not attempted_server:
                attempted_server = True
                print("[AnnaGym] Headless server launch did not become ready. Falling back to regular Godot binary.")
                self.prefer_server_bin = False
                continue
            raise RuntimeError(f"[AnnaGym] Godot failed to become ready on port {self.port}.")

    def _launch_godot_once(self):
        env = os.environ.copy()
        # SessionManager only auto-injects AnnaBridge when this flag is set.
        # Keep it enabled to avoid launching without a bridge in non-RL scenes.
        env.setdefault("ANNA_ENABLED", "1")
        env["ANNA_RL_MODE"] = "1"
        env["ANNA_PORT"] = str(self.port)
        # Disable visual-only fake blob shadow in RL by default to reduce CPU raycast overhead.
        env.setdefault("ODISEA_DISABLE_FAKE_SHADOW", "1")
        # Disable heavy shader warmup/cache build in RL by default.
        env.setdefault("ODISEA_DISABLE_SHADER_WARMUP", "1")
        env.setdefault("ODISEA_DISABLE_SHADER_WARMUP_IN_RL", "1")
        # BaseTerrace includes QodotMap for editor workflows; disable runtime behavior in RL.
        env.setdefault("ANNA_RL_DISABLE_QODOT", "1")
        # Exit behavior on bridge disconnect:
        # - watch/no-relaunch sessions should quit Godot to avoid falling back to live gameplay.
        # - training/relaunch sessions should stay resilient and relaunch from client side.
        if "ANNA_RL_EXIT_ON_DISCONNECT" not in env:
            env["ANNA_RL_EXIT_ON_DISCONNECT"] = "1" if (self.launch_godot and not self.auto_relaunch_on_disconnect) else "0"
        env.setdefault("ANNA_RL_EXIT_ON_DISCONNECT_GRACE_MS", "1500")
        # Runtime defaults:
        # - Headless training: very high fixed physics rate for maximum SPS.
        # - Render/watch mode: human-speed physics so movement is not slow motion.
        if self.headless:
            env.setdefault("ANNA_RL_TARGET_FPS", "2000")
            env.setdefault("ANNA_RL_PHYSICS_FPS", "2000")
            env.setdefault("ANNA_RL_PHYSICS_FPS_CAP", "2000")
            env.setdefault("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME", "64")
        else:
            render_fps = str(os.environ.get("ANNA_RL_RENDER_PHYSICS_FPS", "60")).strip() or "60"
            env.setdefault("ANNA_RL_TARGET_FPS", render_fps)
            env.setdefault("ANNA_RL_PHYSICS_FPS", render_fps)
            env.setdefault("ANNA_RL_PHYSICS_FPS_CAP", render_fps)
            env.setdefault("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME", "8")
        env.setdefault("ANNA_RL_DISABLE_CPU_SLEEP", "1")
        env["ANNA_RL_BINARY_PROTOCOL"] = "1" if self.use_binary_protocol else "0"
        # Optional explicit override only; OYS_AUTO_RUN runs in CLI mode and can auto-quit.
        force_noop = str(env.get("ANNA_FORCE_OYS_NOOP", "0")).lower() in ("1", "true", "yes")
        if force_noop and ("OYS_AUTO_RUN" not in env or not str(env.get("OYS_AUTO_RUN", "")).strip()):
            env["OYS_AUTO_RUN"] = "res://core_v2/tests/anna_rl_noop.oys"

        godot_bin = self._resolve_godot_binary()
        is_server_bin = "server" in os.path.basename(godot_bin)
        if self.headless and self.require_server_bin and not is_server_bin:
            raise RuntimeError(
                "[AnnaGym] Headless RL requires godot3-server. "
                "Set GODOT_BIN=godot3-server (or disable ANNA_GODOT_REQUIRE_SERVER)."
            )

        cmd = []
        if self.headless and not is_server_bin:
            cmd = ["xvfb-run", "-a", "-s", "-screen 0 1024x768x24+120"]
            print(f"[AnnaGym] ⚠️  WARNING: using xvfb-run (software rendering likely). "
                  f"godot3-server not found. FPS will be ~500 instead of 2000+. "
                  f"Install godot3-server for GPU-speed training.")
        elif self.headless:
            print(f"[AnnaGym] ✅ Using server binary: {godot_bin} (headless, fast)")
        else:
            print(f"[AnnaGym] ✅ Using render binary: {godot_bin} (windowed mode)")

        cmd.extend([godot_bin, "--path", "."])
        if not self.disable_audio_driver_flag and self.audio_driver:
            cmd.extend(["--audio-driver", str(self.audio_driver)])
        if self.godot_max_fps:
            if is_server_bin and self.godot_max_fps == "0":
                print("[AnnaGym] ⚠️  ANNA_GODOT_MAX_FPS=0 limits godot3-server throughput; ignoring this value.")
            else:
                cmd.extend(["--max-fps", str(self.godot_max_fps)])
        if self.headless:
            if is_server_bin:
                if self.server_video_driver:
                    cmd.extend(["--video-driver", str(self.server_video_driver)])
            else:
                cmd.extend(["--video-driver", str(self.video_driver)])
                cmd.append("--no-window")
            if self.disable_render_loop:
                cmd.append("--disable-render-loop")
        if self.godot_quiet:
            cmd.append("--quiet")

        scene_arg = str(self.scene_path).strip() if self.scene_path else ""
        if scene_arg:
            cmd.append(self._resolve_scene_arg(scene_arg))

        print(f"[AnnaGym] Launching Godot: {' '.join(cmd)}")
        if self._launch_stagger_sec > 0.0:
            time.sleep(random.uniform(0.0, self._launch_stagger_sec))
        # Launch in its own process group so close() can terminate xvfb-run + Godot children reliably.
        self.godot_process = subprocess.Popen(cmd, env=env, start_new_session=True)
        ready = self._wait_for_bridge_ready(timeout_sec=self._launch_ready_timeout_sec)
        return ready, is_server_bin

    def _resolve_scene_arg(self, scene_arg: str) -> str:
        project_root = os.path.abspath(".")

        def _normalize_res(rel_path: str) -> str:
            rel = rel_path.lstrip("./").replace("\\", "/")
            return "res://" + rel

        def _exists_rel(rel_path: str) -> bool:
            rel = rel_path.lstrip("./")
            return os.path.exists(os.path.join(project_root, rel))

        raw = str(scene_arg).strip()
        if not raw:
            return raw

        attempts = []
        candidates = []

        if raw.startswith("res://"):
            rel = raw[len("res://"):].lstrip("/")
            candidates.append(rel)
        elif os.path.isabs(raw):
            if os.path.exists(raw):
                try:
                    rel = os.path.relpath(raw, project_root)
                    if not rel.startswith(".."):
                        return _normalize_res(rel)
                except Exception:
                    pass
                return raw
            attempts.append(raw)
            raise RuntimeError("[AnnaGym] Scene path does not exist: %s" % raw)
        else:
            candidates.append(raw.lstrip("./"))

        expanded = []
        for c in candidates:
            c = c.strip()
            if not c:
                continue
            expanded.append(c)
            if not c.endswith(".tscn"):
                expanded.append(c + ".tscn")
            if "/" not in c and "\\" not in c:
                expanded.append("core_v2/tests/" + c)
                expanded.append("scenes/" + c)
                if not c.endswith(".tscn"):
                    expanded.append("core_v2/tests/" + c + ".tscn")
                    expanded.append("scenes/" + c + ".tscn")

        seen = set()
        for rel in expanded:
            if rel in seen:
                continue
            seen.add(rel)
            attempts.append(rel)
            if _exists_rel(rel):
                return _normalize_res(rel)

        raise RuntimeError(
            "[AnnaGym] Could not resolve scene '%s'. Tried: %s"
            % (raw, ", ".join(attempts[:10]))
        )

    def _wait_for_bridge_ready(self, timeout_sec: float) -> bool:
        deadline = time.time() + max(1.0, float(timeout_sec))
        while time.time() < deadline:
            if self._is_port_busy(self.port):
                return True
            if self.godot_process and self.godot_process.poll() is not None:
                code = self.godot_process.returncode
                print(f"[AnnaGym] Godot process exited early (code={code}) before bridge was ready.")
                return False
            time.sleep(0.2)
        print(f"[AnnaGym] Timed out waiting for ANNA bridge on port {self.port}.")
        return False

    def _close_socket(self):
        if self.sock:
            try:
                self.sock.close()
            except Exception:
                pass
        self.sock = None
        self.buffer = ""

    def _terminate_godot_process(self):
        if not self.godot_process:
            return
        print("[AnnaGym] Terminating Godot process...")
        try:
            pgid = os.getpgid(self.godot_process.pid)
            os.killpg(pgid, signal.SIGTERM)
        except Exception:
            try:
                self.godot_process.terminate()
            except Exception:
                pass
        try:
            self.godot_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                pgid = os.getpgid(self.godot_process.pid)
                os.killpg(pgid, signal.SIGKILL)
            except Exception:
                try:
                    self.godot_process.kill()
                except Exception:
                    pass
        except Exception:
            pass
        self.godot_process = None

    def _is_godot_alive(self) -> bool:
        if not self.godot_process:
            return False
        return self.godot_process.poll() is None

    @staticmethod
    def _is_port_busy(port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.25)
            return s.connect_ex(("127.0.0.1", int(port))) == 0

    @staticmethod
    def _find_free_port(start: int = 5001, attempts: int = 200) -> Optional[int]:
        for p in range(int(start), int(start) + int(attempts)):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                try:
                    s.bind(("127.0.0.1", p))
                    return p
                except OSError:
                    continue
        return None

    def _connect(self):
        if self.sock:
            return

        for i in range(self._connect_max_retries):
            try:
                self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                self.sock.settimeout(5.0)
                self.sock.connect(("127.0.0.1", self.port))
                print("[AnnaGym] Connected to Godot ANNA Bridge.")
                return
            except ConnectionRefusedError:
                print(f"[AnnaGym] Connection refused, retrying ({i+1}/{self._connect_max_retries})...")
                self._close_socket()
                time.sleep(self._connect_retry_delay_sec)
            except Exception as e:
                print(f"[AnnaGym] Connection error: {e}")
                self._close_socket()
                time.sleep(self._connect_retry_delay_sec)

        raise Exception("Could not connect to Godot.")

    def _recover_bridge(self, reason: str):
        print(f"[AnnaGym] Recovering bridge ({reason})")
        self._close_socket()
        if self.launch_godot:
            if not self.auto_relaunch_on_disconnect:
                raise RuntimeError("[AnnaGym] Bridge disconnected and auto-relaunch is disabled.")
            if self._is_godot_alive():
                self._terminate_godot_process()
            self._launch_godot()
        self._connect()

    def _send_once(self, data):
        if not self.sock:
            self._connect()
        msg = json.dumps(data) + "\n"
        self.sock.sendall(msg.encode("utf-8"))

    def _recv_once(self):
        if not self.sock:
            self._connect()
        while True:
            while "\n" not in self.buffer:
                chunk = self.sock.recv(4096)
                if not chunk:
                    raise RuntimeError("Socket connection broken (empty read).")
                self.buffer += chunk.decode("utf-8", errors="ignore")
            line, rest = self.buffer.split("\n", 1)
            self.buffer = rest
            if not line.strip():
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                print(f"[AnnaGym] JSON Decode Error: {line}")
                return {"obs": [0.0] * 12, "reward": 0.0, "done": True}

    def _recv_exact(self, n_bytes: int) -> bytes:
        if not self.sock:
            self._connect()
        out = bytearray()
        while len(out) < n_bytes:
            chunk = self.sock.recv(n_bytes - len(out))
            if not chunk:
                raise RuntimeError("Socket connection broken (empty read).")
            out.extend(chunk)
        return bytes(out)

    def _recv_once_binary(self):
        # 12 obs float32 + reward float32 + done uint8
        raw = self._recv_exact(53)
        unpacked = struct.unpack(">13fB", raw)
        obs = list(unpacked[:12])
        reward = float(unpacked[12])
        done = bool(unpacked[13])
        return {"obs": obs, "reward": reward, "done": done}

    def _request(self, payload):
        last_error = None
        for attempt in range(self.max_recovery_attempts + 1):
            try:
                self._send_once(payload)
                return self._recv_once()
            except Exception as e:
                last_error = e
                print(f"[AnnaGym] transport error (attempt {attempt + 1}/{self.max_recovery_attempts + 1}): {e}")
                if attempt >= self.max_recovery_attempts:
                    break
                try:
                    self._recover_bridge(str(e))
                except Exception as recover_err:
                    last_error = recover_err
                    print(f"[AnnaGym] bridge recovery failed: {recover_err}")
                    break
        print(f"[AnnaGym] request failed after recovery attempts: {last_error}")
        return {"obs": [0.0] * 12, "reward": 0.0, "done": True, "__bridge_dead": True}

    def _request_binary(self, command_byte: int):
        last_error = None
        cmd = int(command_byte) & 0xFF
        for attempt in range(self.max_recovery_attempts + 1):
            try:
                if not self.sock:
                    self._connect()
                self.sock.sendall(bytes([cmd]))
                return self._recv_once_binary()
            except Exception as e:
                last_error = e
                print(f"[AnnaGym] transport error (binary attempt {attempt + 1}/{self.max_recovery_attempts + 1}): {e}")
                if attempt >= self.max_recovery_attempts:
                    break
                try:
                    self._recover_bridge(str(e))
                except Exception as recover_err:
                    last_error = recover_err
                    print(f"[AnnaGym] bridge recovery failed: {recover_err}")
                    break
        print(f"[AnnaGym] binary request failed after recovery attempts: {last_error}")
        return {"obs": [0.0] * 12, "reward": 0.0, "done": True, "__bridge_dead": True}

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)

        # Send Reset Command
        data = self._request_binary(255) if self.use_binary_protocol else self._request({"command": "RESET"})

        # Receive Initial Observation
        obs = np.array(data.get("obs", np.zeros(12)), dtype=np.float32)
        info = {
            "bridge_recovered": bool(data.get("done", False) and np.all(obs == 0.0)),
            "bridge_dead": bool(data.get("__bridge_dead", False)),
        }

        return obs, info

    def step(self, action):
        # Send Action
        data = self._request_binary(int(action)) if self.use_binary_protocol else self._request({"action": int(action)})

        obs = np.array(data.get("obs", np.zeros(12)), dtype=np.float32)
        reward = float(data.get("reward", 0.0))
        terminated = bool(data.get("done", False))
        truncated = False
        info = {
            "bridge_dead": bool(data.get("__bridge_dead", False)),
            "done_reason": str(data.get("done_reason", "unknown")),
        }

        return obs, reward, terminated, truncated, info

    def close(self):
        self._close_socket()
        self._terminate_godot_process()
