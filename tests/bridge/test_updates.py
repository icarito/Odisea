import asyncio
import base64
import hashlib
import json
import time
import pytest
from aiohttp import web
from odisea_central import OdiseaCentral, MANIFEST_ACCEPT_HEADER

@pytest.fixture
def central():
    return OdiseaCentral()

def make_signed_envelope(payload):
    payload_json = json.dumps(payload).encode("utf-8")
    payload_b64 = base64.b64encode(payload_json).decode("utf-8")
    envelope = {
        "schema_version": 1,
        "payload_b64": payload_b64,
        "signatures": [
            {
                "algorithm": "RSASSA-PKCS1-v1_5-SHA256",
                "key_id": "test-key",
                "value_b64": "fake-signature"
            }
        ]
    }
    return json.dumps(envelope).encode("utf-8")

async def test_update_manifest_400_invalid_accept(central, aiohttp_client):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    resp = await client.get('/game/updates/v1/manifest')
    assert resp.status == 400
    data = await resp.json()
    assert data["error"] == "invalid_accept_header"

async def test_update_manifest_400_missing_params(central, aiohttp_client):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    headers = {"Accept": MANIFEST_ACCEPT_HEADER}
    resp = await client.get('/game/updates/v1/manifest', headers=headers)
    assert resp.status == 400
    data = await resp.json()
    assert data["error"] == "missing_parameters"

async def test_update_manifest_200_ok(central, aiohttp_client, monkeypatch):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    payload = {
        "version": "0.3.3",
        "build_id": "12346",
        "min_supported_version": "0.3.0"
    }
    content = make_signed_envelope(payload)

    async def mock_get_manifest(self, channel, platform, arch):
        return {
            "ts": time.time(),
            "etag": "fake-etag",
            "content": content
        }

    monkeypatch.setattr(OdiseaCentral, "_get_manifest", mock_get_manifest)

    headers = {"Accept": MANIFEST_ACCEPT_HEADER}
    params = {
        "channel": "release",
        "platform": "linux",
        "arch": "x86_64",
        "current_version": "0.3.2",
        "current_build_id": "12345"
    }
    resp = await client.get('/game/updates/v1/manifest', headers=headers, params=params)
    assert resp.status == 200
    assert await resp.read() == content
    assert resp.headers["ETag"] == '"fake-etag"'

async def test_update_manifest_204_already_updated(central, aiohttp_client, monkeypatch):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    payload = {
        "version": "0.3.3",
        "build_id": "12346",
        "min_supported_version": "0.3.0"
    }
    content = make_signed_envelope(payload)

    async def mock_get_manifest(self, channel, platform, arch):
        return {
            "ts": time.time(),
            "etag": "fake-etag",
            "content": content
        }

    monkeypatch.setattr(OdiseaCentral, "_get_manifest", mock_get_manifest)

    headers = {"Accept": MANIFEST_ACCEPT_HEADER}
    params = {
        "channel": "release",
        "platform": "linux",
        "arch": "x86_64",
        "current_version": "0.3.3",
        "current_build_id": "12346"
    }
    resp = await client.get('/game/updates/v1/manifest', headers=headers, params=params)
    assert resp.status == 204

async def test_update_manifest_409_unsupported_version(central, aiohttp_client, monkeypatch):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    payload = {
        "version": "0.3.3",
        "build_id": "12346",
        "min_supported_version": "0.3.0"
    }
    content = make_signed_envelope(payload)

    async def mock_get_manifest(self, channel, platform, arch):
        return {
            "ts": time.time(),
            "etag": "fake-etag",
            "content": content
        }

    monkeypatch.setattr(OdiseaCentral, "_get_manifest", mock_get_manifest)

    headers = {"Accept": MANIFEST_ACCEPT_HEADER}
    params = {
        "channel": "release",
        "platform": "linux",
        "arch": "x86_64",
        "current_version": "0.2.9",
        "current_build_id": "10000"
    }
    resp = await client.get('/game/updates/v1/manifest', headers=headers, params=params)
    assert resp.status == 409
    assert await resp.read() == content

async def test_update_manifest_304_not_modified(central, aiohttp_client, monkeypatch):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    async def mock_get_manifest(self, channel, platform, arch):
        return {
            "ts": time.time(),
            "etag": "fake-etag",
            "content": b"some-content"
        }

    monkeypatch.setattr(OdiseaCentral, "_get_manifest", mock_get_manifest)

    headers = {
        "Accept": MANIFEST_ACCEPT_HEADER,
        "If-None-Match": '"fake-etag"'
    }
    params = {
        "channel": "release",
        "platform": "linux",
        "arch": "x86_64",
        "current_version": "0.3.2",
        "current_build_id": "12345"
    }
    resp = await client.get('/game/updates/v1/manifest', headers=headers, params=params)
    assert resp.status == 304

async def test_update_manifest_503_origin_down(central, aiohttp_client, monkeypatch):
    app = web.Application()
    app.router.add_get('/game/updates/v1/manifest', central.handle_update_manifest)
    client = await aiohttp_client(app)

    async def mock_get_manifest(self, channel, platform, arch):
        return None

    monkeypatch.setattr(OdiseaCentral, "_get_manifest", mock_get_manifest)

    headers = {"Accept": MANIFEST_ACCEPT_HEADER}
    params = {
        "channel": "release",
        "platform": "linux",
        "arch": "x86_64",
        "current_version": "0.3.2",
        "current_build_id": "12345"
    }
    resp = await client.get('/game/updates/v1/manifest', headers=headers, params=params)
    assert resp.status == 503
