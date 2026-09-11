import json

import pytest
from aiohttp import web

import odisea_central
from odisea_central import OdiseaCentral


@pytest.fixture
def log_file(tmp_path, monkeypatch):
    path = tmp_path / "client_logs.jsonl"
    monkeypatch.setattr(odisea_central, "CLIENT_LOG_FILE", str(path))
    return path


@pytest.fixture
def central_app():
    central = OdiseaCentral()
    app = web.Application()
    app.on_response_prepare.append(central._on_prepare)
    app.add_routes([
        web.post("/client-log", central.handle_client_log),
        web.options("/client-log", central.handle_client_log_options),
        web.get("/client-logs", central.handle_client_logs_list),
    ])
    return app


@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer odisea-dev-insecure"}


def _payload(**over):
    body = {
        "player_id": "abc123",
        "session_id": "sess-1",
        "platform": "iOS",
        "version": "1.2.3",
        "gpu": "Apple A15 GPU",
        "lines": ["ERROR: shader link failed", "SCRIPT ERROR: nope"],
    }
    body.update(over)
    return body


@pytest.mark.asyncio
async def test_rejects_without_token(aiohttp_client, central_app, log_file):
    client = await aiohttp_client(central_app)
    resp = await client.post("/client-log", json=_payload())
    assert resp.status == 401
    assert (await client.get("/client-logs")).status == 401
    assert not log_file.exists()


@pytest.mark.asyncio
async def test_client_log_preflight_allows_authenticated_json(aiohttp_client, central_app):
    client = await aiohttp_client(central_app)
    resp = await client.options("/client-log")
    assert resp.status == 204
    assert resp.headers["Access-Control-Allow-Origin"] == "*"
    assert "Authorization" in resp.headers["Access-Control-Allow-Headers"]


@pytest.mark.asyncio
async def test_stores_lines(aiohttp_client, central_app, auth_headers, log_file):
    client = await aiohttp_client(central_app)
    resp = await client.post("/client-log", headers=auth_headers, json=_payload())
    assert resp.status == 200
    assert resp.headers["Access-Control-Allow-Origin"] == "*"
    assert (await resp.json())["stored"] == 2

    record = json.loads(log_file.read_text(encoding="utf-8").strip())
    assert record["platform"] == "iOS"
    assert record["player_id"] == "abc123"
    assert record["lines"][0] == "ERROR: shader link failed"
    assert record["received_at"]


@pytest.mark.asyncio
async def test_lists_newest_client_logs_without_ip(aiohttp_client, central_app, auth_headers, log_file):
    client = await aiohttp_client(central_app)
    await client.post("/client-log", headers=auth_headers, json=_payload(player_id="first"))
    await client.post("/client-log", headers=auth_headers, json=_payload(player_id="latest"))

    resp = await client.get("/client-logs?limit=1", headers=auth_headers)
    assert resp.status == 200
    records = await resp.json()
    assert records[0]["player_id"] == "latest"
    assert "ip" not in records[0]


@pytest.mark.asyncio
async def test_rejects_empty_and_malformed(aiohttp_client, central_app, auth_headers, log_file):
    client = await aiohttp_client(central_app)
    assert (await client.post("/client-log", headers=auth_headers,
                              json=_payload(lines=[]))).status == 400
    assert (await client.post("/client-log", headers=auth_headers,
                              data="no json")).status == 400
    assert not log_file.exists()


@pytest.mark.asyncio
async def test_caps_line_count_and_length(aiohttp_client, central_app, auth_headers, log_file,
                                          monkeypatch):
    monkeypatch.setattr(odisea_central, "CLIENT_LOG_MAX_LINES", 3)
    monkeypatch.setattr(odisea_central, "CLIENT_LOG_MAX_LINE_CHARS", 10)
    client = await aiohttp_client(central_app)
    resp = await client.post("/client-log", headers=auth_headers,
                             json=_payload(lines=["ERROR " + "x" * 100] * 20))
    assert resp.status == 200
    record = json.loads(log_file.read_text(encoding="utf-8").strip())
    assert len(record["lines"]) == 3
    assert all(len(line) <= 10 for line in record["lines"])


@pytest.mark.asyncio
async def test_rejects_oversized_body(aiohttp_client, central_app, auth_headers, log_file,
                                      monkeypatch):
    monkeypatch.setattr(odisea_central, "CLIENT_LOG_MAX_BYTES", 128)
    client = await aiohttp_client(central_app)
    resp = await client.post("/client-log", headers=auth_headers,
                             json=_payload(lines=["ERROR " + "y" * 500]))
    assert resp.status == 413
    assert not log_file.exists()
