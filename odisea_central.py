import asyncio
import datetime
import hashlib
import hmac
import json
import logging
import os
import sqlite3
import subprocess
import time
import uuid
import zlib
from typing import Dict, Any, List, Set, Optional

from aiohttp import web, WSCloseCode

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

# --- Configuration ---
CENTRAL_HTTP_PORT = int(os.environ.get("CENTRAL_HTTP_PORT", 5003))
DEV_DEFAULT_TOKEN = "odisea-dev-insecure"
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", DEV_DEFAULT_TOKEN)

CACHE_TTL = int(os.environ.get("CENTRAL_CACHE_TTL", 120))
STORE_GHOSTS = os.environ.get("CENTRAL_STORE_GHOSTS", "true").lower() == "true"
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
SQLITE_DB = os.environ.get("CENTRAL_SQLITE_DB", os.environ.get("CENTRAL_DB_PATH", "./data/ghosts.db"))
GHOSTS_MAX_BYTES = int(os.environ.get("CENTRAL_GHOSTS_MAX_BYTES", 1073741824))  # 1GB
STATIC_DIR = os.environ.get("CENTRAL_STATIC_DIR", "./dashboard/dist")

# Global, server-side telemetry filtering. The headless server peer is never a
# real client, and the first seconds of every session (scene load, GC, chunk
# streaming) skew FPS/memory — both are excluded here so every dashboard
# consumer sees clean runtime data without re-filtering. Mirrors the frontend
# WARMUP_SECONDS in dashboard/src/lib/filters.ts.
WARMUP_SECONDS = int(os.environ.get("CENTRAL_WARMUP_SECONDS", 10))

# SQL fragment: exclude the headless server peer (case-insensitive).
_NOT_SERVER = "LOWER(COALESCE(platform,'')) != 'server'"

# SQL fragment: exclude warmup heartbeats — keep only rows at least
# WARMUP_SECONDS after their session's first sample. Correlated subquery keyed
# on (player_id, session_id); fine for the bounded LIMIT reads below.
_PAST_WARMUP = (
    "timestamp >= ("
    " SELECT MIN(h2.timestamp) FROM heartbeats h2"
    " WHERE h2.session_id = heartbeats.session_id"
    " AND h2.player_id = heartbeats.player_id"
    f") + {WARMUP_SECONDS}"
)

# Scenes always offered in dashboard dropdowns, even before any telemetry exists.
DEFAULT_SCENES = [s for s in os.environ.get("CENTRAL_DEFAULT_SCENES", "Dome_Crio,OdiseaExterior,ScaffoldOrbit").split(",") if s]

# Deploy webhook (GitHub push -> auto pull + redeploy).
# Secret defaults to BRIDGE_TOKEN so there's nothing extra to configure, but can
# be overridden. Set DEPLOY_WEBHOOK_SECRET to "" to disable the endpoint.
DEPLOY_WEBHOOK_SECRET = os.environ.get("DEPLOY_WEBHOOK_SECRET", BRIDGE_TOKEN)
# Path to the deploy script that does the pull + redeploy. Run detached so it
# survives the restart of this very process.
DEPLOY_SCRIPT = os.environ.get("DEPLOY_SCRIPT", os.path.expanduser("~/odisea-deploy/deploy.sh"))
# Branch whose pushes trigger a deploy.
DEPLOY_BRANCH = os.environ.get("DEPLOY_BRANCH", "main")
# Only redeploy when a push touches central's own dependencies (the server
# script, the dashboard, or the deploy tooling). A push that only changes game
# content shouldn't restart the bridge. Comma-separated path prefixes; set to ""
# to deploy on every push regardless of paths.
DEPLOY_PATHS = [
    p.strip() for p in os.environ.get(
        "DEPLOY_PATHS",
        "odisea_central.py,dashboard/,scripts/deploy-webhook/,scripts/import_ghosts_to_sqlite.py",
    ).split(",") if p.strip()
]

AUTH_MAX_FAILS = int(os.environ.get("CENTRAL_AUTH_MAX_FAILS", 8))
AUTH_FAIL_WINDOW = int(os.environ.get("CENTRAL_AUTH_FAIL_WINDOW", 60))
AUTH_LOCKOUT = int(os.environ.get("CENTRAL_AUTH_LOCKOUT", 300))

WEB_TELEMETRY_FILE = os.environ.get("CENTRAL_WEB_TELEMETRY_FILE", "./data/web_telemetry.jsonl")
WEB_TELEMETRY_MAX_BYTES = int(os.environ.get("CENTRAL_WEB_TELEMETRY_MAX_BYTES", 4096))
WEB_TELEMETRY_RATE_MAX = int(os.environ.get("CENTRAL_WEB_TELEMETRY_RATE_MAX", 20))
WEB_TELEMETRY_RATE_WINDOW = int(os.environ.get("CENTRAL_WEB_TELEMETRY_RATE_WINDOW", 60))

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
                    try:
                        ghosts_bytes += os.path.getsize(os.path.join(root, f))
                    except Exception:
                        pass

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
        self.heartbeats: Dict[str, dict] = {}  # player_id -> heartbeat
        self.last_update: Dict[str, float] = {}  # player_id -> timestamp
        self.session_rate_limit: Dict[str, float] = {}  # session_id -> last_heartbeat_time
        self.active_peers: Dict[web.WebSocketResponse, str] = {}  # ws -> peer_id
        self.peer_ws: Dict[str, web.WebSocketResponse] = {}  # peer_id -> ws
        self.event_subscribers: Set[web.WebSocketResponse] = set()
        self.auth_fails: Dict[str, dict] = {}  # ip -> {"ts": [failure timestamps], "locked_until": float}
        self.metrics = MetricsCollector()
        self.db_queue: asyncio.Queue = asyncio.Queue()
        self.ghost_rotation_counter: Dict[str, int] = {}  # pid -> count
        self.low_fps_timers: Dict[str, float] = {}  # player_id -> timestamp when FPS first dropped < 15
        self.last_alert_time: Dict[str, float] = {}  # player_id -> last alert timestamp
        self.pending_commands: Dict[str, asyncio.Future] = {}  # command_id -> Future
        self.web_telemetry_rate: Dict[str, List[float]] = {}  # ip -> [request timestamps]
        self.low_fps_sessions: Dict[str, float] = {}  # session_id -> start_time_of_low_fps

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

                to_delete_rate = [ip for ip, ts in self.web_telemetry_rate.items()
                                  if not any(now - t < WEB_TELEMETRY_RATE_WINDOW for t in ts)]
                for ip in to_delete_rate:
                    self.web_telemetry_rate.pop(ip, None)
            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}")
            await asyncio.sleep(60)

    # --- Request Handlers ---
    async def handle_health(self, request):
        return web.json_response(self.metrics.get_metrics(self))

    async def handle_web_telemetry(self, request):
        """Unauthenticated loader metrics from the HTML shell (fire and forget).

        Browsers post with mode no-cors (text/plain body), so there is no
        bearer token here; mitigate abuse with a body-size cap and a per-IP
        rate limit instead.
        """
        ip = request.remote or "unknown"
        now = time.time()
        bucket = self.web_telemetry_rate.setdefault(ip, [])
        bucket[:] = [t for t in bucket if now - t < WEB_TELEMETRY_RATE_WINDOW]
        if len(bucket) >= WEB_TELEMETRY_RATE_MAX:
            return web.json_response({"error": "rate_limited"}, status=429,
                                     headers={"Access-Control-Allow-Origin": "*"})
        bucket.append(now)

        try:
            raw = await request.content.read(WEB_TELEMETRY_MAX_BYTES + 1)
            if len(raw) > WEB_TELEMETRY_MAX_BYTES:
                raise ValueError("body too large")
            data = json.loads(raw.decode("utf-8"))
            event = str(data.get("event", ""))
            if event not in ("loader_start", "engine_start", "player_released"):
                raise ValueError("unknown event")
            record = {
                "event": event,
                "ts": data.get("ts"),
                "session_id": str(data.get("session_id", ""))[:64],
                "received_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "ip": ip,
            }
            if event == "loader_start":
                record["ua"] = str(data.get("ua", ""))[:256]
            elif event == "engine_start":
                record["load_ms"] = data.get("load_ms")
            else:
                record["total_ms"] = data.get("total_ms")
        except Exception as e:
            logger.warning(f"Rejected web telemetry from {ip}: {e}")
            return web.json_response({"error": "bad_request"}, status=400,
                                     headers={"Access-Control-Allow-Origin": "*"})

        try:
            os.makedirs(os.path.dirname(WEB_TELEMETRY_FILE) or ".", exist_ok=True)
            with open(WEB_TELEMETRY_FILE, "a", encoding="utf-8") as f:
                f.write(json.dumps(record, ensure_ascii=False) + "\n")
        except Exception as e:
            logger.error(f"Failed to persist web telemetry: {e}")

        extra = ""
        if event == "engine_start":
            extra = f" load_ms={record.get('load_ms')}"
        elif event == "player_released":
            extra = f" total_ms={record.get('total_ms')}"
        logger.info(f"Web telemetry: {event} session={record['session_id']}{extra}")
        return web.json_response({"ok": True}, headers={"Access-Control-Allow-Origin": "*"})

    async def handle_web_telemetry_list(self, request):
        """Recent web loader metrics for the dashboard (auth required)."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            limit = min(max(int(request.query.get("limit", 200)), 1), 1000)
        except ValueError:
            limit = 200

        records = []
        try:
            if os.path.exists(WEB_TELEMETRY_FILE):
                tail_bytes = 262144
                with open(WEB_TELEMETRY_FILE, "rb") as f:
                    f.seek(0, os.SEEK_END)
                    size = f.tell()
                    f.seek(max(0, size - tail_bytes))
                    lines = f.read().decode("utf-8", "replace").splitlines()
                if size > tail_bytes and lines:
                    lines = lines[1:]  # drop possibly truncated first line
                for line in lines[-limit:]:
                    try:
                        rec = json.loads(line)
                        rec.pop("ip", None)  # not the dashboard's business
                        records.append(rec)
                    except Exception:
                        pass
        except Exception as e:
            logger.error(f"Failed reading web telemetry log: {e}")
        return web.json_response(records)

    async def handle_web_telemetry_options(self, request):
        return web.Response(status=204, headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type",
        })

    async def handle_status(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        player_id = request.query.get("player_id")
        self.metrics.record_cache_lookup(player_id in self.heartbeats if player_id else True)

        if player_id:
            hb = self.heartbeats.get(player_id)
            return web.json_response(hb) if hb else web.json_response({"error": "not_found"}, status=404)
        return web.json_response(self.heartbeats)

    async def handle_sessions(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        sessions = list(set(hb.get("session_id") for hb in self.heartbeats.values() if hb.get("session_id")))
        return web.json_response(sessions)

    async def handle_ghosts(self, request):
        """Historical query from SQLite backend with pagination."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        scene = request.query.get("scene")
        since = request.query.get("since")
        until = request.query.get("until")
        platform = request.query.get("platform")
        player_id = request.query.get("player_id")
        session_id = request.query.get("session_id")

        try:
            limit = min(max(int(request.query.get("limit", 1000)), 1), 5000)
        except ValueError:
            limit = 1000

        try:
            offset = int(request.query.get("offset", 0))
        except ValueError:
            offset = 0

        query = f"SELECT * FROM heartbeats WHERE {_NOT_SERVER}"
        if not session_id:
            query += f" AND {_PAST_WARMUP}"
        params = []
        if scene:
            query += " AND scene = ?"
            params.append(scene)
        if since:
            query += " AND timestamp >= ?"
            params.append(float(since))
        if until:
            query += " AND timestamp <= ?"
            params.append(float(until))
        if platform:
            query += " AND platform = ?"
            params.append(platform)
        if player_id:
            query += " AND player_id = ?"
            params.append(player_id)
        if session_id:
            query += " AND session_id = ?"
            params.append(session_id)

        query += " ORDER BY timestamp ASC LIMIT ? OFFSET ?"
        params.append(limit + 1)
        params.append(offset)

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute(query, params)
                rows = [dict(row) for row in cursor.fetchall()]
                conn.close()
                return rows

            rows = await asyncio.wait_for(self._run_query(fetch), timeout=10.0)

            has_more = len(rows) > limit
            if has_more:
                rows = rows[:limit]

            next_offset = offset + len(rows) if has_more else None

            return web.json_response({
                "data": rows,
                "next_offset": next_offset,
                "meta": {
                    "has_more": has_more,
                    "count": len(rows),
                    "limit": limit,
                    "offset": offset
                }
            })
        except asyncio.TimeoutError:
            return web.json_response({
                "data": [],
                "meta": {"has_more": True, "error": "timeout"}
            })
        except Exception as e:
            logger.warning(f"{request.path}: query failed ({e})")
            return web.json_response({"data": [], "meta": {"has_more": False, "error": str(e)}})

    async def handle_ghosts_heatmap(self, request):
        """Aggregated heatmap query from SQLite."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        scene = request.query.get("scene")
        if not scene:
            return web.json_response({"error": "missing_scene"}, status=400)

        res = float(request.query.get("resolution", 5))
        low_fps_threshold = 30.0

        # Aggregate data by grid cell
        query = """
        SELECT
            CAST(pos_x / ? AS INTEGER) * ? as grid_x,
            CAST(pos_z / ? AS INTEGER) * ? as grid_z,
            COUNT(*) as count,
            SUM(CASE WHEN fps < ? THEN 1 ELSE 0 END) as low_fps_count,
            AVG(fps) as avg_fps,
            MIN(fps) as min_fps,
            AVG(memory_mb) as avg_mem
        FROM heartbeats
        WHERE scene = ? AND {not_server} AND {past_warmup}
        GROUP BY grid_x, grid_z
        """.format(not_server=_NOT_SERVER, past_warmup=_PAST_WARMUP)
        params = (res, res, res, res, low_fps_threshold, scene)

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute(query, params)
                rows = [dict(row) for row in cursor.fetchall()]
                conn.close()
                return rows

            rows = await self._run_query(fetch)
            return web.json_response(rows)
        except Exception as e:
            logger.warning(f"{request.path}: query failed, returning [] ({e})")
            return web.json_response([])

    async def handle_download_session(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        pid = request.match_info.get('player_id')
        sid = request.match_info.get('session_id')
        fpath = os.path.join(GHOSTS_DIR, pid, f"{sid}.jsonl")

        if os.path.exists(fpath):
            return web.FileResponse(fpath, headers={
                "Content-Disposition": f'attachment; filename="{sid}.jsonl"'
            })
        return web.Response(status=404, text="Session not found")

    async def handle_ghosts_sessions(self, request):
        """Historical session list from SQLite."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        include_server = request.query.get("include_server") in ("1", "true", "yes")

        query = """
        SELECT
            player_id,
            session_id,
            COALESCE(NULLIF(MAX(platform), ''), 'unknown') as platform,
            MIN(timestamp) as start_time,
            MAX(timestamp) as end_time,
            MAX(timestamp) - MIN(timestamp) as duration,
            GROUP_CONCAT(DISTINCT scene) as scenes_visited,
            AVG(fps) as avg_fps,
            SUM(CASE WHEN fps < 30 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as low_fps_pct,
            AVG(memory_mb) as avg_mem
        FROM heartbeats
        WHERE (? = 1 OR {not_server})
        GROUP BY player_id, session_id
        ORDER BY start_time DESC
        LIMIT 200
        """.format(not_server=_NOT_SERVER)

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute(query, (1 if include_server else 0,))
                rows = [dict(row) for row in cursor.fetchall()]
                conn.close()
                return rows

            rows = await self._run_query(fetch)
            return web.json_response(rows)
        except Exception as e:
            logger.warning(f"{request.path}: query failed, returning [] ({e})")
            return web.json_response([])

    async def handle_ghosts_active(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        now = time.time()
        active = []
        for pid, hb in self.heartbeats.items():
            last_seen = self.last_update.get(pid, 0)
            if now - last_seen < 30:
                p_data = hb.get("player", {})
                pos = p_data.get("position", [0, 0, 0])
                active.append({
                    "player_id": pid,
                    "session_id": hb.get("session_id"),
                    "scene": p_data.get("scene"),
                    "pos_x": pos[0],
                    "pos_y": pos[1],
                    "pos_z": pos[2],
                    "fps": p_data.get("fps"),
                    "last_seen": last_seen
                })
        return web.json_response(active)

    async def handle_ghosts_stats(self, request):
        """Aggregate Ghost stats per scene + headline metrics."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()

                # Per-scene stats as requested: total_ghosts, total_sessions, oldest_ts, newest_ts, memory_mb_avg
                query_scenes = f"""
                SELECT
                    scene,
                    COUNT(*) as total_ghosts,
                    COUNT(DISTINCT session_id) as total_sessions,
                    MIN(timestamp) as oldest_ts,
                    MAX(timestamp) as newest_ts,
                    AVG(memory_mb) as memory_mb_avg
                FROM heartbeats
                WHERE {_NOT_SERVER} AND {_PAST_WARMUP}
                GROUP BY scene
                """
                cursor.execute(query_scenes)
                scene_stats = [dict(row) for row in cursor.fetchall()]

                # Headline stats for dashboard compatibility
                now = time.time()
                day, week, month = 86400, 604800, 2592000

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats WHERE {_NOT_SERVER}"
                )
                unique_total = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {_NOT_SERVER} AND timestamp >= ?",
                    (now - day,),
                )
                unique_day = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {_NOT_SERVER} AND timestamp >= ?",
                    (now - week,),
                )
                unique_week = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {_NOT_SERVER} AND timestamp >= ?",
                    (now - month,),
                )
                unique_month = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT MIN(timestamp) AS start, MAX(timestamp) AS end "
                    f"FROM heartbeats WHERE {_NOT_SERVER} "
                    f"GROUP BY player_id, session_id"
                )
                sessions_intervals = cursor.fetchall()

                # Max concurrent
                events = []
                for row in sessions_intervals:
                    s, e = row["start"], row["end"]
                    if s is None or e is None: continue
                    events.append((s, 1))
                    events.append((e, -1))
                events.sort(key=lambda ev: (ev[0], ev[1]))
                cur_c = max_c = 0
                for _, delta in events:
                    cur_c += delta
                    max_c = max(max_c, cur_c)

                conn.close()

                return {
                    "scenes": scene_stats,
                    "headline": {
                        "unique_players_total": unique_total,
                        "players_last_day": unique_day,
                        "players_last_week": unique_week,
                        "players_last_month": unique_month,
                        "max_concurrent_players": max_c,
                        "total_sessions": len(sessions_intervals),
                    }
                }

            stats = await self._run_query(fetch)
            return web.json_response(stats)
        except Exception as e:
            logger.warning(f"{request.path}: stats query failed ({e})")
            return web.json_response({"error": str(e)}, status=500)

    async def handle_scenes(self, request):
        """Distinct scene names seen in telemetry, for dashboard dropdowns."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        scenes = set(DEFAULT_SCENES)
        try:
            def fetch():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute(
                    "SELECT DISTINCT scene FROM heartbeats WHERE scene IS NOT NULL AND scene != ''"
                )
                s = [row[0] for row in cursor.fetchall()]
                conn.close()
                return s

            db_scenes = await self._run_query(fetch)
            for s in db_scenes:
                scenes.add(s)
        except Exception as e:
            logger.warning(f"handle_scenes: DB query failed, using defaults ({e})")
        return web.json_response(sorted(scenes))

    async def handle_command(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            body = await request.json()
            action = body.get("action")
            args = body.get("args", {})
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)

        if not action:
            return web.json_response({"error": "missing_action"}, status=400)

        # Bug fix: require player_id explicitly; do NOT fallback to first peer
        player_id = body.get("player_id") or args.get("player_id")
        if not player_id:
            return web.json_response({"error": "missing_player_id"}, status=400)

        if not self.active_peers:
            return web.json_response({"error": "no_peers_connected"}, status=503)

        cmd_id = str(uuid.uuid4())[:8]
        cmd = {
            "type": "command",
            "action": action,
            "args": args,
            "id": cmd_id
        }

        target_ws = self.peer_ws.get(player_id)
        if not target_ws:
            hb = self.heartbeats.get(player_id)
            if hb:
                target_peer_id = hb.get("peer_id")
                if target_peer_id:
                    target_ws = self.peer_ws.get(target_peer_id)

        if not target_ws:
            return web.json_response({"error": "player_not_found"}, status=404)

        fut = asyncio.get_running_loop().create_future()
        self.pending_commands[cmd_id] = fut

        try:
            await target_ws.send_json(cmd)
            response = await asyncio.wait_for(fut, timeout=5.5)
            return web.json_response(response)
        except asyncio.TimeoutError:
            self.pending_commands.pop(cmd_id, None)
            return web.json_response({"error": "timeout", "message": "Peer/Godot took too long to respond"}, status=504)
        except Exception as e:
            self.pending_commands.pop(cmd_id, None)
            logger.error(f"Command relay failed: {e}")
            return web.json_response({"error": "relay_failed", "message": str(e)}, status=502)

    async def handle_ws(self, request):
        # compress=True accepts permessage-deflate when the peer/browser offers it
        ws = web.WebSocketResponse(compress=True)
        await ws.prepare(request)

        peer_id = None
        authenticated = False

        # Platform inference (Prompt 4)
        platform_query = request.query.get("platform")
        ua = request.headers.get("User-Agent", "")
        inferred_platform = platform_query
        if not inferred_platform:
            # Simple heuristic: Mozilla-based and no major Desktop OS = likely HTML5/Mobile Browser
            if "Mozilla" in ua and not any(os_name in ua for os_name in ["Windows", "Linux", "Macintosh"]):
                inferred_platform = "HTML5"

        logger.info(f"New peer connection attempt. Inferred Platform: {inferred_platform}")

        try:
            async for msg in ws:
                if msg.type in (web.WSMsgType.TEXT, web.WSMsgType.BINARY):
                    payload = msg.data
                    if msg.type == web.WSMsgType.BINARY:
                        payload = inflate_ws_frame(bytes(payload))
                        if payload is None:
                            logger.warning("Dropping oversized binary frame from peer")
                            continue
                    try:
                        data = json.loads(payload)
                    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
                        logger.warning("Received malformed JSON from peer")
                        continue

                    msg_type = data.get("type")

                    if not authenticated:
                        if msg_type == "handshake":
                            token = data.get("token")
                            # Aceptamos conexiones anónimas para telemetría (HTML5 por defecto).
                            # El token válido solo se exige para ejecutar comandos (ya protegido en HTTP).
                            is_admin = (token == BRIDGE_TOKEN)
                            
                            authenticated = True
                            peer_id = data.get("peer_id")
                            if not peer_id or peer_id == "unknown":
                                peer_id = "anon_" + str(uuid.uuid4())[:8]
                            
                            self.active_peers[ws] = peer_id
                            self.peer_ws[peer_id] = ws
                            
                            mode = "admin" if is_admin else "telemetry"
                            logger.info(f"Peer conectado ({mode}): {peer_id}")
                            await ws.send_json({"type": "handshake_ack", "status": "ok", "mode": mode,
                                                "compression": "deflate"})
                        else:
                            logger.warning("Peer sent message before handshake.")
                            await ws.close(code=WSCloseCode.POLICY_VIOLATION)
                            break

                    elif msg_type == "heartbeat":
                        player_id = data.get("player_id")
                        session_id = data.get("session_id")

                        if not player_id or not session_id:
                            continue

                        now = time.time()
                        last_time = self.session_rate_limit.get(session_id, 0)
                        if now - last_time < 0.05:
                            continue

                        self.session_rate_limit[session_id] = now

                        # Enrich with inferred platform if missing or unknown (Prompt 4)
                        if inferred_platform:
                            if "player" not in data:
                                data["player"] = {}
                            if data["player"].get("platform") in [None, "", "unknown"]:
                                data["player"]["platform"] = inferred_platform
                            if data.get("platform") in [None, "", "unknown"]:
                                data["platform"] = inferred_platform

                        # Alerts and Real-time Broadcast
                        p_data = data.get("player", {})
                        fps = p_data.get("fps", 60)
                        platform = (p_data.get("platform") or data.get("platform") or "").lower()
                        if platform == "server":
                            self.low_fps_timers.pop(player_id, None)
                        elif fps < 15:
                            if player_id not in self.low_fps_timers:
                                self.low_fps_timers[player_id] = now
                            elif now - self.low_fps_timers[player_id] > 5:
                                # Throttle alerts: max 1 per 60s
                                if now - self.last_alert_time.get(player_id, 0) > 60:
                                    self.last_alert_time[player_id] = now
                                    alert = {
                                        "type": "alert",
                                        "alertType": "low_fps",
                                        "playerId": player_id,
                                        "player_id": player_id,
                                        "platform": platform,
                                        "message": f"Low FPS detected: {fps} FPS",
                                        "fps": fps,
                                        "timestamp": now
                                    }
                                    for sub in self.event_subscribers:
                                        try:
                                            await sub.send_json(alert)
                                        except Exception:
                                            pass
                        else:
                            self.low_fps_timers.pop(player_id, None)

                        # Fusionar datos para manejar actualizaciones parciales (tiers) del cliente Godot
                        if player_id in self.heartbeats:
                            existing = self.heartbeats[player_id]
                            existing.update(data)
                            if "player" in data and isinstance(data["player"], dict):
                                if "player" not in existing or not isinstance(existing["player"], dict):
                                    existing["player"] = {}
                                
                                # Fusión inteligente: NO sobrescribir con valores vacíos o nulos
                                curr_player = existing["player"]
                                for key, value in data["player"].items():
                                    if value is not None and value != "":
                                        curr_player[key] = value
                                        
                                existing["player"] = curr_player
                            self.heartbeats[player_id] = existing
                        else:
                            self.heartbeats[player_id] = data.copy()

                        self.last_update[player_id] = now
                        self.metrics.record_heartbeat(session_id)

                        if self.metrics.heartbeats_total % 100 == 0:
                            logger.info(f"Heartbeat 100x: {player_id}")

                        if STORE_GHOSTS:
                            self._store_ghost(player_id, session_id, data)

                        # Low FPS alerts (Prompt 9)
                        player_data_fps = data.get("player", {}).get("fps", 60)
                        player_data = data.get("player", {})
                        platform = (player_data.get("platform") or data.get("platform") or "").lower()
                        if platform == "server":
                            self.low_fps_sessions.pop(session_id, None)
                        elif player_data_fps < 15:
                            if session_id not in self.low_fps_sessions:
                                self.low_fps_sessions[session_id] = now
                            elif now - self.low_fps_sessions[session_id] > 5:
                                # Persistent low FPS alert
                                alert = {
                                    "type": "alert",
                                    "alertType": "low_fps",
                                    "playerId": player_id,
                                    "player_id": player_id,
                                    "session_id": session_id,
                                    "platform": platform,
                                    "message": "Low FPS detected (>5s)",
                                    "fps": player_data_fps,
                                    "timestamp": now
                                }
                                for sub in self.event_subscribers:
                                    try:
                                        asyncio.create_task(sub.send_json(alert))
                                    except Exception: pass
                        else:
                            self.low_fps_sessions.pop(session_id, None)

                        for sub in self.event_subscribers:
                            try:
                                await sub.send_json(data)
                            except Exception:
                                pass

                    elif msg_type == "command_response":
                        cmd_id = data.get("id")
                        if cmd_id in self.pending_commands:
                            fut = self.pending_commands.pop(cmd_id)
                            if not fut.done():
                                fut.set_result(data)

                elif msg.type == web.WSMsgType.ERROR:
                    logger.error(f"Peer connection closed with exception {ws.exception()}")

        finally:
            if ws in self.active_peers:
                pid = self.active_peers.pop(ws)
                if self.peer_ws.get(pid) == ws:
                    self.peer_ws.pop(pid, None)
            logger.info(f"Peer disconnected: {peer_id}")

        return ws

    async def _process_heartbeat(self, data):
        pid = data.get("player_id")
        sid = data.get("session_id")
        if pid and sid:
            now = time.time()
            if now - self.session_rate_limit.get(sid, 0) < 0.05:
                return
            self.session_rate_limit[sid] = now

            self.heartbeats[pid] = data
            self.last_update[pid] = now
            self.metrics.record_heartbeat(sid)

            if self.metrics.heartbeats_total % 100 == 0:
                logger.info(f"Heartbeat 100x: {pid}")

            if STORE_GHOSTS:
                self._store_ghost(pid, sid, data)

            for sub in self.event_subscribers:
                try:
                    await sub.send_json(data)
                except Exception:
                    pass

    async def handle_events_ws(self, request):
        # Allow token in query param for WebSockets as browser API doesn't support headers
        token = request.query.get("token")
        if token == BRIDGE_TOKEN:
            pass # Authorized
        else:
            guard = self._auth_guard(request)
            if guard is not None:
                return guard

        ws = web.WebSocketResponse(compress=True)
        await ws.prepare(request)
        self.event_subscribers.add(ws)
        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.CLOSE:
                    break
        finally:
            self.event_subscribers.discard(ws)
        return ws

    async def handle_deploy_webhook(self, request):
        """GitHub push webhook: validate HMAC, then run the deploy script detached.

        Configure on GitHub: Settings -> Webhooks -> Payload URL
        https://odisea.educa.juegos/webhook/deploy, Content type application/json,
        Secret = the bridge token (or DEPLOY_WEBHOOK_SECRET), events = "Just the push event".
        """
        if not DEPLOY_WEBHOOK_SECRET:
            return web.json_response({"error": "deploy webhook disabled"}, status=503)

        body = await request.read()

        # Validate GitHub's HMAC-SHA256 signature over the raw body.
        sig_header = request.headers.get("X-Hub-Signature-256", "")
        expected = "sha256=" + hmac.new(
            DEPLOY_WEBHOOK_SECRET.encode(), body, hashlib.sha256
        ).hexdigest()
        if not hmac.compare_digest(sig_header, expected):
            logger.warning("deploy webhook: bad signature from %s", self._client_ip(request))
            return web.json_response({"error": "invalid signature"}, status=401)

        # Only redeploy on a push to the configured branch.
        event = request.headers.get("X-GitHub-Event", "")
        if event == "ping":
            return web.json_response({"ok": True, "pong": True})
        if event != "push":
            return web.json_response({"ok": True, "ignored": f"event={event}"})

        try:
            payload = json.loads(body or b"{}")
        except json.JSONDecodeError:
            payload = {}
        ref = payload.get("ref", "")
        if ref != f"refs/heads/{DEPLOY_BRANCH}":
            return web.json_response({"ok": True, "ignored": f"ref={ref}"})

        # Skip the redeploy unless the push touched central's dependencies.
        if DEPLOY_PATHS:
            changed = set()
            for commit in payload.get("commits", []):
                changed.update(commit.get("added", []))
                changed.update(commit.get("modified", []))
                changed.update(commit.get("removed", []))
            relevant = any(
                f.startswith(prefix) for f in changed for prefix in DEPLOY_PATHS
            )
            # If the payload carried commits but none are relevant, skip. (When
            # commits is empty — e.g. a forced/edge case — fall through and deploy
            # to stay safe.)
            if changed and not relevant:
                logger.info("deploy webhook: no relevant paths in push, skipping (%d files)", len(changed))
                return web.json_response({"ok": True, "skipped": "no relevant paths"})

        if not os.path.exists(DEPLOY_SCRIPT):
            logger.error("deploy webhook: script not found at %s", DEPLOY_SCRIPT)
            return web.json_response({"error": "deploy script not found"}, status=500)

        # Run detached so the deploy can restart this process without killing
        # the script mid-flight. Logs go to a file next to the script.
        log_path = os.path.join(os.path.dirname(DEPLOY_SCRIPT), "deploy.log")
        logger.info("deploy webhook: triggering %s (ref=%s)", DEPLOY_SCRIPT, ref)
        try:
            with open(log_path, "ab") as logf:
                subprocess.Popen(
                    ["/bin/bash", DEPLOY_SCRIPT],
                    stdout=logf,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    cwd=os.path.dirname(DEPLOY_SCRIPT),
                    start_new_session=True,  # detach from this process group
                )
        except Exception as e:
            logger.error("deploy webhook: failed to spawn deploy (%s)", e)
            return web.json_response({"error": str(e)}, status=500)

        return web.json_response({"ok": True, "deploying": True, "ref": ref})

    async def _db_worker(self):
        """Background worker for SQLite writes (performance fix)."""
        conn = self._get_db()
        cursor = conn.cursor()

        # Ensure the schema exists before any INSERT/SELECT. Without this, a
        # fresh deploy (DB with no heartbeats table) makes every /api/ghosts*
        # query return {"error": "no such table"}, which the dashboard then
        # tries to .map() over and crashes.
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS heartbeats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                player_id TEXT,
                session_id TEXT,
                timestamp REAL,
                scene TEXT,
                platform TEXT,
                fps REAL,
                memory_mb REAL,
                pos_x REAL,
                pos_y REAL,
                pos_z REAL,
                engine_version TEXT,
                peer_id TEXT,
                UNIQUE(player_id, session_id, timestamp)
            );
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_scene ON heartbeats(scene);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_timestamp ON heartbeats(timestamp);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_platform ON heartbeats(platform);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_session ON heartbeats(session_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_combined ON heartbeats(player_id, scene, timestamp);")
        conn.commit()

        while True:
            try:
                batch = []
                # Wait for at least one item
                batch.append(await self.db_queue.get())

                # Try to drain more items if available
                while not self.db_queue.empty() and len(batch) < 100:
                    batch.append(self.db_queue.get_nowait())

                for data in batch:
                    player_data = data.get("player", {})
                    pos = player_data.get("position", [0, 0, 0])
                    platform = player_data.get("platform") or data.get("platform") or "unknown"

                    cursor.execute("""
                        INSERT OR IGNORE INTO heartbeats (
                            player_id, session_id, timestamp, scene, platform,
                            fps, memory_mb, pos_x, pos_y, pos_z,
                            engine_version, peer_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        data.get("player_id"),
                        data.get("session_id"),
                        data.get("timestamp"),
                        player_data.get("scene"),
                        platform,
                        player_data.get("fps"),
                        player_data.get("memory_mb"),
                        pos[0], pos[1], pos[2],
                        data.get("engine_version") or data.get("godot_version"),
                        data.get("peer_id")
                    ))

                conn.commit()
                for _ in batch:
                    self.db_queue.task_done()
            except Exception as e:
                logger.error(f"DB worker error: {e}")
                await asyncio.sleep(1)

    def _store_ghost(self, pid: str, sid: str, data: dict):
        # Queue for SQLite in background (Prompt 6)
        self.db_queue.put_nowait(data.copy())

        try:
            p_dir = os.path.join(GHOSTS_DIR, pid)
            os.makedirs(p_dir, exist_ok=True)

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

    async def handle_index(self, request):
        index_path = os.path.join(STATIC_DIR, "index.html")
        if os.path.exists(index_path):
            return web.FileResponse(index_path)
        return web.Response(text="<h1>Odisea Central</h1><p>Dashboard not built. Check /health for metrics.</p>", content_type="text/html")

    async def handle_pwa_root_file(self, request):
        """Serve PWA files that live at the dashboard root (sw.js, manifest,
        icons, ...). These aren't under /assets/, so they need their own route.
        Only an allowlist of filenames is served, to avoid path traversal."""
        name = request.match_info.get("name", "")
        allowed = {
            "sw.js", "registerSW.js", "manifest.webmanifest",
            "favicon.svg", "icons.svg",
            "pwa-192x192.png", "pwa-512x512.png", "apple-touch-icon.png",
        }
        # Workbox emits a hashed runtime file (workbox-<hash>.js).
        is_workbox = name.startswith("workbox-") and name.endswith(".js")
        if name not in allowed and not is_workbox:
            return web.Response(status=404)
        fpath = os.path.join(STATIC_DIR, name)
        if not os.path.isfile(fpath):
            return web.Response(status=404)
        # The service worker must not be cached, or clients get stuck on an old
        # SW that never updates.
        headers = {}
        if name == "sw.js" or name == "registerSW.js":
            headers["Cache-Control"] = "no-cache"
        return web.FileResponse(fpath, headers=headers)

    # --- SQLite Helpers ---
    def _get_db(self):
        conn = sqlite3.connect(SQLITE_DB)
        try:
            conn.execute("PRAGMA compression_level=3")
        except sqlite3.OperationalError:
            pass
        return conn

    async def _run_query(self, func, *args):
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, func, *args)


    async def _import_task(self):
        while True:
            try:
                import subprocess
                logger.info("Running periodic ghost import...")
                result = subprocess.run(["python3", "scripts/import_ghosts_to_sqlite.py"], capture_output=True, text=True)
                if result.returncode == 0:
                    logger.info("Periodic import finished successfully.")
                else:
                    logger.error(f"Periodic import failed: {result.stderr}")
            except Exception as e:
                logger.error(f"Error in import task: {e}")
            await asyncio.sleep(300)

    async def run(self):
        app = web.Application()
        app.add_routes([
            web.get('/', self.handle_index),
            web.get('/ws', self.handle_ws),
            web.get('/events', self.handle_events_ws),
            web.get('/status', self.handle_status),
            web.get('/sessions', self.handle_sessions),
            web.get('/sessions/{player_id}/{session_id}', self.handle_download_session),
            web.get('/ghosts', self.handle_ghosts),
            web.get('/ghosts/heatmap', self.handle_ghosts_heatmap),
            web.get('/ghosts/sessions', self.handle_ghosts_sessions),
            web.get('/ghosts/active', self.handle_ghosts_active),
            web.get('/ghosts/stats', self.handle_ghosts_stats),
            web.get('/scenes', self.handle_scenes),
            web.post('/command', self.handle_command),
            web.get('/health', self.handle_health),
            web.post('/telemetry', self.handle_web_telemetry),
            web.get('/telemetry/web', self.handle_web_telemetry_list),
            web.options('/telemetry', self.handle_web_telemetry_options),

            # CI/CD: GitHub push webhook -> pull + redeploy
            web.post('/webhook/deploy', self.handle_deploy_webhook),

            # PWA root files (sw.js, manifest, icons, workbox-*.js). Registered
            # last so the single-segment match doesn't shadow the routes above;
            # the handler allowlists filenames and 404s anything else.
            web.get('/{name}', self.handle_pwa_root_file),
        ])

        if os.path.exists(STATIC_DIR):
            app.router.add_static('/assets/', path=os.path.join(STATIC_DIR, "assets"), name='assets')
            logger.info(f"Serving static assets from {STATIC_DIR}/assets")

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', CENTRAL_HTTP_PORT)
        await site.start()
        logger.info(f"Odisea Central V2 running on port {CENTRAL_HTTP_PORT}")

        cleanup_task = asyncio.create_task(self._cleanup_loop())
        db_worker_task = asyncio.create_task(self._db_worker())
        import_task = asyncio.create_task(self._import_task())

        try:
            while True:
                await asyncio.sleep(3600)
        finally:
            cleanup_task.cancel()
            db_worker_task.cancel()
            import_task.cancel()
            await runner.cleanup()

if __name__ == "__main__":
    if BRIDGE_TOKEN == DEV_DEFAULT_TOKEN:
        logger.warning("Using INSECURE dev default token. Set ODISEA_BRIDGE_TOKEN for production.")

    central = OdiseaCentral()
    try:
        asyncio.run(central.run())
    except KeyboardInterrupt:
        pass
