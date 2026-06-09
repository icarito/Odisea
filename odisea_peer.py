import asyncio
import json
import logging
import os
import time
import uuid
from typing import Dict, Any, Optional

from aiohttp import web, ClientWebSocketResponse
from zeroconf.asyncio import AsyncZeroconf

# Configuration from environment variables
PEER_PORT = int(os.environ.get("PEER_PORT", 4999))
ANNA_HOST = os.environ.get("ANNA_HOST", "127.0.0.1")
ANNA_PORT = int(os.environ.get("ANNA_PORT", 5000))
CENTRAL_WS_URL = os.environ.get("CENTRAL_WS_URL", "ws://35.182.238.36:5003/ws")
# Dev-only default; PRODUCTION must set ODISEA_BRIDGE_TOKEN to a real secret. See FD-162.
DEV_DEFAULT_TOKEN = "odisea-dev-insecure"
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", DEV_DEFAULT_TOKEN)

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_peer")

class OdiseaPeer:
    def __init__(self):
        self.peer_id = f"peer-{uuid.uuid4().hex[:8]}"
        self.hostname = os.uname().nodename
        self.ip_address = "127.0.0.1"
        self.heartbeats: Dict[str, dict] = {}
        self.central_ws: Optional[ClientWebSocketResponse] = None
        self.zeroconf: Optional[AsyncZeroconf] = None
        self.godot_ws: Optional[web.WebSocketResponse] = None
        self.command_history = []  # timestamps of last commands for rate limiting

        logger.info(f"Initialized Peer: peer_id={self.peer_id}, hostname={self.hostname}, ip={self.ip_address}")

    async def connect_to_central(self):
        ws = await web.ClientSession().ws_connect(CENTRAL_WS_URL)
        self.central_ws = ws

        await ws.send_json({
            "type": "handshake",
            "peer_id": self.peer_id,
            "token": BRIDGE_TOKEN
        })

        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    if data.get("type") == "handshake_ack":
                        logger.info("Handshake with central successful.")
                    elif data.get("type") == "command":
                        if self.godot_ws and not self.godot_ws.closed:
                            logger.info(f"Relaying command from central: {data.get('action')} ({data.get('id')})")
                            await self.godot_ws.send_json(data)
                        else:
                            logger.warning("Central command received but no Godot client connected.")
                            await ws.send_json({
                                "type": "command_response",
                                "id": data.get("id"),
                                "ok": False,
                                "error": "Godot client not connected to peer"
                            })
                    elif data.get("type") == "error":
                        logger.error(f"Central error: {data.get('error')}")
                except Exception as e:
                    logger.error(f"Error handling message: {e}")
            elif msg.type in (web.WSMsgType.CLOSED, web.WSMsgType.ERROR):
                logger.error(f"Central connection closed: {ws.exception()}")
                break

    async def handle_godot_client(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        logger.info("New Godot client connected via WebSocket.")
        self.godot_ws = ws

        logged_type = False
        try:
            async for msg in ws:
                if msg.type in (web.WSMsgType.TEXT, web.WSMsgType.BINARY):
                    if not logged_type:
                        logger.info(f"First WS frame type from client: {msg.type.name}")
                        logged_type = True
                    try:
                        raw = msg.data
                        if isinstance(raw, (bytes, bytearray)):
                            raw = raw.decode("utf-8")
                        data = json.loads(raw)
                        msg_type = data.get("type")
                        if msg_type == "heartbeat":
                            player_id = data.get("player_id")
                            if player_id:
                                data["peer_id"] = self.peer_id
                                self.heartbeats[player_id] = data
                                if self.central_ws and not self.central_ws.closed:
                                    await self.central_ws.send_json(data)
                        elif msg_type == "command_response":
                            if self.central_ws and not self.central_ws.closed:
                                logger.info(f"Relaying command_response to central: {data.get('id')}")
                                await self.central_ws.send_json(data)
                    except Exception as e:
                        logger.error(f"Error handling message: {e}")
                elif msg.type == web.WSMsgType.ERROR:
                    logger.error(f"WebSocket connection closed with exception {ws.exception()}")
        finally:
            if self.godot_ws == ws:
                self.godot_ws = None
            logger.info("Godot client disconnected.")
        return ws

    async def handle_command(self, request):
        now = time.time()
        self.command_history = [t for t in self.command_history if now - t < 1.0]
        if len(self.command_history) >= 10:
            return web.json_response({"error": "rate_limited", "message": "Too many commands (max 10/s)"}, status=429)
        self.command_history.append(now)

        if request.method == "GET":
            action = request.query.get("action")
            args = dict(request.query)
            if "action" in args:
                del args["action"]
        else:
            try:
                body = await request.json()
                action = body.get("action")
                args = body.get("args", {})
            except Exception:
                return web.json_response({"error": "invalid_json"}, status=400)

        if not action:
            return web.json_response({"error": "missing_action"}, status=400)

        command = {"action": action, "args": args, "id": str(uuid.uuid4())[:8]}

        try:
            reader, writer = await asyncio.wait_for(asyncio.open_connection(ANNA_HOST, ANNA_PORT), timeout=2.0)
            writer.write((json.dumps(command) + "\n").encode())
            await writer.drain()

            response_data = await asyncio.wait_for(reader.readuntil(b"\n"), timeout=5.0)
            writer.close()
            await writer.wait_closed()

            return web.json_response(json.loads(response_data.decode()))
        except asyncio.TimeoutError:
            return web.json_response({"error": "timeout", "message": "ANNA MCP took too long to respond"}, status=504)
        except Exception as e:
            logger.error(f"TCP Command forward failed: {e}")
            return web.json_response({
                "error": "ANNA MCP not available",
                "message": str(e),
                "hint": "Ensure Godot is running with ANNA enabled on Desktop/Android"
            }, status=502)

    async def handle_health(self, request):
        return web.json_response({
            "ok": True,
            "mode": "peer",
            "peer_id": self.peer_id,
            "godot_connected": self.godot_ws is not None and not self.godot_ws.closed,
            "central_connected": self.central_ws is not None and not self.central_ws.closed
        })

    async def handle_index(self, request):
        return web.Response(text="<h1>Odisea Peer</h1><p>Peer node running.</p>", content_type="text/html")

    async def handle_sessions(self, request):
        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_peers(self, request):
        return web.json_response({"peer_id": self.peer_id, "hostname": self.hostname})

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/', self.handle_index),
            web.get('/health', self.handle_health),
            web.get('/sessions', self.handle_sessions),
            web.get('/peers', self.handle_peers),
            web.get('/command', self.handle_command),
            web.post('/command', self.handle_command),
            web.get('/ws', self.handle_godot_client),
        ])

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', PEER_PORT)
        await site.start()
        logger.info(f"Odisea Peer running on port {PEER_PORT}")

        # Start central connection in background
        asyncio.create_task(self.connect_to_central())

        try:
            while True:
                await asyncio.sleep(3600)
        finally:
            await runner.cleanup()

if __name__ == "__main__":
    if BRIDGE_TOKEN == DEV_DEFAULT_TOKEN:
        logger.warning("Using INSECURE dev default token. Set ODISEA_BRIDGE_TOKEN for production.")

    peer = OdiseaPeer()
    try:
        asyncio.run(peer.run())
    except KeyboardInterrupt:
        pass
