"""Contrato de telemetria v2 (docs/agents/sessions/2026-09-26_polish_ronda5.md):
eventos discretos del heartbeat (`player.phase` + `events`) y sus agregados en
/ghosts/sessions. Cubre lo que un test que solo reescribiera la consulta a mano
no veria: el handler REAL procesando la cola de eventos y filtrando por phase.
"""

import sqlite3
import sys
import tempfile
import time
import types
import unittest
from pathlib import Path
from unittest import mock

if "pywebpush" not in sys.modules:
    pywebpush_stub = types.ModuleType("pywebpush")
    pywebpush_stub.webpush = mock.Mock()
    pywebpush_stub.WebPushException = Exception
    sys.modules["pywebpush"] = pywebpush_stub

import pytest
from aiohttp import web

import odisea_central
from odisea_central import OdiseaCentral


def _heartbeat(player_id: str, session_id: str, ts: float, events=None, scene="Dome_Intro"):
    return {
        "type": "heartbeat",
        "player_id": player_id,
        "session_id": session_id,
        "timestamp": ts,
        "player": {"scene": scene, "fps": 60.0, "phase": "play"},
        "events": events or [],
    }


class SessionEventsPersistenceTest(unittest.IsolatedAsyncioTestCase):
    """(a)/(b): la cola de eventos se persiste, deduplica por seq, y sobrevive
    al rate-limit de 50ms del heartbeat que la carga."""

    async def asyncSetUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.db_path = str(Path(self._tmp.name) / "ghosts.db")
        self.central = OdiseaCentral()
        self._patch = mock.patch.object(odisea_central, "SQLITE_DB", self.db_path)
        self._patch.start()
        # El schema de session_events lo crea _db_worker al arrancar (sync, antes
        # de bloquear en queue.get()); se lanza como task y se cancela apenas
        # alcanza a correr un tick del loop, dejando la tabla lista sin duplicar
        # el DDL aca.
        import asyncio
        task = asyncio.ensure_future(self.central._db_worker())
        await asyncio.sleep(0)
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass

    async def asyncTearDown(self):
        self._patch.stop()
        self._tmp.cleanup()

    def _rows(self):
        conn = sqlite3.connect(self.db_path)
        rows = conn.execute(
            "SELECT seq, type, scene FROM session_events WHERE session_id = ? ORDER BY seq",
            ("s1",),
        ).fetchall()
        conn.close()
        return rows

    async def test_events_se_persisten_y_seq_repetido_no_duplica(self):
        events = [
            {"seq": 1, "t": 1000, "type": "session_start", "data": {}},
            {"seq": 2, "t": 2000, "type": "death", "data": {"pos": [1, 2, 3]}},
        ]
        await self.central._process_heartbeat(_heartbeat("p1", "s1", 100.0, events))
        # Reenvio del mismo heartbeat (p.ej. reconexion del peer): seq 2 no debe duplicarse.
        await self.central._process_heartbeat(
            _heartbeat("p1", "s1", 100.0, [events[1]])
        )
        rows = self._rows()
        self.assertEqual([(1, "session_start", "Dome_Intro"), (2, "death", "Dome_Intro")], rows)

    async def test_events_sobreviven_el_rate_limit_de_50ms(self):
        # Dos heartbeats de la misma sesion a menos de 50ms: el segundo cae en el
        # rate-limit y su player.fps/scene no deben tocar self.heartbeats, pero su
        # evento tiene que persistirse igual (contrato: eventos antes del rate-limit).
        await self.central._process_heartbeat(
            _heartbeat("p1", "s1", 100.0, [{"seq": 1, "t": 1000, "type": "session_start", "data": {}}])
        )
        first_ts = self.central.heartbeats["p1"]["timestamp"]

        await self.central._process_heartbeat(
            _heartbeat("p1", "s1", 999.0, [{"seq": 2, "t": 2000, "type": "death", "data": {}}])
        )

        # El heartbeat cayo en el rate-limit: no piso el timestamp mergeado.
        self.assertEqual(first_ts, self.central.heartbeats["p1"]["timestamp"])
        # El evento igual llego a session_events.
        rows = self._rows()
        self.assertEqual([1, 2], [r[0] for r in rows])


# --- (c)/(d): agregados de /ghosts/sessions -------------------------------

COLUMNS = (
    "player_id TEXT, session_id TEXT, timestamp REAL, scene TEXT, platform TEXT,"
    " fps REAL, memory_mb REAL, focused INTEGER DEFAULT 1, phase TEXT, paused INTEGER,"
    " game_version TEXT, git_commit TEXT, build_channel TEXT, official_build INTEGER,"
    " intake_mode TEXT"
)


@pytest.fixture
def sessions_db(tmp_path, monkeypatch):
    path = tmp_path / "ghosts.db"
    conn = sqlite3.connect(str(path))
    conn.execute(f"CREATE TABLE heartbeats (id INTEGER PRIMARY KEY AUTOINCREMENT, {COLUMNS})")
    conn.execute(
        """CREATE TABLE session_events (
            player_id TEXT, session_id TEXT, seq INTEGER, timestamp REAL,
            type TEXT, scene TEXT, data TEXT, UNIQUE(session_id, seq)
        )"""
    )
    now = time.time()
    names = [c.split()[0] for c in COLUMNS.split(",")]
    placeholders = ",".join("?" * len(names))

    def hb(pid, sid, ts, scene, fps, phase=None, paused=0):
        return (pid, sid, ts, scene, "Android", fps, 300.0, 1, phase, paused,
                "1.0", "abc", "nightly", 1, "ingest")

    rows = [
        # sesion "s1": 3 muestras play a 60fps + ruido menu/boot/paused/viejo-Boot
        # que NO debe entrar al promedio.
        hb("p1", "s1", now, "Dome_Intro", 60.0, "play"),
        hb("p1", "s1", now + 1, "Dome_Intro", 60.0, "play"),
        hb("p1", "s1", now + 2, "Dome_Intro", 60.0, "play"),
        hb("p1", "s1", now + 3, "Menu", 10.0, "menu"),
        hb("p1", "s1", now + 4, "Dome_Intro", 5.0, "boot"),
        hb("p1", "s1", now + 5, "Dome_Intro", 1.0, "paused", paused=1),
        # fila vieja sin phase, en escena Boot: cae al fallback ('x'), se excluye
        # aunque no traiga la columna phase seteada (clientes previos al contrato).
        hb("p1", "s1", now + 6, "Boot", 1000.0, None),
        hb("p1", "s1", now + 7, "Menu", 1000.0, None),
    ]
    conn.executemany(f"INSERT INTO heartbeats({','.join(names)}) VALUES({placeholders})", rows)
    conn.executemany(
        "INSERT INTO session_events(player_id, session_id, seq, timestamp, type, scene, data)"
        " VALUES(?,?,?,?,?,?,?)",
        [
            ("p1", "s1", 1, now, "session_start", "Boot", "{}"),
            ("p1", "s1", 2, now + 1, "death", "Dome_Intro", '{"pos":[0,0,0]}'),
            ("p1", "s1", 3, now + 2, "death", "Dome_Intro", '{"pos":[1,1,1]}'),
            ("p1", "s1", 4, now + 3, "scene_enter", "Dome_Intro", '{"from":"Boot","to":"Dome_Intro","load_ms":500}'),
            ("p1", "s1", 5, now + 4, "scene_enter", "Menu", '{"from":"Dome_Intro","to":"Menu","load_ms":700}'),
        ],
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(odisea_central, "SQLITE_DB", str(path))
    return path


@pytest.fixture
def central_app():
    central = OdiseaCentral()
    app = web.Application()
    app.add_routes([web.get("/ghosts/sessions", central.handle_ghosts_sessions)])
    return app


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer odisea-dev-insecure"}


@pytest.mark.asyncio
async def test_avg_fps_ignora_menu_boot_paused_y_filas_viejas_sin_phase(
    aiohttp_client, central_app, auth_headers, sessions_db
):
    client = await aiohttp_client(central_app)
    rows = await (await client.get("/ghosts/sessions", headers=auth_headers)).json()
    row = next(r for r in rows if r["session_id"] == "s1")
    # Solo las 3 muestras phase=play (60fps) cuentan; el resto (menu/boot/paused y
    # las filas viejas sin phase en Boot/Menu) quedan afuera del promedio.
    assert row["avg_fps"] == 60.0, row


@pytest.mark.asyncio
async def test_deaths_scene_changes_avg_load_ms(aiohttp_client, central_app, auth_headers, sessions_db):
    client = await aiohttp_client(central_app)
    rows = await (await client.get("/ghosts/sessions", headers=auth_headers)).json()
    row = next(r for r in rows if r["session_id"] == "s1")
    assert row["deaths"] == 2
    assert row["scene_changes"] == 2
    assert row["avg_load_ms"] == 600.0


if __name__ == "__main__":
    unittest.main()
