import asyncio
import json
import sqlite3
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

if "pywebpush" not in sys.modules:
    pywebpush_stub = types.ModuleType("pywebpush")
    pywebpush_stub.webpush = mock.Mock()
    pywebpush_stub.WebPushException = Exception
    sys.modules["pywebpush"] = pywebpush_stub

import odisea_central
from odisea_peer import OdiseaPeer


class _FakeWebSocket:
    def __init__(self):
        self.closed = False
        self.messages = []

    async def send_json(self, data):
        self.messages.append(data)


class TransitionTelemetryTest(unittest.IsolatedAsyncioTestCase):
    def _heartbeat(self):
        return {
            "type": "heartbeat",
            "player_id": "ios-test",
            "session_id": "session-test",
            "timestamp": 1234.5,
            "player": {
                "scene": "Menu",
                "platform": "iOS",
                "position": [1, 2, 3],
                "transition": {
                    "stage": "loading",
                    "path": "res://Dome_Intro.tscn",
                    "current_scene": "Menu",
                    "elapsed_ms": 12000,
                    "progress": 0.55,
                    "loader_stage": 11,
                    "preloading": True,
                    "overlay_visible": True,
                    "overlay_alpha": 1.0,
                    "error": "",
                },
            },
        }

    async def test_peer_preserves_transition_locally_and_upstream(self):
        peer = OdiseaPeer()
        game_ws = _FakeWebSocket()
        central_ws = _FakeWebSocket()
        peer.central_ws = central_ws

        await peer._on_game_message(json.dumps(self._heartbeat()), game_ws)

        expected = self._heartbeat()["player"]["transition"]
        self.assertEqual(peer.heartbeats["ios-test"]["player"]["transition"], expected)
        self.assertEqual(peer.local_buffer[0]["player"]["transition"], expected)
        self.assertEqual(central_ws.messages[0]["player"]["transition"], expected)

    async def test_central_persists_transition_columns(self):
        with tempfile.TemporaryDirectory() as tmp:
            db_path = str(Path(tmp) / "ghosts.db")
            central = odisea_central.OdiseaCentral()
            with mock.patch.object(odisea_central, "SQLITE_DB", db_path):
                worker = asyncio.create_task(central._db_worker())
                await central.db_queue.put(self._heartbeat())
                await asyncio.wait_for(central.db_queue.join(), timeout=3)
                worker.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await worker

            conn = sqlite3.connect(db_path)
            row = conn.execute(
                "SELECT transition_stage, transition_path, transition_elapsed_ms, "
                "transition_progress, transition_overlay_visible FROM heartbeats"
            ).fetchone()
            conn.close()
            self.assertEqual(row, ("loading", "res://Dome_Intro.tscn", 12000, 0.55, 1))


if __name__ == "__main__":
    unittest.main()
