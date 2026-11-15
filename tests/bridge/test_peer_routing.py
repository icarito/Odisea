"""Unit tests for peer command routing (odisea_peer.OdiseaPeer).

These run offline — no live peer or game needed. They lock in the rule that keeps
concurrent agent worktrees from cross-capturing: a command with no player_id must be
refused (not silently routed to the most-recent game) when several games are connected.

    pytest tests/bridge/test_peer_routing.py -q
    pytest -k peer
"""
import asyncio
import importlib.machinery
import importlib.util
from pathlib import Path

import pytest

PEER_PY = Path(__file__).resolve().parents[2] / "odisea_peer.py"


@pytest.fixture(scope="module")
def peer_mod():
    spec = importlib.util.spec_from_loader(
        "odisea_peer_under_test",
        importlib.machinery.SourceFileLoader("odisea_peer_under_test", str(PEER_PY)),
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class _FakeWS:
    def __init__(self, closed=False):
        self.closed = closed


def _peer_with_games(peer_mod, n):
    peer = peer_mod.OdiseaPeer()
    peer.godot_clients = [_FakeWS() for _ in range(n)]
    return peer


def test_explicit_or_single_game_is_unambiguous(peer_mod):
    peer = _peer_with_games(peer_mod, 0)
    assert peer._live_game_count() == 0
    assert peer._ambiguous_target(None) is False

    peer = _peer_with_games(peer_mod, 1)
    assert peer._live_game_count() == 1
    assert peer._ambiguous_target(None) is False
    assert peer._ambiguous_target("src-53") is False


def test_two_games_without_player_id_is_ambiguous(peer_mod):
    peer = _peer_with_games(peer_mod, 2)
    assert peer._live_game_count() == 2
    assert peer._ambiguous_target(None) is True
    # Naming the game always resolves it, even with several connected.
    assert peer._ambiguous_target("src-53") is False


def test_closed_connections_do_not_count(peer_mod):
    peer = peer_mod.OdiseaPeer()
    peer.godot_clients = [_FakeWS(), _FakeWS(closed=True)]
    assert peer._live_game_count() == 1
    assert peer._ambiguous_target(None) is False


def test_run_command_refuses_to_guess(peer_mod):
    peer = _peer_with_games(peer_mod, 2)
    resp, status = asyncio.run(peer._run_command("screenshot", {}, None))
    assert status == 400
    assert resp["error"] == "ambiguous_player"


def test_run_command_with_explicit_missing_player_does_not_guess(peer_mod):
    peer = _peer_with_games(peer_mod, 2)
    resp, status = asyncio.run(peer._run_command("screenshot", {}, "does-not-exist"))
    assert status == 404
    assert resp["error"] == "player_not_found"
