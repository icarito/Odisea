import asyncio
import json
import logging
import os
import socket
import time
import uuid
from typing import Dict, Optional

from aiohttp import web, WSCloseCode, ClientSession, ClientWebSocketResponse
from zeroconf import IPVersion, ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

# Configuration from environment variables
PEER_PORT = int(os.environ.get("PEER_PORT", 4999))
CENTRAL_WS_URL = os.environ.get("CENTRAL_WS_URL", "ws://35.182.238.36:5003/ws")
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", "")

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_peer")

class OdiseaPeer:
    def __init__(self):
        self.peer_id = str(uuid.uuid4()) # Ephemeral peer_id for this run
        self.hostname = socket.gethostname()
        self.ip_address = self._get_ip()
        self.heartbeats: Dict[str, dict] = {}
        self.central_ws: Optional[ClientWebSocketResponse] = None
        self.zeroconf: Optional[AsyncZeroconf] = None

        logger.info(f"Initialized Peer: peer_id={self.peer_id}, hostname={self.hostname}, ip={self.ip_address}")

    def _get_ip(self) -> str:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # doesn't even have to be reachable
            s.connect(('10.255.255.255', 1))
            ip = s.getsockname()[0]
        except Exception:
            ip = '127.0.0.1'
        finally:
            s.close()
        return ip

    async def start_mdns(self):
        try:
            self.zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
            desc = {'version': '0.1.0'}
            info = ServiceInfo(
                "_odisea._tcp.local.",
                f"Odisea-Peer-{self.hostname}._odisea._tcp.local.",
                addresses=[socket.inet_aton(self.ip_address)],
                port=PEER_PORT,
                properties=desc,
                server=f"{self.hostname}.local.",
            )
            logger.info(f"Registering mDNS service: {info.name} on {self.ip_address}:{PEER_PORT}")
            await self.zeroconf.async_register_service(info)
        except Exception as e:
            logger.error(f"mDNS registration failed: {e}")

    async def stop_mdns(self):
        if self.zeroconf:
            await self.zeroconf.async_unregister_all_services()
            await self.zeroconf.async_close()

    async def connect_to_central(self):
        while True:
            try:
                async with ClientSession() as session:
                    logger.info(f"Connecting to central server at {CENTRAL_WS_URL}...")
                    async with session.ws_connect(CENTRAL_WS_URL) as ws:
                        self.central_ws = ws
                        # Send handshake
                        await ws.send_json({
                            "type": "handshake",
                            "token": BRIDGE_TOKEN,
                            "peer_id": self.peer_id
                        })

                        # Wait for handshake ack or messages
                        async for msg in ws:
                            if msg.type == web.WSMsgType.TEXT:
                                data = json.loads(msg.data)
                                if data.get("type") == "handshake_ack":
                                    logger.info("Handshake with central successful.")
                                elif data.get("type") == "error":
                                    logger.error(f"Central error: {data.get('error')}")
                            elif msg.type in (web.WSMsgType.CLOSED, web.WSMsgType.ERROR):
                                break
            except Exception as e:
                logger.error(f"Connection to central failed: {e}. Retrying in 5s...")

            self.central_ws = None
            await asyncio.sleep(5)

    async def handle_ws(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        logger.info("New Godot client connected via WebSocket.")

        logged_type = False
        async for msg in ws:
            # Godot 3's WebSocketClient defaults to BINARY write mode, so heartbeats
            # may arrive as BINARY frames carrying UTF-8 JSON. Accept both.
            if msg.type in (web.WSMsgType.TEXT, web.WSMsgType.BINARY):
                if not logged_type:
                    logger.info(f"First WS frame type from client: {msg.type.name}")
                    logged_type = True
                try:
                    raw = msg.data
                    if isinstance(raw, (bytes, bytearray)):
                        raw = raw.decode("utf-8")
                    data = json.loads(raw)
                    if data.get("type") == "heartbeat":
                        player_id = data.get("player_id")
                        if player_id:
                            # Inject peer_id into heartbeat
                            data["peer_id"] = self.peer_id
                            self.heartbeats[player_id] = data
                            # Relay flat heartbeat to central
                            if self.central_ws and not self.central_ws.closed:
                                await self.central_ws.send_json(data)
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
            elif msg.type == web.WSMsgType.ERROR:
                logger.error(f"WebSocket connection closed with exception {ws.exception()}")

        logger.info("Godot client disconnected.")
        return ws

    async def handle_index(self, request):
        return web.Response(text="Odisea Bridge Peer is running.")

    async def handle_status(self, request):
        player_id = request.query.get("player_id")
        if player_id:
            hb = self.heartbeats.get(player_id)
            if hb:
                return web.json_response(hb)
            else:
                return web.json_response({"error": "player not found"}, status=404)
        return web.json_response(self.heartbeats)

    async def handle_sessions(self, request):
        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_health(self, request):
        return web.json_response({
            "ok": True,
            "mode": "peer",
            "players_known": len(self.heartbeats),
            "central_connected": self.central_ws is not None and not self.central_ws.closed
        })

    async def handle_peers(self, request):
        return web.json_response(list(self.heartbeats.keys()))

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/', self.handle_index),
            web.get('/ws', self.handle_ws),
            web.get('/status', self.handle_status),
            web.get('/sessions', self.handle_sessions),
            web.get('/health', self.handle_health),
            web.get('/peers', self.handle_peers),
        ])

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', PEER_PORT)
        await site.start()

        logger.info(f"HTTP/WS server started on port {PEER_PORT}")

        await self.start_mdns()

        # Run central connection in background
        central_task = asyncio.create_task(self.connect_to_central())

        try:
            # Keep the main loop running
            while True:
                await asyncio.sleep(3600)
        finally:
            await self.stop_mdns()
            await runner.cleanup()
            central_task.cancel()

if __name__ == "__main__":
    peer = OdiseaPeer()
    try:
        asyncio.run(peer.run())
    except KeyboardInterrupt:
        pass
