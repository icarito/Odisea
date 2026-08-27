"""El listado historico de sesiones tenia LIMIT 200 fijo y no leia `limit`.

Con mas trafico esas 200 sesiones cubrian cada vez menos dias, asi que desde el
dashboard parecia que el historico se hubiera rotado. Los datos viejos nunca se
perdieron: siguen consultables por /ghosts con since/until.
"""

import sqlite3
import time

import pytest
from aiohttp import web

import odisea_central
from odisea_central import OdiseaCentral

SESSIONS = 260


@pytest.fixture
def db(tmp_path, monkeypatch):
    path = tmp_path / "ghosts.db"
    conn = sqlite3.connect(str(path))
    conn.execute(
        """CREATE TABLE heartbeats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id TEXT, session_id TEXT, timestamp REAL, scene TEXT,
            platform TEXT, fps REAL, memory_mb REAL, focused INTEGER DEFAULT 1,
            game_version TEXT, git_commit TEXT, build_channel TEXT,
            official_build INTEGER, intake_mode TEXT
        )"""
    )
    now = time.time()
    rows = []
    for s in range(SESSIONS):
        # Una sesion por hora hacia atras, dos heartbeats cada una.
        start = now - s * 3600
        for k in range(2):
            rows.append(("p%d" % s, "s%d" % s, start + k, "Dome_Intro", "Android",
                         60.0, 200.0, 1, "1.0", "abc", "nightly", 1, "ingest"))
    conn.executemany(
        "INSERT INTO heartbeats(player_id, session_id, timestamp, scene, platform, fps,"
        " memory_mb, focused, game_version, git_commit, build_channel, official_build,"
        " intake_mode) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
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


async def _sessions(client, headers, query=""):
    resp = await client.get("/ghosts/sessions" + query, headers=headers)
    assert resp.status == 200
    return await resp.json()


@pytest.mark.asyncio
async def test_por_defecto_devuelve_200(aiohttp_client, central_app, auth_headers, db):
    client = await aiohttp_client(central_app)
    assert len(await _sessions(client, auth_headers)) == 200


@pytest.mark.asyncio
async def test_limit_permite_ver_mas_alla_de_las_200(aiohttp_client, central_app,
                                                     auth_headers, db):
    client = await aiohttp_client(central_app)
    rows = await _sessions(client, auth_headers, "?limit=1000")
    assert len(rows) == SESSIONS, "el historico completo tiene que ser alcanzable"


@pytest.mark.asyncio
async def test_offset_pagina_sin_repetir(aiohttp_client, central_app, auth_headers, db):
    client = await aiohttp_client(central_app)
    primera = await _sessions(client, auth_headers, "?limit=50")
    segunda = await _sessions(client, auth_headers, "?limit=50&offset=50")
    assert len(primera) == 50 and len(segunda) == 50
    ids = {r["session_id"] for r in primera} & {r["session_id"] for r in segunda}
    assert not ids


@pytest.mark.asyncio
async def test_limit_invalido_no_rompe(aiohttp_client, central_app, auth_headers, db):
    client = await aiohttp_client(central_app)
    assert len(await _sessions(client, auth_headers, "?limit=ni-idea")) == 200
    assert len(await _sessions(client, auth_headers, "?limit=0")) == 1
    # Tope duro: nadie pide la tabla entera por accidente.
    assert len(await _sessions(client, auth_headers, "?limit=999999")) == SESSIONS
