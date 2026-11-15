#!/usr/bin/env python3
"""Unit tests for Flow Waypoint observation & reward in agents/."""
from __future__ import annotations

import sys
from pathlib import Path

import gymnasium as gym
from gymnasium import spaces
import numpy as np

AGENTS_DIR = Path(__file__).resolve().parent
if str(AGENTS_DIR) not in sys.path:
    sys.path.insert(0, str(AGENTS_DIR))

from flow_waypoint_env import (  # noqa: E402
    FlowWaypointBifurcationEnv,
    FlowWaypointGymWrapper,
    FlowWaypointTracker,
)


def test_tracker_monotonic_progression_and_side_socket_gating() -> None:
    tracker = FlowWaypointTracker(
        main_waypoints=[(0, 0, 0), (0, 0, 10), (0, 0, 20)],
        side_sockets=[(6, 0, 10)],
        reach_radius=1.5,
        socket_radius=2.0,
    )
    tracker.reset((0, 0, 0))
    assert tracker.wp_idx == 1
    assert not tracker.main_route_exhausted

    # Approach wp 1 -> positive progress reward
    r_fwd = tracker.step((0, 0, 4), (0, 1))
    assert r_fwd.reward > 0.0
    assert not r_fwd.backtracking
    assert not r_fwd.side_socket_diversion

    # Backtrack toward wp 0 -> negative backtrack penalty
    r_back = tracker.step((0, 0, 1), (0, 1))
    assert r_back.backtracking
    assert r_back.reward < 0.0

    # Divert to Side Socket before main route is exhausted -> penalized
    r_sock_early = tracker.step((6, 0, 10), (1, 0))
    assert r_sock_early.side_socket_diversion
    assert r_sock_early.reward < 0.0
    assert not tracker.main_route_exhausted

    # Reach wp 1 -> advances monotonically to wp 2
    r_wp1 = tracker.step((0, 0, 10), (0, 1))
    assert r_wp1.waypoint_reached
    assert tracker.wp_idx == 2
    assert not tracker.main_route_exhausted

    # Reach final wp 2 -> main route exhausted
    r_wp2 = tracker.step((0, 0, 20), (0, 1))
    assert r_wp2.waypoint_reached
    assert tracker.main_route_exhausted

    # Now Side Socket is allowed and gives post-route bonus instead of penalty
    r_sock_after = tracker.step((6, 0, 10), (1, 0))
    assert not r_sock_after.side_socket_diversion
    assert r_sock_after.reward > 0.0


def test_bifurcation_gyms_ringhub_and_machinebay_contract_and_determinism() -> None:
    for preset in ("ringhub_bifurcation", "machinebay_bifurcation"):
        env_a = FlowWaypointBifurcationEnv(preset=preset)
        env_b = FlowWaypointBifurcationEnv(preset=preset)

        obs_a, info_a = env_a.reset(seed=123)
        obs_b, info_b = env_b.reset(seed=123)
        assert obs_a.shape == (13,)
        assert env_a.action_space == spaces.Discrete(8)
        assert np.allclose(obs_a, obs_b)
        assert info_a == info_b

        done = False
        steps = 0
        last_info = {}
        while not done and steps < 450:
            # SprintForward follows assisted steering toward the active main waypoint
            obs_a, rew_a, term_a, trunc_a, last_info = env_a.step(2)
            obs_b, rew_b, term_b, trunc_b, _ = env_b.step(2)
            assert np.allclose(obs_a, obs_b)
            assert abs(rew_a - rew_b) < 1e-9
            done = term_a or trunc_a
            steps += 1

        assert last_info["done_reason"] == "success"
        assert last_info["main_route_exhausted"] is True
        assert last_info["side_socket_diversions"] == 0
        assert last_info["backtrack_events"] == 0


def test_waypoint_gym_wrapper_updates_obs_and_penalizes_socket_and_backtrack() -> None:
    class _DummyGodotLikeEnv(gym.Env):
        """Emulates AnnaGymEnv emitting raw target obs[8..9] that must be overridden."""

        def __init__(self) -> None:
            self.observation_space = spaces.Box(-1.0, 1.0, shape=(13,), dtype=np.float32)
            self.action_space = spaces.Discrete(8)
            self.scene_path = "core_v2/tests/TestScene_RL_MachineBayCorridor.tscn"
            self._pos = np.array([0.0, 0.0, 0.0], dtype=np.float64)
            self._fwd = np.array([0.0, 1.0], dtype=np.float64)  # +Z

        def _raw_obs(self) -> np.ndarray:
            obs = np.zeros(13, dtype=np.float32)
            # Raw env points at a stale distant target (dist=49m, angle=-0.9)
            obs[8] = 49.0 / 50.0
            obs[9] = -0.9
            return obs

        def reset(self, *, seed=None, options=None):
            self._pos = np.array([0.0, 0.0, 0.0], dtype=np.float64)
            return self._raw_obs(), {
                "player_pos": self._pos.copy(),
                "player_forward": self._fwd.copy(),
            }

        def step(self, action):
            # 1: forward to wp1, 2: backtrack toward wp0, 3: divert to Side Socket,
            # 4: reach wp1, 5: reach wp2 (exhaust route), 6: visit Side Socket after route
            moves = {
                1: (0.0, 5.0),
                2: (0.0, 2.0),
                3: (6.0, 10.0),
                4: (0.0, 10.0),
                5: (0.0, 20.0),
                6: (6.0, 10.0),
            }
            x, z = moves[int(action)]
            self._pos = np.array([x, 0.0, z], dtype=np.float64)
            return self._raw_obs(), 0.0, False, False, {
                "player_pos": self._pos.copy(),
                "player_forward": self._fwd.copy(),
            }

    flow_data = {
        "main_waypoints": [
            {"id": "entry", "position": {"x": 0.0, "y": 0.0, "z": 0.0}},
            {"id": "mid", "position": {"x": 0.0, "y": 0.0, "z": 10.0}},
            {"id": "exit", "position": {"x": 0.0, "y": 0.0, "z": 20.0}},
        ],
        "side_socket_waypoints": [
            {"id": "socket_1", "position": {"x": 6.0, "y": 0.0, "z": 10.0}},
        ],
    }

    wrapped = FlowWaypointGymWrapper(
        _DummyGodotLikeEnv(),
        waypoints_source=flow_data,
        reach_radius=1.5,
        socket_radius=2.0,
    )
    obs0, info0 = wrapped.reset()
    # obs[8] must reflect dist to wp1 (10m / 50m = 0.2), NOT raw env's 49/50 = 0.98
    assert abs(float(obs0[8]) - 0.2) < 1e-5
    assert abs(float(obs0[9])) < 1e-5
    assert info0["wp_idx"] == 1

    # Approach wp1 -> positive reward, obs[8] = 5m / 50m = 0.1
    obs1, r_fwd, _, _, info1 = wrapped.step(1)
    assert abs(float(obs1[8]) - 0.1) < 1e-5
    assert r_fwd > 0.0

    # Backtrack -> negative reward & backtrack_events increments
    _, r_back, _, _, info2 = wrapped.step(2)
    assert r_back < 0.0
    assert info2["backtrack_events"] == 1

    # Early Side Socket diversion -> negative reward & side_socket_diversions increments
    _, r_sock_early, _, _, info3 = wrapped.step(3)
    assert r_sock_early < 0.0
    assert info3["side_socket_diversions"] == 1

    # Reach wp1 -> advances to wp2 (20m), dist = 10m -> obs[8] = 0.2
    obs4, r_wp1, _, _, info4 = wrapped.step(4)
    assert info4["wp_idx"] == 2
    assert abs(float(obs4[8]) - 0.2) < 1e-5
    assert r_wp1 > 0.0

    # Reach wp2 -> main route exhausted
    _, r_wp2, _, _, info5 = wrapped.step(5)
    assert info5["main_route_exhausted"] is True
    assert r_wp2 > 0.0

    # Visit Side Socket after main route exhausted -> allowed with positive reward
    _, r_sock_after, _, _, info6 = wrapped.step(6)
    assert info6["side_socket_diversions"] == 1
    assert r_sock_after > 0.0


def test_ray_angular_order_matches_anna_interface_left_is_ray2() -> None:
    cfg = {
        "start_pos": (0.0, 0.0, 0.0),
        "start_yaw": 0.0,  # facing -Z
        "bounds": (-30.0, 30.0, -30.0, 30.0),
        "circles": [],
        # Asymmetric obstacle on the player's LEFT (-X) at x=-4, z=0
        "boxes": [(-4.0, 0.0, 1.0, 1.0)],
        "main_waypoints": [(0.0, 0.0, 0.0), (0.0, 0.0, -10.0)],
        "side_sockets": [],
    }
    env = FlowWaypointBifurcationEnv(config=cfg)
    obs, _ = env.reset()
    # Ray 0 = forward (-Z), Ray 2 = left (-X), Ray 6 = right (+X)
    assert obs[2] < obs[6]
    assert obs[2] < 0.25
    assert obs[6] > 0.9
