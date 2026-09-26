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
            phase TEXT, paused INTEGER,
            game_version TEXT, git_commit TEXT, build_channel TEXT, build_id TEXT,
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
                         60.0, 200.0, 1, "play", 0, "1.0", "abc", "nightly", "1", 1, "ingest"))
    conn.executemany(
        "INSERT INTO heartbeats(player_id, session_id, timestamp, scene, platform, fps,"
        " memory_mb, focused, phase, paused, game_version, git_commit, build_channel,"
        " build_id, official_build, intake_mode) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
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


@pytest.mark.asyncio
async def test_agregados_no_cambian_con_el_cambio_de_query(aiohttp_client, central_app,
                                                            auth_headers, db):
    """El rediseno de la query (dos pasos en vez de agregar heartbeats entero)
    no puede alterar paginacion ni las columnas agregadas de cada fila."""
    client = await aiohttp_client(central_app)
    primera = await _sessions(client, auth_headers, "?limit=10")
    segunda = await _sessions(client, auth_headers, "?limit=10&offset=10")
    assert [r["session_id"] for r in primera] == ["s%d" % i for i in range(10)]
    assert [r["session_id"] for r in segunda] == ["s%d" % i for i in range(10, 20)]
    row = primera[0]
    assert row["duration"] == 1
    assert row["scenes_visited"] == "Dome_Intro"
    assert row["avg_fps"] == 60.0
    assert row["build_channel"] == "nightly"
    assert row["build_id"] == "1"
    assert row["deaths"] == 0 and row["scene_changes"] == 0 and row["avg_load_ms"] is None


@pytest.fixture
def db_channels(tmp_path, monkeypatch):
    """Sesiones recientes casi todas 'dev', unas pocas nightly/release mas
    viejas -- el escenario real que motiva el filtro (T-canal)."""
    path = tmp_path / "ghosts.db"
    conn = sqlite3.connect(str(path))
    conn.execute(
        """CREATE TABLE heartbeats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id TEXT, session_id TEXT, timestamp REAL, scene TEXT,
            platform TEXT, fps REAL, memory_mb REAL, focused INTEGER DEFAULT 1,
            phase TEXT, paused INTEGER,
            game_version TEXT, git_commit TEXT, build_channel TEXT, build_id TEXT,
            official_build INTEGER, intake_mode TEXT
        )"""
    )
    now = time.time()
    rows = []
    # 20 sesiones dev, la mas nueva de todas (desplazarian a las nightly si el
    # filtro no se aplicara antes del limite).
    for s in range(20):
        rows.append(("pd%d" % s, "sd%d" % s, now - s * 60, "Dome_Intro", "Android",
                     60.0, 200.0, 1, "play", 0, "1.0", "abc", "dev", "9", 1, "ingest"))
    # 5 sesiones nightly, mas viejas.
    for s in range(5):
        rows.append(("pn%d" % s, "sn%d" % s, now - 10000 - s * 60, "Dome_Intro", "Android",
                     60.0, 200.0, 1, "play", 0, "1.0", "abc", "nightly", "5", 1, "ingest"))
    # 1 sesion con build_channel vacio (fila vieja pre-contrato): cuenta como 'dev'.
    rows.append(("po1", "so1", now - 20000, "Dome_Intro", "Android",
                 60.0, 200.0, 1, "play", 0, "1.0", "abc", "", "", 1, "ingest"))
    conn.executemany(
        "INSERT INTO heartbeats(player_id, session_id, timestamp, scene, platform, fps,"
        " memory_mb, focused, phase, paused, game_version, git_commit, build_channel,"
        " build_id, official_build, intake_mode) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        rows,
    )
    conn.commit()
    conn.close()
    monkeypatch.setattr(odisea_central, "SQLITE_DB", str(path))
    return path


@pytest.mark.asyncio
async def test_channels_ausente_devuelve_todos(aiohttp_client, central_app, auth_headers,
                                                 db_channels):
    client = await aiohttp_client(central_app)
    rows = await _sessions(client, auth_headers)
    assert len(rows) == 26


@pytest.mark.asyncio
async def test_channels_filtra_antes_del_limite(aiohttp_client, central_app, auth_headers,
                                                  db_channels):
    """Sin el filtro, las 20 sesiones dev (mas nuevas) tapan a las nightly en
    cualquier limit chico. Con `channels=nightly`, deben aparecer las 5."""
    client = await aiohttp_client(central_app)
    rows = await _sessions(client, auth_headers, "?channels=nightly&limit=3")
    assert len(rows) == 3
    assert {r["session_id"] for r in rows} <= {"sn%d" % i for i in range(5)}


@pytest.mark.asyncio
async def test_channels_vacio_o_nulo_cuenta_como_dev(aiohttp_client, central_app, auth_headers,
                                                       db_channels):
    client = await aiohttp_client(central_app)
    rows = await _sessions(client, auth_headers, "?channels=dev&limit=100")
    ids = {r["session_id"] for r in rows}
    assert ids == {"sd%d" % i for i in range(20)} | {"so1"}


@pytest.mark.asyncio
async def test_channels_invalido_se_ignora(aiohttp_client, central_app, auth_headers,
                                            db_channels):
    """Un canal desconocido no rompe el filtro: cae al default (todos)."""
    client = await aiohttp_client(central_app)
    rows = await _sessions(client, auth_headers, "?channels=queseyo&limit=100")
    assert len(rows) == 26
