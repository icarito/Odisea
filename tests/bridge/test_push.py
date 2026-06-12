import pytest
import json
import asyncio
from aiohttp import web
from odisea_central import OdiseaCentral

@pytest.fixture
def central_app():
    central = OdiseaCentral()
    app = web.Application()
    app.add_routes([
        web.get('/push/key', central.handle_vapid_public_key),
        web.post('/push/subscribe', central.handle_push_subscribe),
        web.post('/push/send', central.handle_push_send),
    ])
    return app

@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer odisea-dev-insecure"}

@pytest.mark.asyncio
async def test_vapid_key_endpoint(aiohttp_client, central_app):
    client = await aiohttp_client(central_app)
    resp = await client.get('/push/key')
    if resp.status == 200:
        data = await resp.json()
        assert "publicKey" in data
    else:
        assert resp.status == 503

@pytest.mark.asyncio
async def test_push_subscribe_unauthorized(aiohttp_client, central_app):
    client = await aiohttp_client(central_app)
    resp = await client.post('/push/subscribe', json={"subscription": {}})
    assert resp.status == 401

@pytest.mark.asyncio
async def test_push_subscribe_success(aiohttp_client, central_app, auth_headers, monkeypatch):
    async def mock_run_query(self, func, *args):
        return None
    monkeypatch.setattr(OdiseaCentral, "_run_query", mock_run_query)
    
    client = await aiohttp_client(central_app)
    resp = await client.post('/push/subscribe', 
                             headers=auth_headers,
                             json={
                                 "subscription": {"endpoint": "https://test.com"},
                                 "settings": {"disconnect": True, "bridge": False}
                             })
    assert resp.status == 200
    data = await resp.json()
    assert data["ok"] is True

@pytest.mark.asyncio
async def test_push_send_success(aiohttp_client, central_app, auth_headers, monkeypatch):
    pushed_payload = None
    async def mock_send_push(self, payload):
        nonlocal pushed_payload
        pushed_payload = payload
    monkeypatch.setattr(OdiseaCentral, "send_push_to_all", mock_send_push)

    client = await aiohttp_client(central_app)
    payload = {"message": "test push"}
    resp = await client.post('/push/send', 
                             headers=auth_headers,
                             json=payload)
    assert resp.status == 200
    assert pushed_payload == payload
