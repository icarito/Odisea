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
        self.peer_id = str(uuid.uuid4()) # Ephemeral peer_id for this run
        self.hostname = socket.gethostname()
        self.ip_address = self._get_ip()
        self.heartbeats: Dict[str, dict] = {}
        self.central_ws: Optional[ClientWebSocketResponse] = None
        self.zeroconf: Optional[AsyncZeroconf] = None
        self.godot_ws: Optional[web.WebSocketResponse] = None
        self.command_history = [] # timestamps of last commands for rate limiting

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
                                elif data.get("type") == "command":
                                    # Forward to Godot via established WS
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
        self.godot_ws = ws

        logged_type = False
        try:
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
                        msg_type = data.get("type")
                        if msg_type == "heartbeat":
                            player_id = data.get("player_id")
                            if player_id:
                                # Inject peer_id into heartbeat
                                data["peer_id"] = self.peer_id
                                self.heartbeats[player_id] = data
                                # Relay flat heartbeat to central
                                if self.central_ws and not self.central_ws.closed:
                                    await self.central_ws.send_json(data)
                        elif msg_type == "command_response":
                            # Relay response back to central
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

    async def handle_command(self, request):
        # Rate limiting: 10 commands per second
        now = time.time()
        self.command_history = [t for t in self.command_history if now - t < 1.0]
        if len(self.command_history) >= 10:
            return web.json_response({"error": "rate_limited", "message": "Too many commands (max 10/s)"}, status=429)
        self.command_history.append(now)

        # Parse args from query string (GET) or body (POST)
        if request.method == "GET":
            action = request.query.get("action")
            # For GET, we support simple path-based inspect or execute_script with ?script=
            args = dict(request.query)
            if "action" in args: del args["action"]
        else:
            try:
                body = await request.json()
                action = body.get("action")
                args = body.get("args", {})
            except Exception:
                return web.json_response({"error": "invalid_json"}, status=400)

        if not action:
            return web.json_response({"error": "missing_action"}, status=400)

        # Forward to ANNA MCP via TCP
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
            web.get('/command', self.handle_command),
            web.post('/command', self.handle_command),
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
