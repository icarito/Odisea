"""Odisea Bridge — Peer node (FD-162).

A local LAN node that:
  - receives telemetry heartbeats from running Godot games over WebSocket (/ws),
  - serves that telemetry to agents over plain HTTP (/status, /sessions, /peers),
  - relays runtime commands to the live game and returns the response synchronously
    (POST /command  →  Godot ANNAV2  →  command_response  →  HTTP JSON),
  - syncs everything up to the central node with auto-reconnect.

Designed to be the natural read/drive surface for agents debugging the runtime:

    curl -s localhost:4999/status | jq                      # who's alive
    curl -sN localhost:4999/events                          # watch heartbeats (SSE) live
    curl -s "localhost:4999/eval?expr=get_tree().get_node_count()"   # one-line runtime query
    curl -s -XPOST localhost:4999/command -d \
      '{"action":"inspect_node","args":{"path":"/root"}}'   # poke the runtime
    curl -s -XPOST localhost:4999/command -d \
      '{"action":"screenshot"}'                             # -> writes a PNG, returns its path
    curl -s -XPOST localhost:4999/command/batch -d \
      '{"commands":[...]}'                                  # ordered repro in one call

See docs/features/FD-162-odisea-bridge.md and the `odisea-telemetry` skill.
"""
import asyncio
import base64
import json
import logging
import os
import socket
import time
import uuid
import zlib
from typing import Dict, Any, Optional, List

from aiohttp import web, ClientSession, ClientWebSocketResponse, WSMsgType

# Cap for inflating compressed WS frames (zlib bomb guard)
WS_MAX_INFLATED = 1024 * 1024


def inflate_ws_frame(data: bytes) -> Optional[bytes]:
    """Inflate a zlib-compressed WS frame (Godot's COMPRESSION_DEFLATE).

    Returns the raw bytes if `data` is not zlib — older clients send plain
    UTF-8 JSON in binary frames. Returns None for oversized payloads.
    """
    try:
        d = zlib.decompressobj()
        out = d.decompress(data, WS_MAX_INFLATED)
        if d.unconsumed_tail:
            return None
        return out
    except zlib.error:
        return data

# --- Configuration (env-overridable) ---
PEER_PORT = int(os.environ.get("PEER_PORT", 4999))
ANNA_HOST = os.environ.get("ANNA_HOST", "127.0.0.1")
ANNA_PORT = int(os.environ.get("ANNA_PORT", 5000))
CENTRAL_WS_URL = os.environ.get("CENTRAL_WS_URL", "wss://odisea.educa.juegos/ws")
CENTRAL_ENABLED = os.environ.get("PEER_NO_CENTRAL", "").lower() not in ("1", "true", "yes", "on")

# Dev-only default; PRODUCTION must set ODISEA_BRIDGE_TOKEN to a real secret. See FD-162.
DEV_DEFAULT_TOKEN = "odisea-dev-insecure"
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", DEV_DEFAULT_TOKEN)

# How long a heartbeat stays "live" in /status before it's pruned (seconds).
HEARTBEAT_TTL = float(os.environ.get("PEER_HEARTBEAT_TTL", 30))
# How long to wait for a Godot command_response over WS (seconds).
COMMAND_TIMEOUT = float(os.environ.get("PEER_COMMAND_TIMEOUT", 8.0))
# Where screenshots returned by Godot get decoded to PNG so agents can open them.
SCREENSHOT_DIR = os.environ.get("PEER_SCREENSHOT_DIR", "/tmp/odisea_peer")
# Legacy: also accept commands over the deprecated V1 TCP ANNA when no game is on WS.
TCP_FALLBACK = os.environ.get("PEER_TCP_FALLBACK", "").lower() in ("1", "true", "yes", "on")
# Best-effort mDNS advertisement of _odisea._tcp (Godot can also find us by port scan).
MDNS_ENABLED = os.environ.get("PEER_NO_MDNS", "").lower() not in ("1", "true", "yes", "on")

# Central reconnect backoff bounds (seconds).
RECONNECT_MIN = 1.0
RECONNECT_MAX = 30.0

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_peer")


def _primary_ip() -> str:
    """Best-effort primary LAN IPv4 (no traffic actually sent)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


class OdiseaPeer:
    def __init__(self):
        self.peer_id = f"peer-{uuid.uuid4().hex[:8]}"
        self.hostname = os.uname().nodename
        self.ip_address = _primary_ip()

        self.heartbeats: Dict[str, dict] = {}          # player_id -> last heartbeat
        self.last_seen: Dict[str, float] = {}          # player_id -> monotonic-ish wall time

        self.http_session: Optional[ClientSession] = None
        self.central_ws: Optional[ClientWebSocketResponse] = None

        self.godot_clients: List[web.WebSocketResponse] = []   # connected games (insertion order)
        self.player_ws: Dict[str, web.WebSocketResponse] = {}  # player_id -> its game ws

        self.pending_commands: Dict[str, asyncio.Future] = {}  # local HTTP command id -> Future
        self.command_history: List[float] = []                 # for rate limiting
        self.event_subscribers: set = set()                    # asyncio.Queue per SSE /events client

        self.zeroconf = None
        self.service_info = None
        self._shutting_down = False

        logger.info(
            "Initialized Peer: peer_id=%s hostname=%s ip=%s",
            self.peer_id, self.hostname, self.ip_address,
        )

    # ------------------------------------------------------------------ helpers
    @property
    def godot_ws(self) -> Optional[web.WebSocketResponse]:
        """Most-recent live game (back-compat / single-game convenience)."""
        for ws in reversed(self.godot_clients):
            if not ws.closed:
                return ws
        return None

    def _live_heartbeats(self) -> Dict[str, dict]:
        """Heartbeats seen within HEARTBEAT_TTL; prunes stale entries as a side effect."""
        now = time.time()
        stale = [pid for pid, t in self.last_seen.items() if now - t > HEARTBEAT_TTL]
        for pid in stale:
            self.heartbeats.pop(pid, None)
            self.last_seen.pop(pid, None)
        return self.heartbeats

    def _pick_game(self, player_id: Optional[str]) -> Optional[web.WebSocketResponse]:
        """Resolve which connected game a command targets."""
        if player_id:
            ws = self.player_ws.get(player_id)
            return ws if ws is not None and not ws.closed else None
        return self.godot_ws  # default: the single / most-recent game

    # -------------------------------------------------------------- central link
    async def central_loop(self):
        """Maintain the uplink to central forever, with exponential backoff."""
        if not CENTRAL_ENABLED:
            logger.info("Central uplink disabled (PEER_NO_CENTRAL).")
            return

        backoff = RECONNECT_MIN
        while not self._shutting_down:
            try:
                await self._central_session()
                backoff = RECONNECT_MIN  # clean exit (server closed) -> retry promptly
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.warning("Central connection failed (%s); retry in %.1fs", e, backoff)
            if self._shutting_down:
                break
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, RECONNECT_MAX)

    async def _central_session(self):
        """One connection lifetime to central: handshake, then pump messages."""
        assert self.http_session is not None
        # compress=15 requests permessage-deflate; heartbeats are repetitive
        # JSON so this cuts the upstream traffic ~70-80%.
        async with self.http_session.ws_connect(CENTRAL_WS_URL, heartbeat=20, compress=15) as ws:
            self.central_ws = ws
            await ws.send_json({"type": "handshake", "peer_id": self.peer_id, "token": BRIDGE_TOKEN})
            logger.info("Connected to central %s", CENTRAL_WS_URL)
            try:
                async for msg in ws:
                    if msg.type == WSMsgType.TEXT:
                        await self._on_central_message(msg.data, ws)
                    elif msg.type in (WSMsgType.CLOSED, WSMsgType.ERROR):
                        break
            finally:
                if self.central_ws is ws:
                    self.central_ws = None
        logger.info("Central connection closed.")

    async def _on_central_message(self, raw: str, ws):
        try:
            data = json.loads(raw)
        except Exception as e:
            logger.error("Bad JSON from central: %s", e)
            return
        mtype = data.get("type")
        if mtype == "handshake_ack":
            logger.info("Central handshake ok (mode=%s).", data.get("mode"))
        elif mtype == "command":
            target = self._pick_game(data.get("player_id"))
            if target is not None:
                logger.info("Relaying central command: %s (%s)", data.get("action"), data.get("id"))
                await target.send_json(data)
            else:
                await ws.send_json({
                    "type": "command_response", "id": data.get("id"), "ok": False,
                    "error": "no game connected to peer",
                })
        elif mtype == "error":
            logger.error("Central error: %s", data.get("error"))

    # ------------------------------------------------------------ game (Godot) WS
    async def handle_godot_client(self, request):
        # compress=True accepts permessage-deflate when the client offers it
        # (browser WebSocket does; Godot 3 desktop WS client doesn't — both fine).
        ws = web.WebSocketResponse(heartbeat=20, compress=True)
        await ws.prepare(request)
        self.godot_clients.append(ws)
        logger.info("Game connected via WS (%d total).", len(self.godot_clients))

        try:
            async for msg in ws:
                if msg.type in (WSMsgType.TEXT, WSMsgType.BINARY):
                    await self._on_game_message(msg.data, ws)
                elif msg.type == WSMsgType.ERROR:
                    logger.error("Game WS error: %s", ws.exception())
        finally:
            self.godot_clients = [c for c in self.godot_clients if c is not ws]
            for pid in [p for p, w in self.player_ws.items() if w is ws]:
                self.player_ws.pop(pid, None)
            logger.info("Game disconnected (%d remain).", len(self.godot_clients))
        return ws

    async def _on_game_message(self, raw, ws):
        try:
            if isinstance(raw, (bytes, bytearray)):
                raw = inflate_ws_frame(bytes(raw))
                if raw is None:
                    logger.warning("Dropping oversized binary frame from game")
                    return
                raw = raw.decode("utf-8")
            data = json.loads(raw)
        except Exception as e:
            logger.error("Bad frame from game: %s", e)
            return

        mtype = data.get("type")
        if mtype == "handshake":
            # Ack so the game knows it can switch to compressed binary frames.
            try:
                await ws.send_json({"type": "handshake_ack", "status": "ok",
                                    "mode": "peer", "compression": "deflate"})
            except Exception:
                pass
        elif mtype == "heartbeat":
            player_id = data.get("player_id")
            if not player_id:
                return
            data["peer_id"] = self.peer_id
            self.heartbeats[player_id] = data
            self.last_seen[player_id] = time.time()
            self.player_ws[player_id] = ws  # learn which game owns this player
            self._fanout_event(data)        # push to live SSE /events subscribers
            if self.central_ws is not None and not self.central_ws.closed:
                try:
                    await self.central_ws.send_json(data)
                except Exception:
                    pass  # central drop is handled by central_loop; never block telemetry
        elif mtype == "command_response":
            cmd_id = data.get("id")
            fut = self.pending_commands.get(cmd_id)
            if fut is not None:
                # Local HTTP caller is waiting — resolve it (don't double-send to central).
                if not fut.done():
                    fut.set_result(data)
            elif self.central_ws is not None and not self.central_ws.closed:
                # Originated at central — relay the response back up.
                try:
                    await self.central_ws.send_json(data)
                except Exception:
                    pass

    # ----------------------------------------------------------------- commands
    async def _send_command_ws(self, action: str, args: dict, player_id: Optional[str]):
        """Send a command to the live game over WS and await its response."""
        target = self._pick_game(player_id)
        if target is None:
            return None  # caller decides on fallback / error

        cmd_id = uuid.uuid4().hex[:8]
        fut = asyncio.get_running_loop().create_future()
        self.pending_commands[cmd_id] = fut
        try:
            await target.send_json({"type": "command", "action": action, "args": args, "id": cmd_id})
            return await asyncio.wait_for(fut, timeout=COMMAND_TIMEOUT)
        finally:
            self.pending_commands.pop(cmd_id, None)

    async def _send_command_tcp(self, action: str, args: dict):
        """Legacy V1 path: forward to ANNA MCP over raw TCP (deprecated)."""
        command = {"action": action, "args": args, "id": uuid.uuid4().hex[:8]}
        reader, writer = await asyncio.wait_for(
            asyncio.open_connection(ANNA_HOST, ANNA_PORT), timeout=2.0)
        try:
            writer.write((json.dumps(command) + "\n").encode())
            await writer.drain()
            resp = await asyncio.wait_for(reader.readuntil(b"\n"), timeout=5.0)
            return json.loads(resp.decode())
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    def _maybe_save_screenshot(self, action: str, response: dict) -> dict:
        """Decode a base64 screenshot result to a PNG file so agents can open it."""
        if action != "screenshot" or not isinstance(response, dict):
            return response
        b64 = response.get("result")
        if not isinstance(b64, str) or not b64:
            return response
        try:
            os.makedirs(SCREENSHOT_DIR, exist_ok=True)
            path = os.path.join(SCREENSHOT_DIR, f"shot-{int(time.time()*1000)}.png")
            with open(path, "wb") as f:
                f.write(base64.b64decode(b64))
            out = {k: v for k, v in response.items() if k != "result"}
            out["screenshot_path"] = path
            return out
        except Exception as e:
            logger.error("Failed to save screenshot: %s", e)
            return response

    def _check_rate(self, cost: int = 1) -> bool:
        """Token-bucket-ish: returns True if this request should be rate-limited (max 10/s)."""
        now = time.time()
        self.command_history = [t for t in self.command_history if now - t < 1.0]
        if len(self.command_history) + cost > 10:
            return True
        self.command_history.extend([now] * cost)
        return False

    async def _run_command(self, action: str, args: dict, player_id: Optional[str]):
        """Execute one command; returns (response_dict, http_status)."""
        if not action:
            return {"error": "missing_action"}, 400

        # Primary path: the live game over WebSocket (V2).
        if self._pick_game(player_id) is not None:
            try:
                resp = await self._send_command_ws(action, args, player_id)
                return self._maybe_save_screenshot(action, resp), 200
            except asyncio.TimeoutError:
                return {"error": "timeout", "message": "game took too long to respond"}, 504
            except Exception as e:
                logger.error("WS command failed: %s", e)
                return {"error": "command_failed", "message": str(e)}, 502

        if player_id:
            return {"error": "player_not_found", "player_id": player_id}, 404

        # Fallback: legacy TCP ANNA MCP (only if explicitly enabled).
        if TCP_FALLBACK:
            try:
                resp = await self._send_command_tcp(action, args)
                return self._maybe_save_screenshot(action, resp), 200
            except asyncio.TimeoutError:
                return {"error": "timeout", "message": "ANNA MCP (TCP) took too long"}, 504
            except Exception as e:
                logger.error("TCP command failed: %s", e)

        return {
            "error": "no_game_connected",
            "message": "No Godot game is connected to this peer.",
            "hint": "Run the game (F5) with ANNAV2; it auto-discovers the peer on :4999.",
        }, 503

    async def handle_command(self, request):
        if self._check_rate():
            return web.json_response(
                {"error": "rate_limited", "message": "Too many commands (max 10/s)"}, status=429)

        if request.method == "GET":
            action = request.query.get("action")
            args = {k: v for k, v in request.query.items() if k not in ("action", "player_id")}
            player_id = request.query.get("player_id")
        else:
            try:
                body = await request.json()
            except Exception:
                return web.json_response({"error": "invalid_json"}, status=400)
            action = body.get("action")
            args = body.get("args", {})
            player_id = body.get("player_id") or (args or {}).get("player_id")

        resp, status = await self._run_command(action, args, player_id)
        return web.json_response(resp, status=status)

    async def handle_eval(self, request):
        """Shortcut for execute_script: GET /eval?expr=<gdscript expression>.

        Wraps the expression as `return <expr>` inside ANNAV2's execute_script, so
        agents can query the runtime without hand-escaping a GDScript block:
            GET /eval?expr=get_tree().get_node_count()
            GET /eval?expr=SessionManager.player.global_transform.origin
        """
        if self._check_rate():
            return web.json_response(
                {"error": "rate_limited", "message": "Too many commands (max 10/s)"}, status=429)
        expr = request.query.get("expr")
        if not expr:
            return web.json_response({"error": "missing_expr"}, status=400)
        player_id = request.query.get("player_id")
        resp, status = await self._run_command(
            "execute_script", {"script": "return " + expr}, player_id)
        return web.json_response(resp, status=status)

    async def handle_command_batch(self, request):
        """Run an ordered list of commands in one call; great for capturing a repro.

        POST /command/batch
          {"player_id": "<default, optional>", "stop_on_error": true,
           "commands": [{"action": "...", "args": {...}, "player_id": "<override>"}, ...]}
        Returns {"results": [{action, ok, status, response}, ...]}.
        """
        try:
            body = await request.json()
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)

        commands = body.get("commands")
        if not isinstance(commands, list) or not commands:
            return web.json_response({"error": "missing_commands"}, status=400)
        if len(commands) > 20:
            return web.json_response({"error": "too_many_commands", "max": 20}, status=400)
        if self._check_rate(cost=len(commands)):
            return web.json_response(
                {"error": "rate_limited", "message": "Too many commands (max 10/s)"}, status=429)

        default_pid = body.get("player_id")
        stop_on_error = bool(body.get("stop_on_error", False))
        results = []
        for cmd in commands:
            action = cmd.get("action")
            args = cmd.get("args", {})
            player_id = cmd.get("player_id") or default_pid
            resp, status = await self._run_command(action, args, player_id)
            ok = status == 200 and isinstance(resp, dict) and resp.get("ok") is not False
            results.append({"action": action, "ok": ok, "status": status, "response": resp})
            if stop_on_error and not ok:
                break
        return web.json_response({"results": results})

    # ------------------------------------------------------------- HTTP handlers
    async def handle_health(self, request):
        return web.json_response({
            "ok": True, "mode": "peer", "peer_id": self.peer_id, "hostname": self.hostname,
            "games_connected": len([w for w in self.godot_clients if not w.closed]),
            "players_known": len(self._live_heartbeats()),
            "central_connected": self.central_ws is not None and not self.central_ws.closed,
        })

    async def handle_status(self, request):
        hbs = self._live_heartbeats()
        player_id = request.query.get("player_id")
        if player_id:
            hb = hbs.get(player_id)
            return web.json_response(hb) if hb else web.json_response(
                {"error": "not_found", "player_id": player_id}, status=404)
        return web.json_response(hbs)

    async def handle_sessions(self, request):
        sessions = sorted({hb.get("session_id") for hb in self._live_heartbeats().values()
                           if hb.get("session_id")})
        return web.json_response(sessions)

    async def handle_peers(self, request):
        return web.json_response({
            "peer_id": self.peer_id, "hostname": self.hostname, "ip": self.ip_address,
            "players": sorted(self._live_heartbeats().keys()),
        })

    def _fanout_event(self, data: dict):
        """Non-blocking push of a heartbeat to all live SSE /events subscribers."""
        for q in list(self.event_subscribers):
            try:
                q.put_nowait(data)
            except asyncio.QueueFull:
                pass  # slow consumer: drop rather than back up the game's WS loop

    async def handle_events(self, request):
        """Server-Sent Events stream of heartbeats — watch the runtime instead of polling.

            curl -N localhost:4999/events
            curl -N "localhost:4999/events?player_id=<id>"   # filter to one game
        """
        pid_filter = request.query.get("player_id")
        resp = web.StreamResponse(headers={
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        })
        await resp.prepare(request)
        await resp.write(b": connected\n\n")

        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self.event_subscribers.add(q)
        try:
            while True:
                try:
                    data = await asyncio.wait_for(q.get(), timeout=15)
                except asyncio.TimeoutError:
                    await resp.write(b": keepalive\n\n")  # keep proxies/clients from timing out
                    continue
                if pid_filter and data.get("player_id") != pid_filter:
                    continue
                await resp.write(f"data: {json.dumps(data)}\n\n".encode())
        except (asyncio.CancelledError, ConnectionResetError):
            pass
        finally:
            self.event_subscribers.discard(q)
        return resp

    async def handle_index(self, request):
        return web.Response(
            text="<h1>Odisea Peer</h1><p>Peer node running. "
                 "See /status, /sessions, /events, /health.</p>",
            content_type="text/html")

    # --------------------------------------------------------------------- mDNS
    async def _register_mdns(self):
        if not MDNS_ENABLED:
            return
        try:
            from zeroconf import ServiceInfo
            from zeroconf.asyncio import AsyncZeroconf
            self.zeroconf = AsyncZeroconf()
            self.service_info = ServiceInfo(
                "_odisea._tcp.local.",
                f"{self.peer_id}._odisea._tcp.local.",
                addresses=[socket.inet_aton(self.ip_address)],
                port=PEER_PORT,
                properties={"peer_id": self.peer_id, "hostname": self.hostname},
                server=f"{self.peer_id}.local.",
            )
            await self.zeroconf.async_register_service(self.service_info)
            logger.info("mDNS: advertising _odisea._tcp on %s:%d", self.ip_address, PEER_PORT)
        except Exception as e:
            logger.warning("mDNS advertisement unavailable (%s); Godot falls back to port scan.", e)
            self.zeroconf = None

    async def _unregister_mdns(self):
        if self.zeroconf is not None:
            try:
                if self.service_info is not None:
                    await self.zeroconf.async_unregister_service(self.service_info)
                await self.zeroconf.async_close()
            except Exception:
                pass

    # ---------------------------------------------------------------------- run
    async def run(self):
        self.http_session = ClientSession()

        app = web.Application()
        app.add_routes([
            web.get('/', self.handle_index),
            web.get('/health', self.handle_health),
            web.get('/status', self.handle_status),
            web.get('/sessions', self.handle_sessions),
            web.get('/peers', self.handle_peers),
            web.get('/events', self.handle_events),
            web.get('/eval', self.handle_eval),
            web.get('/command', self.handle_command),
            web.post('/command', self.handle_command),
            web.post('/command/batch', self.handle_command_batch),
            web.get('/ws', self.handle_godot_client),
        ])

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', PEER_PORT)
        await site.start()
        # NOTE: this exact phrasing is matched by the VS Code "Run Odisea Bridge Peer" task.
        logger.info("HTTP/WS server started on port %d", PEER_PORT)

        await self._register_mdns()
        central_task = asyncio.create_task(self.central_loop())

        try:
            while not self._shutting_down:
                await asyncio.sleep(3600)
        finally:
            self._shutting_down = True
            central_task.cancel()
            await self._unregister_mdns()
            if self.http_session is not None:
                await self.http_session.close()
            await runner.cleanup()


if __name__ == "__main__":
    if BRIDGE_TOKEN == DEV_DEFAULT_TOKEN:
        logger.warning("Using INSECURE dev default token. Set ODISEA_BRIDGE_TOKEN for production.")

    peer = OdiseaPeer()
    try:
        asyncio.run(peer.run())
    except KeyboardInterrupt:
        peer._shutting_down = True
