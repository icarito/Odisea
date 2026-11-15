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


def test_waypoint_gym_wrapper_shapes_progress_reward() -> None:
    class _DummyObs13Env(gym.Env):
        def __init__(self) -> None:
            self.observation_space = spaces.Box(-1.0, 1.0, shape=(13,), dtype=np.float32)
            self.action_space = spaces.Discrete(8)
            self._d = 20.0

        def reset(self, *, seed=None, options=None):
            self._d = 20.0
            obs = np.zeros(13, dtype=np.float32)
            obs[8] = self._d / 50.0
            return obs, {}

        def step(self, action):
            self._d += -2.0 if action == 1 else +2.0
            obs = np.zeros(13, dtype=np.float32)
            obs[8] = self._d / 50.0
            obs[9] = 0.0
            return obs, 0.0, False, False, {}

    wrapped = FlowWaypointGymWrapper(_DummyObs13Env(), progress_scale=1.0, align_scale=0.1)
    wrapped.reset()
    _, r_approach, _, _, _ = wrapped.step(1)
    _, r_retreat, _, _, _ = wrapped.step(0)
    assert r_approach > 0.0
    assert r_retreat < 0.0
