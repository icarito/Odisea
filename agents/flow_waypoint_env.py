#!/usr/bin/env python3
"""Flow Waypoint observation and reward tracking for ANNA RL gyms.

Exposes ordered main-route waypoints (from FlowRouteValidator) as the active
navigation target (obs[8]=dist/50, obs[9]=angle/PI) and shaping reward
(progress toward next waypoint, backtrack penalty, and Side Socket diversion
penalty until the main route is exhausted).

Supports:
  1. `FlowWaypointTracker`: pure deterministic waypoint state machine.
  2. `FlowWaypointBifurcationEnv`: fast deterministic Gymnasium env (`obs13/act8`)
     modeling RingHub and MachineBay bifurcations (main route vs Side Sockets).
  3. `FlowWaypointGymWrapper`: Gymnasium wrapper for live `AnnaGymEnv` runs.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Sequence, Tuple

import gymnasium as gym
from gymnasium import spaces
import numpy as np


SENSOR_RANGE = 20.0
RL_MAX_VELOCITY = 20.0
RL_DIST_NORM = 50.0


def _to_vec3(p: Sequence[float]) -> np.ndarray:
    arr = np.asarray(p, dtype=np.float64)
    if arr.shape[0] == 2:
        return np.array([arr[0], 0.0, arr[1]], dtype=np.float64)
    return arr[:3].astype(np.float64)


def signed_angle_to_target(forward_xz: np.ndarray, to_target_xz: np.ndarray) -> float:
    """Signed angle in [-1, 1] matching AnnaInterface (-Z forward, +Y up)."""
    f = np.array([forward_xz[0], forward_xz[1]], dtype=np.float64)
    t = np.array([to_target_xz[0], to_target_xz[1]], dtype=np.float64)
    fn = np.linalg.norm(f)
    tn = np.linalg.norm(t)
    if fn < 1e-6 or tn < 1e-6:
        return 0.0
    f /= fn
    t /= tn
    dot = float(np.clip(np.dot(f, t), -1.0, 1.0))
    angle = math.acos(dot)
    # 3D cross(forward, to_target).y where forward=(fx,0,fz), to_target=(tx,0,tz):
    # cross.y = fz * tx - fx * tz
    cross_y = f[1] * t[0] - f[0] * t[1]
    if cross_y < 0.0:
        angle = -angle
    return float(np.clip(angle / math.pi, -1.0, 1.0))


@dataclass
class WaypointStepResult:
    wp_idx: int
    dist_to_wp: float
    angle_to_wp: float
    reward: float
    waypoint_reached: bool
    main_route_exhausted: bool
    side_socket_diversion: bool
    backtracking: bool


class FlowWaypointTracker:
    """Monotonic ordered-waypoint tracker with Side Socket & backtrack shaping."""

    def __init__(
        self,
        main_waypoints: Sequence[Sequence[float]],
        side_sockets: Sequence[Sequence[float]] = (),
        reach_radius: float = 2.0,
        socket_radius: float = 2.5,
        progress_scale: float = 1.5,
        waypoint_bonus: float = 4.0,
        route_complete_bonus: float = 15.0,
        backtrack_penalty: float = 0.6,
        side_socket_penalty: float = 3.0,
        side_socket_post_route_bonus: float = 1.0,
    ) -> None:
        if len(main_waypoints) < 1:
            raise ValueError("main_waypoints must contain at least one point.")
        self.main_waypoints: List[np.ndarray] = [_to_vec3(p) for p in main_waypoints]
        self.side_sockets: List[np.ndarray] = [_to_vec3(p) for p in side_sockets]
        self.reach_radius = float(reach_radius)
        self.socket_radius = float(socket_radius)
        self.progress_scale = float(progress_scale)
        self.waypoint_bonus = float(waypoint_bonus)
        self.route_complete_bonus = float(route_complete_bonus)
        self.backtrack_penalty = float(backtrack_penalty)
        self.side_socket_penalty = float(side_socket_penalty)
        self.side_socket_post_route_bonus = float(side_socket_post_route_bonus)

        self.wp_idx: int = 0
        self.main_route_exhausted: bool = False
        self.prev_dist_to_wp: Optional[float] = None
        self.prev_dist_to_prev_wp: Optional[float] = None
        self.visited_side_sockets: set = set()

    def reset(self, start_pos: Sequence[float]) -> Tuple[float, float]:
        pos = _to_vec3(start_pos)
        self.wp_idx = 0
        self.main_route_exhausted = False
        self.visited_side_sockets.clear()
        # If starting right on top of entry waypoint, advance to index 1 when available.
        if len(self.main_waypoints) > 1:
            d0 = float(np.linalg.norm(pos - self.main_waypoints[0]))
            if d0 <= self.reach_radius:
                self.wp_idx = 1
        self.prev_dist_to_wp = float(np.linalg.norm(pos - self.current_waypoint()))
        self.prev_dist_to_prev_wp = (
            float(np.linalg.norm(pos - self.main_waypoints[self.wp_idx - 1]))
            if self.wp_idx > 0
            else None
        )
        return self.prev_dist_to_wp, 0.0

    def current_waypoint(self) -> np.ndarray:
        return self.main_waypoints[self.wp_idx]

    def step(
        self,
        pos: Sequence[float],
        forward_xz: Sequence[float],
    ) -> WaypointStepResult:
        p = _to_vec3(pos)
        target = self.current_waypoint()
        delta = target - p
        dist = float(np.linalg.norm(delta))
        angle = signed_angle_to_target(
            np.asarray(forward_xz, dtype=np.float64),
            np.array([delta[0], delta[2]], dtype=np.float64),
        )

        reward = 0.0
        if self.prev_dist_to_wp is not None and not self.main_route_exhausted:
            reward += self.progress_scale * (self.prev_dist_to_wp - dist)

        # Detect backtracking toward previous cleared waypoint.
        backtracking = False
        if self.wp_idx > 0 and not self.main_route_exhausted:
            prev_wp = self.main_waypoints[self.wp_idx - 1]
            dist_prev = float(np.linalg.norm(p - prev_wp))
            if (
                self.prev_dist_to_prev_wp is not None
                and self.prev_dist_to_wp is not None
                and dist > self.prev_dist_to_wp + 0.02
                and dist_prev < self.prev_dist_to_prev_wp - 0.02
            ):
                backtracking = True
                reward -= self.backtrack_penalty
            self.prev_dist_to_prev_wp = dist_prev

        # Detect Side Socket diversion before main route is exhausted.
        side_socket_diversion = False
        for s_idx, sp in enumerate(self.side_sockets):
            if float(np.linalg.norm(p - sp)) <= self.socket_radius:
                if not self.main_route_exhausted:
                    side_socket_diversion = True
                    reward = min(reward, 0.0) - self.side_socket_penalty
                elif s_idx not in self.visited_side_sockets:
                    self.visited_side_sockets.add(s_idx)
                    reward += self.side_socket_post_route_bonus

        waypoint_reached = False
        if not self.main_route_exhausted and dist <= self.reach_radius:
            waypoint_reached = True
            reward += self.waypoint_bonus
            if self.wp_idx < len(self.main_waypoints) - 1:
                self.wp_idx += 1
                target = self.current_waypoint()
                delta = target - p
                dist = float(np.linalg.norm(delta))
                angle = signed_angle_to_target(
                    np.asarray(forward_xz, dtype=np.float64),
                    np.array([delta[0], delta[2]], dtype=np.float64),
                )
                self.prev_dist_to_prev_wp = float(
                    np.linalg.norm(p - self.main_waypoints[self.wp_idx - 1])
                )
            else:
                self.main_route_exhausted = True
                reward += self.route_complete_bonus

        self.prev_dist_to_wp = dist
        return WaypointStepResult(
            wp_idx=self.wp_idx,
            dist_to_wp=dist,
            angle_to_wp=angle,
            reward=reward,
            waypoint_reached=waypoint_reached,
            main_route_exhausted=self.main_route_exhausted,
            side_socket_diversion=side_socket_diversion,
            backtracking=backtracking,
        )


def _preset_config(preset: str) -> Dict[str, Any]:
    if preset == "ringhub_bifurcation":
        return {
            "start_pos": (20.0, 0.0, 0.0),
            "start_yaw": math.pi * 0.5,  # facing +Z around the ring
            "bounds": (-36.0, 36.0, -36.0, 36.0),
            "circles": [(0.0, 0.0, 13.0)],  # central HubRing obstacle
            "boxes": [],
            "main_waypoints": [
                (20.0, 0.0, 0.0),
                (14.0, 0.0, 14.0),   # bifurcation point
                (0.0, 0.0, 20.0),    # main route continues around ring
                (-14.0, 0.0, 14.0),
                (-20.0, 0.0, 0.0),   # exit
            ],
            "side_sockets": [
                (24.0, 0.0, 22.0),   # CuratedSocket off the bifurcation
            ],
            "max_steps": 450,
        }
    if preset == "machinebay_bifurcation":
        return {
            "start_pos": (0.0, 0.0, -2.0),
            "start_yaw": math.pi,  # facing +Z down the corridor (-Z is yaw=0)
            "bounds": (-8.0, 8.0, -6.0, 92.0),
            "circles": [],
            # Alternating station blocks matching TestScene_RL_MachineBayCorridor
            "boxes": [
                (-5.5, 8.0, 2.5, 3.0),
                (5.5, 28.0, 2.5, 3.0),
                (-5.5, 48.0, 2.5, 3.0),
                (5.5, 68.0, 2.5, 3.0),
            ],
            "main_waypoints": [
                (0.0, 0.0, -2.0),
                (2.5, 0.0, 14.0),
                (-1.0, 0.0, 30.0),   # bifurcation before Station_3_W
                (2.5, 0.0, 52.0),
                (0.0, 0.0, 80.0),    # exit
            ],
            "side_sockets": [
                (-6.2, 0.0, 34.0),   # CuratedSocket alcove off the corridor
            ],
            "max_steps": 500,
        }
    raise ValueError(f"Unknown preset: {preset}")


class FlowWaypointBifurcationEnv(gym.Env):
    """Deterministic kinematic bifurcation gym using ANNA's obs13 / Discrete(8) contract."""

    metadata = {"render_modes": ["human"], "render_fps": 60}

    def __init__(
        self,
        preset: str = "ringhub_bifurcation",
        config: Optional[Dict[str, Any]] = None,
        dt: float = 1.0 / 30.0,
        turn_assist_rate: float = 0.28,
    ) -> None:
        super().__init__()
        self.preset = preset
        self.cfg = dict(config) if config is not None else _preset_config(preset)
        self.dt = float(dt)
        self.turn_assist_rate = float(turn_assist_rate)

        self.action_space = spaces.Discrete(8)
        self.observation_space = spaces.Box(
            low=-1.0, high=1.0, shape=(13,), dtype=np.float32
        )

        self.tracker = FlowWaypointTracker(
            main_waypoints=self.cfg["main_waypoints"],
            side_sockets=self.cfg.get("side_sockets", ()),
        )
        self.pos = _to_vec3(self.cfg["start_pos"])
        self.yaw = float(self.cfg.get("start_yaw", 0.0))
        self.vel = np.zeros(3, dtype=np.float64)
        self.steps = 0
        self.max_steps = int(self.cfg.get("max_steps", 450))
        self.side_socket_diversions = 0
        self.backtrack_events = 0

    def _forward_xz(self) -> np.ndarray:
        # Yaw=0 -> -Z forward (matching Godot / AnnaInterface convention)
        return np.array([-math.sin(self.yaw), -math.cos(self.yaw)], dtype=np.float64)

    def _right_xz(self) -> np.ndarray:
        return np.array([math.cos(self.yaw), -math.sin(self.yaw)], dtype=np.float64)

    def _is_blocked(self, x: float, z: float) -> bool:
        min_x, max_x, min_z, max_z = self.cfg["bounds"]
        if x < min_x + 0.4 or x > max_x - 0.4 or z < min_z + 0.4 or z > max_z - 0.4:
            return True
        for cx, cz, cr in self.cfg.get("circles", ()):
            if (x - cx) ** 2 + (z - cz) ** 2 <= (cr + 0.4) ** 2:
                return True
        for bx, bz, hx, hz in self.cfg.get("boxes", ()):
            if abs(x - bx) <= (hx + 0.4) and abs(z - bz) <= (hz + 0.4):
                return True
        return False

    def _cast_rays(self) -> List[float]:
        fwd = self._forward_xz()
        base_angle = math.atan2(fwd[1], fwd[0])
        rays: List[float] = []
        step_m = 0.5
        for i in range(8):
            theta = base_angle + (2.0 * math.pi * i) / 8.0
            dx, dz = math.cos(theta), math.sin(theta)
            dist = SENSOR_RANGE
            d = step_m
            while d <= SENSOR_RANGE:
                if self._is_blocked(self.pos[0] + dx * d, self.pos[2] + dz * d):
                    dist = d
                    break
                d += step_m
            rays.append(float(np.clip(dist / SENSOR_RANGE, 0.0, 1.0)))
        return rays

    def _build_obs(self, dist_to_wp: float, angle_to_wp: float) -> np.ndarray:
        rays = self._cast_rays()
        fwd = self._forward_xz()
        right = self._right_xz()
        vx_local = float(self.vel[0] * right[0] + self.vel[2] * right[1])
        vz_local = float(-(self.vel[0] * fwd[0] + self.vel[2] * fwd[1]))
        obs = rays + [
            float(np.clip(dist_to_wp / RL_DIST_NORM, 0.0, 1.0)),
            float(np.clip(angle_to_wp, -1.0, 1.0)),
            float(np.clip(vx_local / RL_MAX_VELOCITY, -1.0, 1.0)),
            float(np.clip(vz_local / RL_MAX_VELOCITY, -1.0, 1.0)),
            float(self.pos[1]),
        ]
        return np.asarray(obs, dtype=np.float32)

    def reset(self, *, seed: Optional[int] = None, options: Optional[dict] = None):
        super().reset(seed=seed)
        self.pos = _to_vec3(self.cfg["start_pos"])
        self.yaw = float(self.cfg.get("start_yaw", 0.0))
        if seed is not None:
            # Small deterministic jitter on start yaw when seeded.
            rng = np.random.default_rng(seed)
            self.yaw += float(rng.uniform(-0.08, 0.08))
        self.vel = np.zeros(3, dtype=np.float64)
        self.steps = 0
        self.side_socket_diversions = 0
        self.backtrack_events = 0
        dist, _ = self.tracker.reset(self.pos)
        wp = self.tracker.current_waypoint()
        angle = signed_angle_to_target(
            self._forward_xz(), np.array([wp[0] - self.pos[0], wp[2] - self.pos[2]])
        )
        return self._build_obs(dist, angle), {
            "wp_idx": self.tracker.wp_idx,
            "main_route_exhausted": False,
        }

    def step(self, action: int):
        action = int(action)
        self.steps += 1

        # Assisted steering toward active waypoint (mirrors AnnaInterface).
        wp = self.tracker.current_waypoint()
        angle_norm = signed_angle_to_target(
            self._forward_xz(), np.array([wp[0] - self.pos[0], wp[2] - self.pos[2]])
        )
        # Adjust yaw to drive angle_norm toward 0.
        self.yaw += angle_norm * math.pi * self.turn_assist_rate

        fwd = self._forward_xz()
        right = self._right_xz()
        speed = 0.0
        move_vec = np.zeros(2, dtype=np.float64)
        if action == 1:  # Forward
            speed = 4.5
            move_vec = fwd
        elif action == 2:  # SprintForward
            speed = 7.0
            move_vec = fwd
        elif action == 3:  # JumpForward
            speed = 6.5
            move_vec = fwd
        elif action in (4, 6):  # StrafeLeft / JumpStrafeLeft
            speed = 4.5
            move_vec = -right
        elif action in (5, 7):  # StrafeRight / JumpStrafeRight
            speed = 4.5
            move_vec = right

        desired_vx = move_vec[0] * speed
        desired_vz = move_vec[1] * speed
        nx = self.pos[0] + desired_vx * self.dt
        nz = self.pos[2] + desired_vz * self.dt
        collided = self._is_blocked(nx, nz)
        if not collided:
            self.pos[0] = nx
            self.pos[2] = nz
            self.vel[0] = desired_vx
            self.vel[2] = desired_vz
        else:
            self.vel[0] = 0.0
            self.vel[2] = 0.0

        res = self.tracker.step(self.pos, self._forward_xz())
        if res.side_socket_diversion:
            self.side_socket_diversions += 1
        if res.backtracking:
            self.backtrack_events += 1

        reward = res.reward - 0.02  # small time penalty
        if collided:
            reward -= 0.25
        if action == 0:
            reward -= 0.05

        terminated = bool(res.main_route_exhausted)
        truncated = bool(not terminated and self.steps >= self.max_steps)
        done_reason = (
            "success"
            if terminated
            else ("timeout" if truncated else "running")
        )
        obs = self._build_obs(res.dist_to_wp, res.angle_to_wp)
        info = {
            "done_reason": done_reason,
            "wp_idx": res.wp_idx,
            "main_route_exhausted": res.main_route_exhausted,
            "side_socket_diversions": self.side_socket_diversions,
            "backtrack_events": self.backtrack_events,
        }
        return obs, float(reward), terminated, truncated, info


class FlowWaypointGymWrapper(gym.Wrapper):
    """Gymnasium wrapper that adds forward waypoint-progress shaping to AnnaGymEnv."""

    def __init__(
        self,
        env: gym.Env,
        progress_scale: float = 0.8,
        align_scale: float = 0.05,
    ) -> None:
        super().__init__(env)
        self.progress_scale = float(progress_scale)
        self.align_scale = float(align_scale)
        self._prev_dist_m: Optional[float] = None

    def reset(self, **kwargs):
        obs, info = self.env.reset(**kwargs)
        obs_arr = np.asarray(obs, dtype=np.float32)
        self._prev_dist_m = float(obs_arr[8]) * RL_DIST_NORM
        return obs_arr, info

    def step(self, action):
        obs, reward, terminated, truncated, info = self.env.step(action)
        obs_arr = np.asarray(obs, dtype=np.float32)
        dist_m = float(obs_arr[8]) * RL_DIST_NORM
        angle_norm = float(obs_arr[9])
        shaping = 0.0
        if self._prev_dist_m is not None:
            shaping += self.progress_scale * (self._prev_dist_m - dist_m)
        shaping += self.align_scale * math.cos(angle_norm * math.pi)
        self._prev_dist_m = dist_m
        return obs_arr, float(reward) + shaping, terminated, truncated, info
