import asyncio
import json
import logging
import os
import time
import datetime
from typing import Dict, Any, List, Set, Optional

from aiohttp import web, WSCloseCode

# --- Configuration ---
CENTRAL_HTTP_PORT = int(os.environ.get("CENTRAL_HTTP_PORT", 5003))
DEV_DEFAULT_TOKEN = "odisea-dev-insecure"
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", DEV_DEFAULT_TOKEN)

CACHE_TTL = int(os.environ.get("CENTRAL_CACHE_TTL", 120))
STORE_GHOSTS = os.environ.get("CENTRAL_STORE_GHOSTS", "true").lower() == "true"
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
GHOSTS_MAX_BYTES = int(os.environ.get("CENTRAL_GHOSTS_MAX_BYTES", 104857600)) # 100MB

AUTH_MAX_FAILS = int(os.environ.get("CENTRAL_AUTH_MAX_FAILS", 8))
AUTH_FAIL_WINDOW = int(os.environ.get("CENTRAL_AUTH_FAIL_WINDOW", 60))
AUTH_LOCKOUT = int(os.environ.get("CENTRAL_AUTH_LOCKOUT", 300))

# --- Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_central")

class MetricsCollector:
    def __init__(self):
        self.started_at = datetime.datetime.now(datetime.timezone.utc)
        self.heartbeats_total = 0
        self.errors_total = 0
        self.sessions_seen: Set[str] = set()
        self.cache_hits = 0
        self.cache_lookups = 0

    def record_heartbeat(self, session_id: str):
        self.heartbeats_total += 1
        if session_id:
            self.sessions_seen.add(session_id)

    def record_error(self):
        self.errors_total += 1

    def record_cache_lookup(self, hit: bool):
        self.cache_lookups += 1
        if hit:
            self.cache_hits += 1

    def get_metrics(self, central: 'OdiseaCentral') -> Dict[str, Any]:
        now = datetime.datetime.now(datetime.timezone.utc)
        uptime = (now - self.started_at).total_seconds()

        ghosts_bytes = 0
        if os.path.exists(GHOSTS_DIR):
            for root, dirs, files in os.walk(GHOSTS_DIR):
                for f in files:
                    try: ghosts_bytes += os.path.getsize(os.path.join(root, f))
                    except: pass

        memory_mb = 0
        try:
            import psutil
            process = psutil.Process(os.getpid())
            memory_mb = process.memory_info().rss / (1024 * 1024)
        except ImportError:
            pass

        return {
            "ok": True,
            "mode": "central",
            "started_at": self.started_at.isoformat(),
            "uptime_seconds": int(uptime),
            "peers_connected": len(central.active_peers),
            "heartbeats_total": self.heartbeats_total,
            "heartbeats_rate": round(self.heartbeats_total / uptime, 2) if uptime > 0 else 0,
            "sessions_total": len(self.sessions_seen),
            "errors_total": self.errors_total,
            "errors_rate": round(self.errors_total / self.heartbeats_total, 4) if self.heartbeats_total > 0 else 0,
            "cache_size": len(central.heartbeats),
            "cache_hit_ratio": round(self.cache_hits / self.cache_lookups, 2) if self.cache_lookups > 0 else 0,
            "ghosts_enabled": STORE_GHOSTS,
            "ghosts_bytes": ghosts_bytes,
            "memory_mb": round(memory_mb, 1)
        }

class OdiseaCentral:
    def __init__(self):
        self.heartbeats: Dict[str, dict] = {} # player_id -> heartbeat
        self.last_update: Dict[str, float] = {} # player_id -> timestamp
        self.session_rate_limit: Dict[str, float] = {} # session_id -> last_heartbeat_time
        self.active_peers: Set[web.WebSocketResponse] = set()
        self.event_subscribers: Set[web.WebSocketResponse] = set()
        self.auth_fails: Dict[str, dict] = {} # ip -> {"ts": [failure timestamps], "locked_until": float}
        self.metrics = MetricsCollector()
        self.ghost_rotation_counter: Dict[str, int] = {} # pid -> count

        if STORE_GHOSTS and not os.path.exists(GHOSTS_DIR):
            os.makedirs(GHOSTS_DIR, exist_ok=True)
            logger.info(f"Created ghosts directory: {GHOSTS_DIR}")

    # --- Auth Logic ---
    def _is_authorized(self, request):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return False
        token = auth_header[7:]
        return token == BRIDGE_TOKEN

    def _client_ip(self, request) -> str:
        fwd = request.headers.get("X-Forwarded-For", "")
        if fwd:
            return fwd.split(",")[0].strip()
        return request.remote or "unknown"

    def _is_locked(self, ip: str, now: float) -> bool:
        entry = self.auth_fails.get(ip)
        return bool(entry and entry.get("locked_until", 0) > now)

    def _record_auth_fail(self, ip: str, now: float) -> None:
        entry = self.auth_fails.setdefault(ip, {"ts": [], "locked_until": 0})
        entry["ts"] = [t for t in entry["ts"] if now - t < AUTH_FAIL_WINDOW]
        entry["ts"].append(now)
        if len(entry["ts"]) >= AUTH_MAX_FAILS:
            entry["locked_until"] = now + AUTH_LOCKOUT
            entry["ts"] = []
            logger.warning(f"Auth brute-force lockout for IP {ip} ({AUTH_LOCKOUT}s)")

    def _auth_guard(self, request):
        ip = self._client_ip(request)
        now = time.time()
        if self._is_locked(ip, now):
            retry = int(self.auth_fails[ip]["locked_until"] - now)
            return web.json_response(
                {"error": "rate_limited", "retry_after": retry},
                status=429, headers={"Retry-After": str(max(1, retry))},
            )
        if not self._is_authorized(request):
            self._record_auth_fail(ip, now)
            return web.json_response({"error": "unauthorized"}, status=401)
        self.auth_fails.pop(ip, None)
        return None

    async def _cleanup_loop(self):
        while True:
            try:
                now = time.time()
                to_delete_hb = [pid for pid, last in self.last_update.items() if now - last > CACHE_TTL]
                for pid in to_delete_hb:
                    self.heartbeats.pop(pid, None)
                    self.last_update.pop(pid, None)

                to_delete_auth = [ip for ip, entry in self.auth_fails.items()
                                 if entry.get("locked_until", 0) <= now and not any(now - t < AUTH_FAIL_WINDOW for t in entry.get("ts", []))]
                for ip in to_delete_auth:
                    self.auth_fails.pop(ip, None)
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}")
            await asyncio.sleep(60)

    # --- Request Handlers ---
    async def handle_health(self, request):
        return web.json_response(self.metrics.get_metrics(self))

    async def handle_status(self, request):
        guard = self._auth_guard(request)
        if guard: return guard

        player_id = request.query.get("player_id")
        self.metrics.record_cache_lookup(player_id in self.heartbeats if player_id else True)

        if player_id:
            hb = self.heartbeats.get(player_id)
            return web.json_response(hb) if hb else web.json_response({"error":"not_found"}, status=404)
        return web.json_response(self.heartbeats)

    async def handle_sessions(self, request):
        guard = self._auth_guard(request)
        if guard: return guard
        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_sessions_history(self, request):
        guard = self._auth_guard(request)
        if guard: return guard

        history = []
        if os.path.exists(GHOSTS_DIR):
            for pid in os.listdir(GHOSTS_DIR):
                p_path = os.path.join(GHOSTS_DIR, pid)
                if not os.path.isdir(p_path): continue
                for sid_file in os.listdir(p_path):
                    if not sid_file.endswith(".jsonl"): continue
                    sid = sid_file[:-6]
                    f_path = os.path.join(p_path, sid_file)
                    try:
                        stats = os.stat(f_path)
                        history.append({
                            "session_id": sid,
                            "player_id": pid,
                            "size_bytes": stats.st_size,
                            "mtime": stats.st_mtime
                        })
                    except: pass
        return web.json_response(history)

    async def handle_ghosts(self, request):
        guard = self._auth_guard(request)
        if guard: return guard

        pid = request.query.get("player_id")
        sid = request.query.get("session_id")
        if not pid or not sid:
            return web.json_response({"error":"missing parameters"}, status=400)

        path = os.path.join(GHOSTS_DIR, pid, f"{sid}.jsonl")
        if not os.path.exists(path):
            return web.json_response({"error":"ghost not found"}, status=404)

        return web.FileResponse(path)

    async def handle_command(self, request):
        guard = self._auth_guard(request)
        if guard: return guard

        try:
            cmd = await request.json()
            for ws in self.active_peers:
                await ws.send_json({"type": "command", "payload": cmd})
            return web.json_response({"ok": True, "broadcast_to": len(self.active_peers)})
        except Exception as e:
            return web.json_response({"error": str(e)}, status=400)

    async def handle_ws(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        self.active_peers.add(ws)

        peer_id = "unknown"
        # Optional token for HTML5/WS as per spec FD-166 "aceptar sin token" / "WS /ws Opcional"
        authenticated = False

        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                    except json.JSONDecodeError:
                        logger.warning("Received malformed JSON from peer")
                        continue

                    mtype = data.get("type")

                    if not authenticated:
                        if mtype == "handshake":
                            if data.get("token") == BRIDGE_TOKEN:
                                authenticated = True
                                peer_id = data.get("peer_id", "unknown")
                                await ws.send_json({"type": "handshake_ack", "status": "ok"})
                            else:
                                # HTML5 client might not have token, allow heartbeat without handshake?
                                # Spec says "WS /ws Opcional". Let's treat unauthenticated as "HTML5 mode"
                                logger.info("Peer connecting without valid token (HTML5 mode)")
                                authenticated = True
                                peer_id = "html5-" + data.get("peer_id", "unknown")
                                await ws.send_json({"type": "handshake_ack", "status": "anonymous"})
                        elif mtype == "heartbeat":
                            # Allow heartbeats without handshake for "Opcional" WS
                            authenticated = True
                            await self._process_heartbeat(data)
                    elif mtype == "heartbeat":
                        await self._process_heartbeat(data)
        finally:
            self.active_peers.discard(ws)
        return ws

    async def _process_heartbeat(self, data):
        pid = data.get("player_id")
        sid = data.get("session_id")
        if pid and sid:
            now = time.time()
            if now - self.session_rate_limit.get(sid, 0) < 0.05: return
            self.session_rate_limit[sid] = now

            self.heartbeats[pid] = data
            self.last_update[pid] = now
            self.metrics.record_heartbeat(sid)

            if self.metrics.heartbeats_total % 100 == 0:
                logger.info(f"Heartbeat 100x: {pid}")

            if STORE_GHOSTS:
                self._store_ghost(pid, sid, data)

            for sub in self.event_subscribers:
                try: await sub.send_json(data)
                except: pass

    async def handle_events_ws(self, request):
        guard = self._auth_guard(request)
        if guard: return guard

        ws = web.WebSocketResponse()
        await ws.prepare(request)
        self.event_subscribers.add(ws)
        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.CLOSE: break
        finally:
            self.event_subscribers.discard(ws)
        return ws

    def _store_ghost(self, pid: str, sid: str, data: dict):
        try:
            p_dir = os.path.join(GHOSTS_DIR, pid)
            os.makedirs(p_dir, exist_ok=True)

            # Efficient rotation check: every 100 heartbeats for this player
            self.ghost_rotation_counter[pid] = self.ghost_rotation_counter.get(pid, 0) + 1
            if self.ghost_rotation_counter[pid] >= 100:
                self.ghost_rotation_counter[pid] = 0
                files = [os.path.join(p_dir, f) for f in os.listdir(p_dir) if f.endswith(".jsonl")]
                total_size = sum(os.path.getsize(f) for f in files)
                if total_size > GHOSTS_MAX_BYTES:
                    files.sort(key=lambda x: os.path.getmtime(x))
                    while total_size > GHOSTS_MAX_BYTES * 0.8 and files:
                        oldest = files.pop(0)
                        total_size -= os.path.getsize(oldest)
                        os.remove(oldest)
                        logger.info(f"Rotated ghost for {pid}: deleted {oldest}")

            with open(os.path.join(p_dir, f"{sid}.jsonl"), "a") as f:
                f.write(json.dumps(data) + "\n")
        except Exception as e:
            self.metrics.record_error()
            logger.error(f"Ghost error: {e}")

    async def handle_dashboard(self, request):
        # Serve React SPA if exists, else fall back to a basic embedded status page
        if os.path.exists('./static/dashboard/index.html'):
            return web.FileResponse('./static/dashboard/index.html')
        return web.Response(text="<h1>Odisea Central V2</h1><p>Dashboard SPA not found. Check /health for metrics.</p>", content_type="text/html")

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/health', self.handle_health),
            web.get('/status', self.handle_status),
            web.get('/sessions', self.handle_sessions),
            web.get('/sessions/history', self.handle_sessions_history),
            web.get('/ghosts', self.handle_ghosts),
            web.post('/command', self.handle_command),
            web.get('/ws', self.handle_ws),
            web.get('/events', self.handle_events_ws),
            web.get('/dashboard', self.handle_dashboard),
            web.static('/dashboard/', './static/dashboard') if os.path.exists('./static/dashboard') else web.get('/dashboard/', lambda r: web.Response(status=404)),
        ])

        if os.path.exists('./static/assets'):
            app.add_routes([web.static('/assets', './static/assets')])
        else:
            app.add_routes([web.get('/assets/{tail:.*}', lambda r: web.Response(status=404))])

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', CENTRAL_HTTP_PORT)
        await site.start()
        logger.info(f"Odisea Central V2 running on port {CENTRAL_HTTP_PORT}")

        asyncio.create_task(self._cleanup_loop())
        while True: await asyncio.sleep(3600)

if __name__ == "__main__":
    asyncio.run(OdiseaCentral().run())
