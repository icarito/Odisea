"""/ghosts/stats contra el handler REAL, no contra una copia de la consulta.

Se rompio en produccion (`near "NOT": syntax error`) porque un comentario SQL dentro
del f-string traia una interpolacion, y el filtro de visibilidad es multilinea: la
primera linea quedaba comentada y el resto se derramaba como SQL suelto. Un test que
reescribia la consulta a mano no lo habria visto nunca; este ejecuta el handler.
"""

import sqlite3
import time

import pytest
from aiohttp import web

import odisea_central
from odisea_central import OdiseaCentral

COLUMNS = (
    "player_id TEXT, session_id TEXT, timestamp REAL, scene TEXT, platform TEXT,"
    " fps REAL, memory_mb REAL, focused INTEGER DEFAULT 1, draw_calls REAL,"
    " objects REAL, vertices REAL, nodes REAL, game_version TEXT, git_commit TEXT,"
    " build_channel TEXT, official_build INTEGER, intake_mode TEXT"
)


@pytest.fixture
def db(tmp_path, monkeypatch):
    path = tmp_path / "ghosts.db"
    conn = sqlite3.connect(str(path))
    conn.execute(f"CREATE TABLE heartbeats (id INTEGER PRIMARY KEY AUTOINCREMENT, {COLUMNS})")
    now = time.time()
    rows = []
    for s in range(6):
        start = now - s * 600
        # El primer heartbeat de cada sesion cae dentro del warmup y no debe contarse.
        for offset in (0.0, 60.0, 120.0):
            rows.append(("p%d" % s, "s%d" % s, start + offset,
                         "Dome_Intro" if s % 2 else "Dome_Crio",
                         "Android", 55.0, 300.0, 1, 100.0, 10.0, 1000.0, 50.0,
                         "1.0", "abc", "nightly", 1, "ingest"))
    # Ruido que el filtro de visibilidad tiene que excluir.
    rows.append(("test-bot", "test-1", now, "Dome_Intro", "test", 60.0, 100.0, 1,
                 0.0, 0.0, 0.0, 0.0, "1.0", "abc", "nightly", 1, "ingest"))
    rows.append(("srv", "srv-1", now, "Dome_Intro", "server", 60.0, 100.0, 1,
                 0.0, 0.0, 0.0, 0.0, "1.0", "abc", "nightly", 1, "ingest"))
    names = [c.split()[0] for c in COLUMNS.split(",")]
    conn.executemany(
        f"INSERT INTO heartbeats({','.join(names)}) VALUES({','.join('?' * len(names))})",
        rows)
    conn.commit()
    conn.close()
    monkeypatch.setattr(odisea_central, "SQLITE_DB", str(path))
    return path


@pytest.fixture
def central_app():
    central = OdiseaCentral()
    app = web.Application()
    app.add_routes([web.get("/ghosts/stats", central.handle_ghosts_stats)])
    return app


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer odisea-dev-insecure"}


@pytest.mark.asyncio
async def test_stats_responde_200_y_no_500(aiohttp_client, central_app, auth_headers, db):
    client = await aiohttp_client(central_app)
    resp = await client.get("/ghosts/stats", headers=auth_headers)
    assert resp.status == 200, await resp.text()


@pytest.mark.asyncio
async def test_agrupa_por_escena_y_respeta_el_warmup(aiohttp_client, central_app,
                                                     auth_headers, db):
    client = await aiohttp_client(central_app)
    data = await (await client.get("/ghosts/stats", headers=auth_headers)).json()
    por_escena = data["scenes"] if isinstance(data, dict) and "scenes" in data else data
    escenas = {row["scene"]: row for row in por_escena}
    assert set(escenas) == {"Dome_Intro", "Dome_Crio"}, escenas
    # 3 sesiones por escena x 3 heartbeats, menos el que cae dentro del warmup.
    for nombre, row in escenas.items():
        assert row["total_sessions"] == 3, nombre
        assert row["total_ghosts"] == 6, f"{nombre}: el warmup no filtro"


@pytest.mark.asyncio
async def test_excluye_telemetria_de_tests_y_de_server(aiohttp_client, central_app,
                                                       auth_headers, db):
    client = await aiohttp_client(central_app)
    data = await (await client.get("/ghosts/stats", headers=auth_headers)).json()
    por_escena = data["scenes"] if isinstance(data, dict) and "scenes" in data else data
    total = sum(row["total_ghosts"] for row in por_escena)
    assert total == 12, "las filas de platform test/server no deben contarse"


@pytest.mark.asyncio
async def test_la_segunda_llamada_sale_del_cache(aiohttp_client, central_app,
                                                 auth_headers, db, monkeypatch):
    """La consulta recorre la tabla entera (~10s en prod) y el dashboard la pide una vez
    por minuto por pestana abierta. Se cachea por TTL: se comprueba vaciando la tabla
    entre llamadas -- si la respuesta no cambia, salio del cache."""
    monkeypatch.setattr(odisea_central, "STATS_CACHE_TTL", 60.0)
    client = await aiohttp_client(central_app)
    primera = await (await client.get("/ghosts/stats", headers=auth_headers)).json()

    conn = sqlite3.connect(str(db))
    conn.execute("DELETE FROM heartbeats")
    conn.commit()
    conn.close()

    segunda = await (await client.get("/ghosts/stats", headers=auth_headers)).json()
    assert segunda == primera, "con TTL vivo tiene que devolver lo cacheado"

    # TTL vencido -> vuelve a consultar y ahora si ve la tabla vacia.
    monkeypatch.setattr(odisea_central, "STATS_CACHE_TTL", 0.0)
    tercera = await (await client.get("/ghosts/stats", headers=auth_headers)).json()
    assert tercera != primera, "vencido el TTL tiene que releer la base"


@pytest.mark.asyncio
async def test_llamadas_concurrentes_consultan_una_sola_vez(aiohttp_client, central_app,
                                                            auth_headers, db, monkeypatch):
    """Single-flight: sin el lock, N pestanas lanzan N recorridos completos en paralelo."""
    monkeypatch.setattr(odisea_central, "STATS_CACHE_TTL", 60.0)
    consultas = []
    original = OdiseaCentral._run_query

    async def contando(self, func, *args):
        consultas.append(1)
        return await original(self, func, *args)

    monkeypatch.setattr(OdiseaCentral, "_run_query", contando)
    client = await aiohttp_client(central_app)
    import asyncio as _asyncio
    resps = await _asyncio.gather(*[
        client.get("/ghosts/stats", headers=auth_headers) for _ in range(5)
    ])
    assert all(r.status == 200 for r in resps)
    assert len(consultas) == 1, f"se consulto {len(consultas)} veces en vez de una"
