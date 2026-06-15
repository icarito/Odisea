import pytest
import time
import hmac
import hashlib
import os
from aiohttp import web
from odisea_central import OdiseaCentral, BRIDGE_TOKEN

@pytest.fixture
def central_instance(tmp_path):
    # Setup a temporary hotzones directory
    hotzones_dir = tmp_path / "hotzones"
    hotzones_dir.mkdir()
    
    # Mock some environment variables if needed or just instantiate
    central = OdiseaCentral()
    central.HOTZONES_DIR = str(hotzones_dir)
    return central

@pytest.fixture
def central_app(central_instance):
    app = web.Application()
    app.add_routes([
        web.get('/hotzones/{id}/dl-link', central_instance.handle_hotzone_dl_link),
        web.get('/hotzones/{id}/download', central_instance.handle_hotzone_download),
    ])
    return app

@pytest.fixture
def auth_headers():
    return {"Authorization": f"Bearer {BRIDGE_TOKEN}"}

@pytest.mark.asyncio
async def test_hotzone_dl_link_unauthorized(aiohttp_client, central_app):
    client = await aiohttp_client(central_app)
    resp = await client.get('/hotzones/test-hz/dl-link')
    assert resp.status == 401

@pytest.mark.asyncio
async def test_hotzone_dl_link_success(aiohttp_client, central_app, auth_headers):
    client = await aiohttp_client(central_app)
    resp = await client.get('/hotzones/test-hz/dl-link', headers=auth_headers)
    assert resp.status == 200
    data = await resp.json()
    assert "url" in data
    assert "runbin_token=" in data["url"]
    assert "expires=" in data["url"]
    assert "/hotzones/test-hz/download" in data["url"]

@pytest.mark.asyncio
async def test_hotzone_download_with_token_success(aiohttp_client, central_app, central_instance, tmp_path, monkeypatch):
    hz_id = "test-hz-123"
    hz_file = tmp_path / "hotzones" / "test-hz-123.bin"
    hz_file.write_bytes(b"dummy binary data")
    
    # Mock _run_query to return the file path
    async def mock_run_query(self, func, *args):
        return str(hz_file)
    monkeypatch.setattr(OdiseaCentral, "_run_query", mock_run_query)

    # Generate valid token
    expiry = int(time.time() + 60)
    payload = f"{hz_id}:{expiry}"
    token = hmac.new(BRIDGE_TOKEN.encode(), payload.encode(), hashlib.sha256).hexdigest()[:16]

    client = await aiohttp_client(central_app)
    url = f"/hotzones/{hz_id}/download?runbin_token={token}&expires={expiry}"
    resp = await client.get(url)
    
    assert resp.status == 200
    assert await resp.read() == b"dummy binary data"
    assert resp.headers.get("Access-Control-Allow-Origin") == "*"

@pytest.mark.asyncio
async def test_hotzone_download_with_invalid_token(aiohttp_client, central_app):
    hz_id = "test-hz-123"
    client = await aiohttp_client(central_app)
    
    # Invalid token
    url = f"/hotzones/{hz_id}/download?runbin_token=invalid&expires={int(time.time()+60)}"
    resp = await client.get(url)
    assert resp.status == 401

@pytest.mark.asyncio
async def test_hotzone_download_with_expired_token(aiohttp_client, central_app):
    hz_id = "test-hz-123"
    expiry = int(time.time() - 60) # Expired
    payload = f"{hz_id}:{expiry}"
    token = hmac.new(BRIDGE_TOKEN.encode(), payload.encode(), hashlib.sha256).hexdigest()[:16]
    
    client = await aiohttp_client(central_app)
    url = f"/hotzones/{hz_id}/download?runbin_token={token}&expires={expiry}"
    resp = await client.get(url)
    assert resp.status == 401
