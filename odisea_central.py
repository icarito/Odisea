import asyncio
import json
import logging
import os
import time
from typing import Dict, Any

from aiohttp import web, WSCloseCode

# Configuration from environment variables
CENTRAL_HTTP_PORT = int(os.environ.get("CENTRAL_HTTP_PORT", 5003))
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", "")
CACHE_TTL = int(os.environ.get("CENTRAL_CACHE_TTL", 60))
STORE_GHOSTS = os.environ.get("CENTRAL_STORE_GHOSTS", "false").lower() == "true"
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_central")

class OdiseaCentral:
    def __init__(self):
        self.heartbeats: Dict[str, dict] = {} # player_id -> heartbeat
        self.last_update: Dict[str, float] = {} # player_id -> timestamp
        self.session_rate_limit: Dict[str, float] = {} # session_id -> last_heartbeat_time
        self.active_peers = set() # set of active WebSocket objects

        if STORE_GHOSTS and not os.path.exists(GHOSTS_DIR):
            os.makedirs(GHOSTS_DIR, exist_ok=True)
            logger.info(f"Created ghosts directory: {GHOSTS_DIR}")

    def _is_authorized(self, request):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return False
        token = auth_header[7:]
        return token == BRIDGE_TOKEN

    async def _clean_cache(self):
        while True:
            now = time.time()
            # Clean heartbeats
            to_delete_hb = [pid for pid, last in self.last_update.items() if now - last > CACHE_TTL]
            for pid in to_delete_hb:
                logger.info(f"Expiring cache for player_id: {pid}")
                self.heartbeats.pop(pid, None)
                self.last_update.pop(pid, None)

            # Clean session rate limits (TTL = CACHE_TTL * 2 to be safe)
            to_delete_sessions = [sid for sid, last in self.session_rate_limit.items() if now - last > CACHE_TTL * 2]
            for sid in to_delete_sessions:
                self.session_rate_limit.pop(sid, None)

            await asyncio.sleep(10)

    async def handle_ws(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)

        peer_id = None
        authenticated = False
        self.active_peers.add(ws)

        logger.info("New peer connection attempt.")

        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        msg_type = data.get("type")

                        if not authenticated:
                            if msg_type == "handshake":
                                token = data.get("token")
                                if token == BRIDGE_TOKEN:
                                    authenticated = True
                                    peer_id = data.get("peer_id", "unknown")
                                    logger.info(f"Peer authenticated: {peer_id}")
                                    await ws.send_json({"type": "handshake_ack", "status": "ok"})
                                else:
                                    logger.warning(f"Peer authentication failed. Invalid token.")
                                    await ws.send_json({"type": "error", "error": "invalid_token"})
                                    await ws.close(code=WSCloseCode.POLICY_VIOLATION)
                                    break
                            else:
                                logger.warning("Peer sent message before handshake.")
                                await ws.close(code=WSCloseCode.POLICY_VIOLATION)
                                break

                        elif msg_type == "heartbeat":
                            player_id = data.get("player_id")
                            session_id = data.get("session_id")

                            if not player_id or not session_id:
                                continue

                            # Rate limiting: 1 heartbeat per 50ms per session_id
                            now = time.time()
                            last_time = self.session_rate_limit.get(session_id, 0)
                            if now - last_time < 0.05:
                                # logger.debug(f"Rate limiting heartbeat for session {session_id}")
                                continue

                            self.session_rate_limit[session_id] = now

                            # Update cache
                            self.heartbeats[player_id] = data
                            self.last_update[player_id] = now

                            # Store ghosts
                            if STORE_GHOSTS:
                                self._store_ghost(player_id, session_id, data)

                    except Exception as e:
                        logger.error(f"Error processing peer message: {e}")
                elif msg.type == web.WSMsgType.ERROR:
                    logger.error(f"Peer connection closed with exception {ws.exception()}")

        finally:
            self.active_peers.discard(ws)
            logger.info(f"Peer disconnected: {peer_id}")

        return ws

    def _store_ghost(self, player_id: str, session_id: str, heartbeat: dict):
        try:
            player_dir = os.path.join(GHOSTS_DIR, player_id)
            os.makedirs(player_dir, exist_ok=True)
            filepath = os.path.join(player_dir, f"{session_id}.jsonl")
            with open(filepath, "a") as f:
                f.write(json.dumps(heartbeat) + "\n")
        except Exception as e:
            logger.error(f"Failed to store ghost: {e}")

    async def handle_status(self, request):
        if not self._is_authorized(request):
            return web.json_response({"error": "unauthorized"}, status=401)

        player_id = request.query.get("player_id")
        if player_id:
            hb = self.heartbeats.get(player_id)
            if hb:
                return web.json_response(hb)
            else:
                return web.json_response({"error": "player not found"}, status=404)
        return web.json_response(self.heartbeats)

    async def handle_sessions(self, request):
        if not self._is_authorized(request):
            return web.json_response({"error": "unauthorized"}, status=401)

        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_health(self, request):
        # Public endpoint
        return web.json_response({
            "ok": True,
            "mode": "central",
            "peers_connected": len(self.active_peers)
        })

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/ws', self.handle_ws),
            web.get('/status', self.handle_status),
            web.get('/sessions', self.handle_sessions),
            web.get('/health', self.handle_health),
        ])

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', CENTRAL_HTTP_PORT)
        await site.start()

        logger.info(f"Central server started on port {CENTRAL_HTTP_PORT}")

        # Run cleanup task in background
        cleanup_task = asyncio.create_task(self._clean_cache())

        try:
            while True:
                await asyncio.sleep(3600)
        finally:
            cleanup_task.cancel()
            await runner.cleanup()

if __name__ == "__main__":
    if not BRIDGE_TOKEN:
        logger.error("ODISEA_BRIDGE_TOKEN environment variable is required.")
        exit(1)

    central = OdiseaCentral()
    try:
        asyncio.run(central.run())
    except KeyboardInterrupt:
        pass
