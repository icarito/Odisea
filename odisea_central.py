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

# HTTP auth brute-force protection: after AUTH_MAX_FAILS bad tokens from one IP within
# AUTH_FAIL_WINDOW seconds, that IP is locked out for AUTH_LOCKOUT seconds (HTTP 429).
# Only failed auth counts toward the limit; valid-token requests (e.g. the dashboard
# polling) are never throttled.
AUTH_MAX_FAILS = int(os.environ.get("CENTRAL_AUTH_MAX_FAILS", 8))
AUTH_FAIL_WINDOW = int(os.environ.get("CENTRAL_AUTH_FAIL_WINDOW", 60))
AUTH_LOCKOUT = int(os.environ.get("CENTRAL_AUTH_LOCKOUT", 300))

# Logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("odisea_central")

# Self-contained observability dashboard (no external deps). The page itself is public;
# the live data still requires the Bearer token, which the user types as a password and
# the browser sends on each /status fetch.
DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Odisea — Observabilidad (Central)</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; font:13px/1.4 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
         background:#0c0e12; color:#d7dbe0; }
  header { display:flex; align-items:center; gap:16px; flex-wrap:wrap;
           padding:10px 16px; background:#13161c; border-bottom:1px solid #232833; position:sticky; top:0; }
  header h1 { font-size:15px; margin:0; color:#7fd1ff; font-weight:600; }
  .stat { color:#9aa3af; } .stat b { color:#e8edf2; }
  .dot { display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:5px; vertical-align:middle; }
  .ok { background:#3fb950; } .bad { background:#f85149; } .warn { background:#d29922; }
  main { padding:12px 16px; }
  table { border-collapse:collapse; width:100%; }
  th,td { text-align:left; padding:6px 9px; border-bottom:1px solid #1c2129; white-space:nowrap; }
  th { color:#8b95a3; font-weight:600; position:sticky; top:48px; background:#0c0e12; cursor:default; }
  tr:hover td { background:#141821; }
  .num { text-align:right; font-variant-numeric:tabular-nums; }
  .muted { color:#6b7280; } .scene { color:#7fd1ff; } .stale td { opacity:.45; }
  .pill { background:#1c2230; border:1px solid #2a3140; border-radius:10px; padding:1px 7px; color:#aab3c0; }
  /* Login gate */
  #gate { position:fixed; inset:0; display:flex; align-items:center; justify-content:center;
          background:#0c0e12; z-index:10; }
  #gate .box { background:#13161c; border:1px solid #232833; border-radius:10px; padding:26px 28px; width:340px; }
  #gate h2 { margin:0 0 4px; font-size:16px; color:#7fd1ff; }
  #gate p { margin:0 0 16px; color:#8b95a3; font-size:12px; }
  #gate input { width:100%; padding:9px 11px; background:#0c0e12; border:1px solid #2a3140;
                border-radius:6px; color:#e8edf2; font:inherit; }
  #gate button { margin-top:12px; width:100%; padding:9px; background:#1f6feb; border:0;
                 border-radius:6px; color:#fff; font:inherit; font-weight:600; cursor:pointer; }
  #gate button:hover { background:#388bfd; }
  #err { color:#f85149; font-size:12px; min-height:16px; margin-top:8px; }
  .empty { color:#6b7280; padding:40px; text-align:center; }
  .raw { white-space:pre; color:#8b95a3; font-size:11px; background:#0a0c10; padding:8px; }
</style>
</head>
<body>
<div id="gate">
  <div class="box">
    <h2>Odisea · Central</h2>
    <p>Observabilidad de telemetría en tiempo real. Ingresá el token de acceso.</p>
    <form id="loginForm">
      <input id="token" type="password" placeholder="ODISEA_BRIDGE_TOKEN" autocomplete="current-password" autofocus>
      <button type="submit">Conectar</button>
      <div id="err"></div>
    </form>
  </div>
</div>

<header style="display:none" id="bar">
  <h1>Odisea · Central</h1>
  <span class="stat"><span id="connDot" class="dot warn"></span><span id="connTxt">conectando…</span></span>
  <span class="stat">players <b id="nPlayers">0</b></span>
  <span class="stat">peers <b id="nPeers">?</b></span>
  <span class="stat">refresco <b id="rate">1s</b></span>
  <span class="stat muted" id="lastUpd"></span>
  <span style="flex:1"></span>
  <button id="logout" class="pill" style="cursor:pointer">salir</button>
</header>

<main style="display:none" id="view">
  <table>
    <thead><tr>
      <th>player</th><th>host</th><th>plat</th><th>scene / zone</th><th>mode</th>
      <th class="num">pos (x,y,z)</th><th class="num">vel</th><th class="num">yaw/pitch</th>
      <th class="num">fps</th><th class="num">mem</th><th class="num">tick</th><th class="num">edad</th>
    </tr></thead>
    <tbody id="rows"></tbody>
  </table>
  <div id="empty" class="empty">Sin players reportando todavía.</div>
</main>

<script>
let TOKEN = sessionStorage.getItem("odisea_token") || "";
let timer = null;
const REFRESH_MS = 1000;

const $ = id => document.getElementById(id);
const fmt3 = a => Array.isArray(a) ? a.map(v => (+v).toFixed(2)).join(", ") : "—";
const f2 = a => Array.isArray(a) ? a.map(v => (+v).toFixed(2)).join(",") : "—";

function showApp(on) {
  $("gate").style.display = on ? "none" : "flex";
  $("bar").style.display = on ? "flex" : "none";
  $("view").style.display = on ? "block" : "none";
}

async function poll() {
  try {
    const r = await fetch("status", { headers: { "Authorization": "Bearer " + TOKEN } });
    if (r.status === 401) { fail("Token inválido."); return; }
    if (!r.ok) { setConn(false, "HTTP " + r.status); return; }
    const data = await r.json();
    render(data);
    setConn(true, "conectado");
    fetch("health").then(x => x.json()).then(h => $("nPeers").textContent = h.peers_connected ?? "?").catch(()=>{});
  } catch (e) {
    setConn(false, "sin conexión");
  }
}

function setConn(ok, txt) {
  $("connDot").className = "dot " + (ok ? "ok" : "bad");
  $("connTxt").textContent = txt;
  $("lastUpd").textContent = "actualizado " + new Date().toLocaleTimeString();
}

function render(map) {
  const ids = Object.keys(map);
  $("nPlayers").textContent = ids.length;
  $("empty").style.display = ids.length ? "none" : "block";
  const now = Date.now() / 1000;
  const rows = ids.sort().map(pid => {
    const hb = map[pid] || {}, p = hb.player || {};
    const age = hb.timestamp ? (now - hb.timestamp) : null;
    const stale = age != null && age > 10;
    const ageTxt = age == null ? "—" : (age < 60 ? age.toFixed(0)+"s" : (age/60).toFixed(1)+"m");
    return `<tr class="${stale ? 'stale' : ''}" title="${esc(pid)}">
      <td>${esc(pid.slice(0,16))}</td>
      <td>${esc(hb.host||'—')}</td>
      <td>${esc(hb.platform||'—')}</td>
      <td><span class="scene">${esc(p.scene||'—')}</span> <span class="muted">${esc(p.zone||'')}</span></td>
      <td>${esc(p.mode||'—')}</td>
      <td class="num">${fmt3(p.position)}</td>
      <td class="num">${f2(p.velocity)}</td>
      <td class="num">${p.yaw!=null?(+p.yaw).toFixed(2):'—'}/${p.pitch!=null?(+p.pitch).toFixed(2):'—'}</td>
      <td class="num">${p.fps!=null?Math.round(p.fps):'—'}</td>
      <td class="num">${p.memory_mb!=null?(+p.memory_mb).toFixed(0):'—'}</td>
      <td class="num">${p.tick??'—'}</td>
      <td class="num ${stale?'':'muted'}">${ageTxt}</td>
    </tr>`;
  }).join("");
  $("rows").innerHTML = rows;
}

function esc(s){ return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c])); }

function start() {
  showApp(true);
  poll();
  timer = setInterval(poll, REFRESH_MS);
}
function fail(msg) {
  clearInterval(timer); timer = null;
  TOKEN = ""; sessionStorage.removeItem("odisea_token");
  showApp(false); $("err").textContent = msg; $("token").focus();
}

$("loginForm").addEventListener("submit", e => {
  e.preventDefault();
  TOKEN = $("token").value.trim();
  if (!TOKEN) { $("err").textContent = "Ingresá el token."; return; }
  sessionStorage.setItem("odisea_token", TOKEN);
  $("err").textContent = "";
  start();
});
$("logout").addEventListener("click", () => fail(""));

if (TOKEN) start();
</script>
</body>
</html>
"""

class OdiseaCentral:
    def __init__(self):
        self.heartbeats: Dict[str, dict] = {} # player_id -> heartbeat
        self.last_update: Dict[str, float] = {} # player_id -> timestamp
        self.session_rate_limit: Dict[str, float] = {} # session_id -> last_heartbeat_time
        self.active_peers = set() # set of active WebSocket objects
        self.auth_fails: Dict[str, dict] = {} # ip -> {"ts": [failure timestamps], "locked_until": float}

        if STORE_GHOSTS and not os.path.exists(GHOSTS_DIR):
            os.makedirs(GHOSTS_DIR, exist_ok=True)
            logger.info(f"Created ghosts directory: {GHOSTS_DIR}")

    def _is_authorized(self, request):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return False
        token = auth_header[7:]
        return token == BRIDGE_TOKEN

    def _client_ip(self, request) -> str:
        # Behind a proxy/LB, prefer the first hop in X-Forwarded-For.
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
        """Return None if the request may proceed, else a web.Response (429/401)."""
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
        # Successful auth clears any accumulated failures for this IP.
        self.auth_fails.pop(ip, None)
        return None

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

            # Clean expired auth brute-force entries (not locked and no recent failures)
            to_delete_auth = []
            for ip, entry in self.auth_fails.items():
                if entry.get("locked_until", 0) > now:
                    continue
                if any(now - t < AUTH_FAIL_WINDOW for t in entry.get("ts", [])):
                    continue
                to_delete_auth.append(ip)
            for ip in to_delete_auth:
                self.auth_fails.pop(ip, None)

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
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        player_id = request.query.get("player_id")
        if player_id:
            hb = self.heartbeats.get(player_id)
            if hb:
                return web.json_response(hb)
            else:
                return web.json_response({"error": "player not found"}, status=404)
        return web.json_response(self.heartbeats)

    async def handle_sessions(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_health(self, request):
        # Public endpoint
        return web.json_response({
            "ok": True,
            "mode": "central",
            "peers_connected": len(self.active_peers)
        })

    async def handle_index(self, request):
        # Public observability dashboard; data fetches still require the Bearer token.
        return web.Response(text=DASHBOARD_HTML, content_type="text/html")

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/', self.handle_index),
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
