import asyncio
import base64
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
from pywebpush import webpush, WebPushException

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

VALID_PLATFORMS = {"linux", "windows", "macos", "android", "html5", "ios"}
VALID_CHANNELS = {"release", "nightly"}
MANIFEST_ACCEPT_HEADER = "application/vnd.odisea.update-manifest.v1+json"

GITHUB_RELEASES_URL = "https://api.github.com/repos/icarito/Odisea/releases/latest"
DOWNLOADS_PAGE_URL = "https://icarito.github.io/odisea-neon-dreams/#downloads"
WEB_URL = "https://odisea-game.netlify.app"

# PWA Push Notifications (FD-167)
VAPID_PUBLIC_KEY = os.environ.get("ODISEA_VAPID_PUBLIC_KEY")
VAPID_PRIVATE_KEY = os.environ.get("ODISEA_VAPID_PRIVATE_KEY")
VAPID_CLAIMS = {"sub": "mailto:admin@odisea.dev"}
DEV_DEFAULT_TOKEN = "odisea-dev-insecure"
BRIDGE_TOKEN = os.environ.get("ODISEA_BRIDGE_TOKEN", DEV_DEFAULT_TOKEN)
INGEST_TOKEN = os.environ.get("ODISEA_CENTRAL_INGEST_TOKEN", "")

CACHE_TTL = int(os.environ.get("CENTRAL_CACHE_TTL", 120))
STORE_GHOSTS = os.environ.get("CENTRAL_STORE_GHOSTS", "true").lower() == "true"
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
SQLITE_DB = os.environ.get("CENTRAL_SQLITE_DB", os.environ.get("CENTRAL_DB_PATH", "./data/ghosts.db"))
GEO_SQLITE_DB = os.environ.get("CENTRAL_GEO_DB", "./data/geo_tags.db")
DASHBOARD_VERSION = os.environ.get("ODISEA_DASHBOARD_VERSION", os.environ.get("GITHUB_SHA", ""))[:12] or "dev"
# Salt for hashing client IPs before they touch disk. MUST match the salt used
# by scripts/import_nginx_geo.py (ODISEA_GEO_HASH_SALT) so live-recorded hashes
# line up with any backfilled rows. No raw IP is ever persisted.
GEO_HASH_SALT = os.environ.get("ODISEA_GEO_HASH_SALT", "odisea-public-geo-v1")
HOTZONES_DIR = os.environ.get("CENTRAL_HOTZONES_DIR", "./data/hotzones")
GHOSTS_MAX_BYTES = int(os.environ.get("CENTRAL_GHOSTS_MAX_BYTES", 1073741824))  # 1GB
STATIC_DIR = os.environ.get("CENTRAL_STATIC_DIR", "./dashboard/dist")

# Global, server-side telemetry filtering. The headless server peer is never a
# real client, and the first seconds of every session (scene load, GC, chunk
# streaming) skew FPS/memory — both are excluded here so every dashboard
# consumer sees clean runtime data without re-filtering. Mirrors the frontend
# WARMUP_SECONDS in dashboard/src/lib/filters.ts.
WARMUP_SECONDS = int(os.environ.get("CENTRAL_WARMUP_SECONDS", 13))

# SQL fragment: exclude the headless server peer (case-insensitive).
_NOT_SERVER = "LOWER(COALESCE(platform,'')) != 'server'"

# SQL fragment: keep only focused (foreground) samples for FPS/perf aggregation.
# A backgrounded game throttles itself and drops FPS, which would otherwise skew
# avg_fps / low_fps stats and paint fake heatmap hotspots. Rows predating the
# `focused` column default to 1, so historical data is unaffected.
_FOCUSED_ONLY = "COALESCE(focused, 1) = 1"

# SQL fragment: exclude automated test telemetry by default. Test runners do
# not consistently report platform=server, so use the persisted identifiers and
# scene metadata that survives JSONL imports into SQLite.
_NOT_TEST_TELEMETRY = """
NOT (
    LOWER(COALESCE(platform,'')) IN ('test', 'tests')
    OR SUBSTR(LOWER(COALESCE(player_id,'')), 1, 5) IN ('test-', 'test_')
    OR SUBSTR(LOWER(COALESCE(player_id,'')), 1, 10) IN ('ratelimit-', 'ratelimit_')
    OR SUBSTR(LOWER(COALESCE(session_id,'')), 1, 5) IN ('test-', 'test_')
    OR SUBSTR(LOWER(COALESCE(session_id,'')), 1, 10) IN ('ratelimit-', 'ratelimit_')
    OR LOWER(COALESCE(scene,'')) LIKE 'res://%/tests/%'
    OR LOWER(COALESCE(scene,'')) LIKE 'res://tests/%'
    OR LOWER(COALESCE(scene,'')) LIKE 'test%'
)
"""

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


def semver_lt(v1: str, v2: str) -> bool:
    """Returns True if v1 < v2 using SemVer comparison (major.minor.patch)."""
    try:
        def parse(v):
            # Strip 'v' prefix if present and split by '.', take first 3 parts as ints
            parts = v.lstrip('v').split('+')[0].split('-')[0].split('.')
            res = [int(p) for p in parts[:3]]
            while len(res) < 3:
                res.append(0)
            return res
        return parse(v1) < parse(v2)
    except (ValueError, IndexError):
        return False


MILESTONES = [
    # Players
    ("players_10", "10 jugadores únicos", "users"),
    ("players_50", "50 jugadores únicos", "users"),
    ("players_100", "100 jugadores únicos", "users"),
    ("players_500", "500 jugadores únicos", "users"),
    ("players_1000", "1,000 jugadores únicos", "users"),
    # Concurrent
    ("concurrent_5", "5 jugadores simultáneos", "zap"),
    ("concurrent_10", "10 jugadores simultáneos", "zap"),
    ("concurrent_25", "25 jugadores simultáneos", "zap"),
    # Heartbeats
    ("heartbeats_10k", "10,000 heartbeats", "activity"),
    ("heartbeats_100k", "100,000 heartbeats", "activity"),
    ("heartbeats_1m", "1,000,000 heartbeats", "activity"),
    # Gameplay time
    ("gameplay_1h", "1 hora de gameplay acumulado", "clock"),
    ("gameplay_10h", "10 horas de gameplay acumulado", "clock"),
    ("gameplay_100h", "100 horas de gameplay acumulado", "clock"),
    # Performance
    ("nobadfps_1h", "1 hora sin FPS bajo", "heart"),
    ("nobadfps_24h", "24 horas sin FPS bajo", "heart"),
    # Sessions
    ("sessions_10", "10 sesiones de juego", "play"),
    ("sessions_100", "100 sesiones de juego", "play"),
]

class MilestoneDetector:
    def __init__(self, central: 'OdiseaCentral'):
        self.central = central
        self.unique_players: Set[str] = set()
        self.total_heartbeats = 0
        self.total_gameplay_seconds = 0.0
        self.max_concurrent = 0
        self.last_low_fps_at = time.time()
        self.sessions_seen: Set[str] = set()
        self.achieved_ids: Set[str] = set()
        self.check_counter = 0
        self.session_last_ts: Dict[str, float] = {}  # session_id -> last timestamp

    async def load(self):
        """Initializes metrics from the SQLite database."""
        def fetch():
            conn = self.central._get_db()
            cursor = conn.cursor()
            
            # Ensure table exists
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS milestones (
                    milestone_id TEXT PRIMARY KEY,
                    title TEXT,
                    icon TEXT,
                    achieved_at REAL,
                    value REAL
                );
            """)
            
            visible_sql = self.central._visibility_sql(include_server=False, include_tests=False)
            
            try:
                # Unique players
                cursor.execute(f"SELECT DISTINCT player_id FROM heartbeats WHERE {visible_sql}")
                self.unique_players = {r[0] for r in cursor.fetchall() if r[0]}
                
                # Sessions
                cursor.execute(f"SELECT DISTINCT session_id FROM heartbeats WHERE {visible_sql}")
                self.sessions_seen = {r[0] for r in cursor.fetchall() if r[0]}
                
                # Total heartbeats
                cursor.execute(f"SELECT COUNT(*) FROM heartbeats WHERE {visible_sql}")
                self.total_heartbeats = cursor.fetchone()[0] or 0
                
                # Gameplay time estimation
                cursor.execute(f"""
                    SELECT session_id, MIN(timestamp), MAX(timestamp)
                    FROM heartbeats
                    WHERE {visible_sql}
                    GROUP BY session_id
                """)
                total_duration = 0
                for row in cursor.fetchall():
                    if row[1] and row[2]:
                        total_duration += (row[2] - row[1])
                self.total_gameplay_seconds = total_duration

                # Max concurrent
                cursor.execute(f"""
                    SELECT MIN(timestamp) AS start, MAX(timestamp) AS end
                    FROM heartbeats WHERE {visible_sql}
                    GROUP BY player_id, session_id
                """)
                events = []
                for row in cursor.fetchall():
                    if row[0] is not None and row[1] is not None:
                        events.append((row[0], 1))
                        events.append((row[1], -1))
                events.sort()
                cur_c = max_c = 0
                for _, delta in events:
                    cur_c += delta
                    max_c = max(max_c, cur_c)
                self.max_concurrent = max_c
                
                # Last low FPS (focused samples only — backgrounded games drop FPS legitimately)
                cursor.execute(f"SELECT MAX(timestamp) FROM heartbeats WHERE fps < 15 AND {_FOCUSED_ONLY} AND {visible_sql}")
                row = cursor.fetchone()
                if row and row[0]:
                    self.last_low_fps_at = row[0]

            except sqlite3.OperationalError:
                # heartbeats table might not exist yet
                pass

            # Achieved milestones
            cursor.execute("SELECT milestone_id FROM milestones")
            self.achieved_ids = {r[0] for r in cursor.fetchall()}
            
            conn.close()

        await self.central._run_query(fetch)
        logger.info(f"MilestoneDetector loaded: {len(self.unique_players)} players, "
                    f"{self.total_heartbeats} heartbeats, {len(self.achieved_ids)} achieved")

    def record_heartbeat(self, data: dict):
        """Updates internal metrics based on incoming heartbeat data."""
        if self.central._is_test_telemetry(data):
            return

        self.total_heartbeats += 1
        
        pid = data.get("player_id")
        if pid:
            self.unique_players.add(pid)
            
        sid = data.get("session_id")
        if sid:
            self.sessions_seen.add(sid)
            ts = data.get("timestamp") or time.time()
            if sid in self.session_last_ts:
                delta = ts - self.session_last_ts[sid]
                if 0 < delta < 60:  # Ignore large gaps or backward jumps
                    self.total_gameplay_seconds += delta
            self.session_last_ts[sid] = ts

        # Concurrent players (approximate via active cache)
        # We only count visible telemetry here as well.
        active_now = len([hb for hb in self.central.heartbeats.values() 
                         if self.central._is_visible_telemetry(hb)])
        if active_now > self.max_concurrent:
            self.max_concurrent = active_now

    def record_low_fps(self):
        """Resets the timer for 'time without low FPS' milestone."""
        self.last_low_fps_at = time.time()

    async def check_and_notify(self):
        """Checks metrics against MILESTONES and triggers push notifications."""
        self.check_counter += 1
        if self.check_counter % 50 != 0:
            return

        now = time.time()
        no_bad_fps_seconds = now - self.last_low_fps_at
        
        for mid, title, icon in MILESTONES:
            if mid in self.achieved_ids:
                continue
                
            achieved = False
            value = 0
            
            if mid.startswith("players_"):
                threshold = int(mid.split("_")[1].replace("k", "000"))
                value = len(self.unique_players)
                if value >= threshold: achieved = True
            elif mid.startswith("concurrent_"):
                threshold = int(mid.split("_")[1])
                value = self.max_concurrent
                if value >= threshold: achieved = True
            elif mid.startswith("heartbeats_"):
                suffix = mid.split("_")[1]
                if suffix == "10k": threshold = 10000
                elif suffix == "100k": threshold = 100000
                elif suffix == "1m": threshold = 1000000
                else: threshold = 0
                value = self.total_heartbeats
                if value >= threshold: achieved = True
            elif mid.startswith("gameplay_"):
                hours = int(mid.split("_")[1].replace("h", ""))
                threshold = hours * 3600
                value = self.total_gameplay_seconds
                if value >= threshold: achieved = True
            elif mid.startswith("nobadfps_"):
                hours = int(mid.split("_")[1].replace("h", ""))
                threshold = hours * 3600
                value = no_bad_fps_seconds
                if value >= threshold: achieved = True
            elif mid.startswith("sessions_"):
                threshold = int(mid.split("_")[1])
                value = len(self.sessions_seen)
                if value >= threshold: achieved = True

            if achieved:
                self.achieved_ids.add(mid)
                logger.info(f"🏆 Milestone achieved: {title} ({mid})")
                
                # Persist
                def save():
                    conn = self.central._get_db()
                    cursor = conn.cursor()
                    cursor.execute("""
                        INSERT OR REPLACE INTO milestones (milestone_id, title, icon, achieved_at, value)
                        VALUES (?, ?, ?, ?, ?)
                    """, (mid, title, icon, now, float(value)))
                    conn.commit()
                    conn.close()
                
                await self.central._run_query(save)
                
                # Notify
                payload = {
                    "type": "milestone",
                    "milestone_id": mid,
                    "title": "¡Hito alcanzado!",
                    "message": title,
                    "icon": icon,
                    "value": value,
                    "timestamp": now
                }
                asyncio.create_task(self.central.send_push_to_all(payload))

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

        # When the deployed dashboard was last written (index.html mtime). Lets the
        # header show a real deploy date next to the dashboard version.
        dashboard_deployed_at = None
        try:
            index_path = os.path.join(STATIC_DIR, "index.html")
            if os.path.exists(index_path):
                dashboard_deployed_at = os.path.getmtime(index_path)
        except OSError:
            pass

        return {
            "ok": True,
            "mode": "central",
            "dashboard_version": DASHBOARD_VERSION,
            "dashboard_deployed_at": dashboard_deployed_at,
            "latest_published": central._latest_published_build(),
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
        self.last_known_hb: Dict[str, dict] = {}  # player_id -> last hb before disconnect
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
        self.geo_recorded_sessions: Set[str] = set()  # session_ids already geo-recorded this run
        self.geo_pending_lookup: Dict[str, str] = {}  # ip_hash -> raw IP awaiting geolocation (memory-only)
        self.scene_geometry_cache: Dict[str, dict] = {}  # scene -> {"mtime": float, "data": dict, "grid": dict}
        self.milestone_checker = MilestoneDetector(self)
        self._manifest_cache: Dict[tuple, dict] = {}  # (channel, platform, arch) -> {ts, etag, content}

        if STORE_GHOSTS and not os.path.exists(GHOSTS_DIR):
            os.makedirs(GHOSTS_DIR, exist_ok=True)
            logger.info(f"Created ghosts directory: {GHOSTS_DIR}")
        if not os.path.exists(HOTZONES_DIR):
            os.makedirs(HOTZONES_DIR, exist_ok=True)
            logger.info(f"Created hotzones directory: {HOTZONES_DIR}")

    # --- Auth Logic ---
    def _bearer_token(self, request) -> str:
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return ""
        return auth_header[7:]

    def _is_admin_token(self, token: str) -> bool:
        return token == BRIDGE_TOKEN

    def _is_ingest_token(self, token: str) -> bool:
        if token == BRIDGE_TOKEN:
            return True
        return INGEST_TOKEN != "" and token == INGEST_TOKEN

    def _is_authorized(self, request):
        return self._is_admin_token(self._bearer_token(request))

    def _is_ingest_authorized(self, request):
        return self._is_ingest_token(self._bearer_token(request))

    def _auth_guard(self, request, scope: str = "admin"):
        ip = self._client_ip(request)
        now = time.time()
        if self._is_locked(ip, now):
            retry = int(self.auth_fails[ip]["locked_until"] - now)
            return web.json_response(
                {"error": "rate_limited", "retry_after": retry},
                status=429, headers={"Retry-After": str(max(1, retry))},
            )

        if scope == "ingest":
            authorized = self._is_ingest_authorized(request)
        else:
            authorized = self._is_authorized(request)

        if not authorized:
            self._record_auth_fail(ip, now)
            return web.json_response({"error": "unauthorized"}, status=401)
        self.auth_fails.pop(ip, None)
        return None

    def _token_mode(self, token: str) -> str:
        if self._is_admin_token(token):
            return "admin"
        if self._is_ingest_token(token):
            return "ingest"
        return "telemetry"

    def _client_ip(self, request) -> str:
        fwd = request.headers.get("X-Forwarded-For", "")
        if fwd:
            return fwd.split(",")[0].strip()
        return request.remote or "unknown"

    def _include_flag(self, request, name: str) -> bool:
        return request.query.get(name, "").lower() in ("1", "true", "yes", "on")

    def _visibility_sql(self, include_server: bool = False, include_tests: bool = False) -> str:
        parts = []
        if not include_server:
            parts.append(_NOT_SERVER)
        if not include_tests:
            parts.append(_NOT_TEST_TELEMETRY)
        return " AND ".join(parts) if parts else "1 = 1"

    def _is_test_telemetry(self, hb: dict) -> bool:
        player_data = hb.get("player", {}) if isinstance(hb.get("player"), dict) else {}
        values = {
            "platform": str(player_data.get("platform") or hb.get("platform") or "").lower(),
            "build_channel": str(hb.get("build_channel") or "").lower(),
            "player_id": str(hb.get("player_id") or "").lower(),
            "session_id": str(hb.get("session_id") or "").lower(),
            "scene": str(player_data.get("scene") or hb.get("scene") or "").lower(),
        }
        if values["platform"] in ("test", "tests") or values["build_channel"] in ("test", "tests", "ci"):
            return True
        for key in ("player_id", "session_id"):
            value = values[key]
            if value.startswith(("test-", "test_", "ratelimit-", "ratelimit_")):
                return True
        scene = values["scene"]
        return scene.startswith("test") or scene.startswith("res://tests/") or "/tests/" in scene

    def _is_visible_telemetry(self, hb: dict, include_server: bool = False, include_tests: bool = False) -> bool:
        player_data = hb.get("player", {}) if isinstance(hb.get("player"), dict) else {}
        platform = str(player_data.get("platform") or hb.get("platform") or "").lower()
        if not include_server and platform == "server":
            return False
        if not include_tests and self._is_test_telemetry(hb):
            return False
        return True

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

    async def _cleanup_loop(self):
        while True:
            try:
                now = time.time()
                to_delete_hb = [pid for pid, last in self.last_update.items() if now - last > CACHE_TTL]
                for pid in to_delete_hb:
                    hb = self.heartbeats.pop(pid, None)
                    self.last_update.pop(pid, None)
                    if hb:
                        pass  # Disconnect push suppressed (too noisy from heartbeat timeouts)
                        # Only WebSocket-level disconnects trigger push (see _process_ws_message finally block)

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

    async def _get_manifest(self, channel: str, platform: str, arch: str) -> Optional[dict]:
        """Fetch and cache the signed manifest from GitHub.
        Returns:
            - The cache entry dict if found/fetched.
            - {} (empty dict) if GitHub is UP but the asset is NOT FOUND (204 candidate).
            - None if GitHub is DOWN and no cache is available (503 candidate).
        """
        now = time.time()
        cache_key = (channel, platform, arch)
        cached = self._manifest_cache.get(cache_key)

        # 5 minutes TTL
        if cached and now - cached["ts"] < 300:
            return cached

        try:
            import urllib.request

            # 1. Fetch release metadata to find the asset URL
            if channel == "release":
                api_url = GITHUB_RELEASES_URL
            else:
                api_url = f"https://api.github.com/repos/icarito/Odisea/releases/tags/{channel}"

            headers = {"Accept": "application/vnd.github.v3+json", "User-Agent": "Odisea-Central-Bridge"}

            def fetch_json(url):
                req = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(req, timeout=10) as response:
                    return json.loads(response.read().decode())

            release_data = await asyncio.get_running_loop().run_in_executor(None, fetch_json, api_url)

            asset_name = f"manifest-{platform}-{arch}.json"
            asset_url = None
            for asset in release_data.get("assets", []):
                if asset.get("name") == asset_name:
                    asset_url = asset.get("url")
                    break

            if not asset_url:
                logger.info(f"Manifest asset {asset_name} not found in {channel} release")
                # Mark as not found in cache too to avoid re-fetching for 5 min
                self._manifest_cache[cache_key] = {"ts": now, "not_found": True}
                return {}

            # 2. Fetch the actual manifest content (the signed envelope)
            # GitHub Assets API requires a different Accept header for raw data
            asset_headers = headers.copy()
            asset_headers["Accept"] = "application/octet-stream"

            def fetch_raw(url):
                req = urllib.request.Request(url, headers=asset_headers)
                with urllib.request.urlopen(req, timeout=10) as response:
                    content = response.read()
                    if len(content) > 2 * 1024 * 1024:  # 2 MiB limit
                        raise ValueError("Manifest envelope too large")
                    return content

            content = await asyncio.get_running_loop().run_in_executor(None, fetch_raw, asset_url)

            etag = hashlib.sha256(content).hexdigest()
            entry = {
                "ts": now,
                "etag": etag,
                "content": content
            }
            self._manifest_cache[cache_key] = entry
            return entry

        except Exception as e:
            logger.error(f"Failed to fetch manifest for {cache_key}: {e}")
            # stale-if-error: up to 24 hours
            if cached and now - cached["ts"] < 86400:
                logger.info(f"Serving stale manifest for {cache_key}")
                return cached
            return None

    async def handle_update_manifest(self, request):
        """GET /game/updates/v1/manifest"""
        if request.headers.get("Accept") != MANIFEST_ACCEPT_HEADER:
            return web.json_response({"error": "invalid_accept_header"}, status=400)

        channel = request.query.get("channel")
        platform = request.query.get("platform")
        arch = request.query.get("arch")
        current_version = request.query.get("current_version")
        current_build_id = request.query.get("current_build_id")

        if not all([channel, platform, arch, current_version, current_build_id]):
            return web.json_response({"error": "missing_parameters"}, status=400)

        if channel not in VALID_CHANNELS:
            return web.json_response({"error": "invalid_channel"}, status=400)
        if platform not in VALID_PLATFORMS:
            return web.json_response({"error": "invalid_platform"}, status=400)

        manifest_entry = await self._get_manifest(channel, platform, arch)
        if manifest_entry is None:
            return web.json_response({"error": "origin_unavailable"}, status=503)
        if manifest_entry == {} or manifest_entry.get("not_found"):
            return web.Response(status=204)

        # Cache/ETag check
        if_none_match = request.headers.get("If-None-Match", "").strip('"')
        if if_none_match == manifest_entry["etag"]:
            return web.Response(status=304)

        # Parse signed envelope to check version/build
        envelope = {}
        try:
            envelope = json.loads(manifest_entry["content"].decode("utf-8"))
            payload_raw = base64.b64decode(envelope.get("payload_b64", ""))
            payload = json.loads(payload_raw.decode("utf-8"))

            # 204 if already on this build
            if str(payload.get("build_id")) == str(current_build_id):
                return web.Response(status=204)

            # 409 if current version is too old (unsupported)
            min_v = payload.get("min_supported_version")
            if min_v and semver_lt(current_version, min_v):
                return web.Response(
                    body=manifest_entry["content"],
                    status=409,
                    content_type="application/json",
                    headers={"ETag": f'"{manifest_entry["etag"]}"'}
                )
        except Exception as e:
            logger.error(f"Error parsing manifest for check: {e}")
            # If we can't parse it to check version, still serve it as-is if
            # it's a valid envelope format, otherwise 503.
            if not isinstance(envelope, dict) or "payload_b64" not in envelope:
                return web.json_response({"error": "malformed_manifest"}, status=503)

        return web.Response(
            body=manifest_entry["content"],
            status=200,
            content_type="application/json",
            headers={"ETag": f'"{manifest_entry["etag"]}"'}
        )

    async def handle_game_version(self, request):
        """Returns the latest game version from GitHub Releases with 5-min caching."""
        now = time.time()
        if hasattr(self, "_game_version_cache"):
            cache_ts, cache_data = self._game_version_cache
            if now - cache_ts < 300:  # 5 minutes TTL
                return web.json_response(cache_data, headers={"Access-Control-Allow-Origin": "*"})

        try:
            import urllib.request
            req = urllib.request.Request(
                GITHUB_RELEASES_URL,
                headers={"Accept": "application/vnd.github.v3+json", "User-Agent": "Odisea-Central-Bridge"}
            )
            # Fetch from GitHub API (sync call in executor)
            def fetch():
                with urllib.request.urlopen(req, timeout=5) as response:
                    return json.loads(response.read().decode())

            data = await asyncio.get_running_loop().run_in_executor(None, fetch)
            version = data.get("tag_name", "v0.0.0")
            release_url = data.get("html_url", "")

            version_info = {
                "version": version,
                "latest_release_url": release_url,
                "web_url": WEB_URL,
                "downloads_page": DOWNLOADS_PAGE_URL
            }
            self._game_version_cache = (now, version_info)
            return web.json_response(version_info, headers={"Access-Control-Allow-Origin": "*"})

        except Exception as e:
            logger.warning(f"Failed to fetch game version from GitHub: {e}")
            # Fallback to last cached if available, even if expired
            if hasattr(self, "_game_version_cache"):
                return web.json_response(self._game_version_cache[1], headers={"Access-Control-Allow-Origin": "*"})
            return web.json_response({"error": "failed_to_fetch_version"}, status=502, headers={"Access-Control-Allow-Origin": "*"})

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

    async def handle_vapid_public_key(self, request):
        """Returns the VAPID public key for frontend subscription."""
        if not VAPID_PUBLIC_KEY:
            return web.json_response({"error": "VAPID keys not configured"}, status=503)
        return web.json_response({"publicKey": VAPID_PUBLIC_KEY})

    async def handle_push_subscribe(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            data = await request.json()
            subscription = data.get("subscription")
            player_id = data.get("player_id", "admin")
            settings = data.get("settings", {})
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)

        if not subscription:
            return web.json_response({"error": "missing_subscription"}, status=400)

        try:
            def save():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT OR REPLACE INTO push_subscriptions (subscription_json, player_id, settings_json, updated_at)
                    VALUES (?, ?, ?, ?)
                """, (json.dumps(subscription), player_id, json.dumps(settings), time.time()))
                conn.commit()
                conn.close()

            await self._run_query(save)
            logger.info(f"Push subscription saved for {player_id}")
            return web.json_response({"ok": True})
        except Exception as e:
            logger.error(f"Failed to save push subscription: {e}")
            return web.json_response({"error": str(e)}, status=500)

    async def handle_push_send(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            payload = await request.json()
        except Exception:
            return web.json_response({"error": "invalid_json"}, status=400)

        await self.send_push_to_all(payload)
        return web.json_response({"ok": True})

    async def send_push_to_all(self, payload: dict):
        """Sends a push notification to all registered subscriptions, with cooldown per event type."""
        if not VAPID_PRIVATE_KEY:
            logger.warning("Push notification skipped: VAPID_PRIVATE_KEY not set")
            return

        msg_type = payload.get("type", "")
        # Cooldown per event type to prevent spam (seconds)
        cooldowns = {"disconnect": 300, "alert": 300, "bridge_status": 600, "low_fps": 300}
        now = time.time()
        if msg_type in cooldowns:
            if not hasattr(self, 'push_cooldowns'):
                self.push_cooldowns = {}
            key = f"push_cooldown_{msg_type}"
            last = self.push_cooldowns.get(key, 0)
            if now - last < cooldowns[msg_type]:
                return
            self.push_cooldowns[key] = now

        try:
            def fetch_subs():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT subscription_json, settings_json FROM push_subscriptions")
                subs = [(json.loads(row[0]), json.loads(row[1] or "{}")) for row in cursor.fetchall()]
                conn.close()
                return subs

            subscriptions_with_settings = await self._run_query(fetch_subs)
            if not subscriptions_with_settings:
                return

            msg_type = payload.get("type")
            # Map payload type to settings key
            event_key = "alert" if msg_type == "alert" else "disconnect" if msg_type == "disconnect" else "bridge" if msg_type == "bridge_status" else None
            
            logger.info(f"Sending push (type={msg_type}) to suitable subscribers")
            
            # Send pushes in parallel
            tasks = []
            for sub, settings in subscriptions_with_settings:
                if event_key and not settings.get(event_key, True):
                    continue
                tasks.append(self._send_single_push(sub, payload))
            
            if tasks:
                await asyncio.gather(*tasks, return_exceptions=True)

        except Exception as e:
            logger.error(f"Error in send_push_to_all: {e}")

    async def _send_single_push(self, subscription: dict, payload: dict):
        try:
            # webpush is synchronous, run in executor
            await asyncio.get_running_loop().run_in_executor(None, lambda: webpush(
                subscription_info=subscription,
                data=json.dumps(payload),
                vapid_private_key=VAPID_PRIVATE_KEY,
                vapid_claims=VAPID_CLAIMS.copy()
            ))
        except WebPushException as ex:
            logger.warning(f"WebPush error: {ex}")
            # If 410 Gone, we should ideally remove the subscription
            if ex.response is not None and ex.response.status_code == 410:
                def remove_sub():
                    conn = self._get_db()
                    conn.execute("DELETE FROM push_subscriptions WHERE subscription_json = ?", (json.dumps(subscription),))
                    conn.commit()
                    conn.close()
                await self._run_query(remove_sub)
        except Exception as e:
            logger.error(f"Unexpected error in _send_single_push: {e}")

    async def handle_status(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        player_id = request.query.get("player_id")
        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        self.metrics.record_cache_lookup(player_id in self.heartbeats if player_id else True)

        if player_id:
            hb = self.heartbeats.get(player_id)
            if hb and self._is_visible_telemetry(hb, include_server, include_tests):
                tags = await self._run_query(self._fetch_player_tags)
                hb = hb.copy()
                tag = tags.get(player_id) or {}
                hb["display_name"] = tag.get("display_name")
                hb["color"] = tag.get("color")
                hb["notes"] = tag.get("notes")
                return web.json_response(hb)
            return web.json_response({"error": "not_found"}, status=404)

        tags = await self._run_query(self._fetch_player_tags)
        visible = {
            pid: {
                **hb,
                "display_name": (tags.get(pid) or {}).get("display_name"),
                "color": (tags.get(pid) or {}).get("color"),
                "notes": (tags.get(pid) or {}).get("notes"),
            }
            for pid, hb in self.heartbeats.items()
            if self._is_visible_telemetry(hb, include_server, include_tests)
        }
        return web.json_response(visible)

    async def handle_sessions(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        sessions = list(set(
            hb.get("session_id") for hb in self.heartbeats.values()
            if hb.get("session_id") and self._is_visible_telemetry(hb, include_server, include_tests)
        ))
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
        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")

        try:
            limit = min(max(int(request.query.get("limit", 1000)), 1), 5000)
        except ValueError:
            limit = 1000

        try:
            offset = int(request.query.get("offset", 0))
        except ValueError:
            offset = 0

        query = f"SELECT * FROM heartbeats WHERE {self._visibility_sql(include_server, include_tests)}"
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

        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        res = float(request.query.get("resolution", 5))
        low_fps_threshold = 30.0

        # Aggregate data by grid cell. perf.dc/obj/vtx/nodes are only populated
        # by ANNAV2 builds that send the `perf` sub-dict (older rows are NULL),
        # so we use AVG() which ignores NULLs — the resulting avg_perf_* fields
        # are null for cells with no instrumented samples.
        query = """
        SELECT
            CAST(pos_x / ? AS INTEGER) * ? as grid_x,
            CAST(pos_z / ? AS INTEGER) * ? as grid_z,
            COUNT(*) as count,
            SUM(CASE WHEN fps < ? THEN 1 ELSE 0 END) as low_fps_count,
            AVG(fps) as avg_fps,
            MIN(fps) as min_fps,
            AVG(memory_mb) as avg_mem,
            AVG(draw_calls) as avg_draw_calls,
            AVG(objects) as avg_objects,
            AVG(vertices) as avg_vertices,
            AVG(nodes) as avg_nodes
        FROM heartbeats
        WHERE scene = ? AND {visible} AND {past_warmup} AND {focused}
        GROUP BY grid_x, grid_z
        """.format(visible=self._visibility_sql(include_server, include_tests), past_warmup=_PAST_WARMUP, focused=_FOCUSED_ONLY)
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
            tags = await self._run_query(self._fetch_player_tags)
            geo_by_player = await self._run_query(
                self._fetch_geo_by_player_ids,
                [row.get("player_id") for row in rows],
            )
            for row in rows:
                tag = tags.get(row.get("player_id")) or {}
                geo = geo_by_player.get(row.get("player_id")) or {}
                row["display_name"] = tag.get("display_name")
                row["color"] = tag.get("color")
                row["country"] = geo.get("country")
                row["country_code"] = geo.get("country_code")
                row["region"] = geo.get("region")
                row["city"] = geo.get("city")
                row["latitude"] = geo.get("latitude")
                row["longitude"] = geo.get("longitude")
            return web.json_response(rows)
        except Exception as e:
            logger.warning(f"{request.path}: query failed, returning [] ({e})")
            return web.json_response([])

    def _load_scene_geometry(self, scene: str) -> Optional[dict]:
        if not scene or "/" in scene or "\\" in scene or ".." in scene:
            return None
        path = os.path.join(STATIC_DIR, "scene-data", f"{scene}.json")
        if not os.path.isfile(path):
            return None
        mtime = os.path.getmtime(path)
        cached = self.scene_geometry_cache.get(scene)
        if cached and cached.get("mtime") == mtime:
            return cached
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        cell_size = 48.0
        point_grid: Dict[tuple, list] = {}
        for point in data.get("points", []):
            try:
                cell = (
                    int(float(point[0]) // cell_size),
                    int(float(point[1]) // cell_size),
                    int(float(point[2]) // cell_size),
                )
            except (TypeError, ValueError, IndexError):
                continue
            point_grid.setdefault(cell, []).append(point)
        cached = {
            "mtime": mtime,
            "geometry_version": f"{data.get('version', 1)}:{int(mtime)}",
            "data": data,
            "cell_size": cell_size,
            "point_grid": point_grid,
            "stream_cache": {},
        }
        self.scene_geometry_cache[scene] = cached
        logger.info(
            "Indexed scene geometry %s: %s points in %s cells",
            scene,
            len(data.get("points", [])),
            len(point_grid),
        )
        return cached

    async def handle_scene_geometry_stream(self, request):
        """Return a nearest-first slice of scene geometry around a player.

        The full JSON remains available as /scene-data/<scene>.json for global
        maps. The 3D live viewport uses this endpoint so large scenes don't
        transfer or render the whole point cloud on every session.
        """
        scene = request.match_info.get("scene", "")
        try:
            center = (
                float(request.query.get("x", "0")),
                float(request.query.get("y", "0")),
                float(request.query.get("z", "0")),
            )
            radius = max(1.0, min(float(request.query.get("radius", "80")), 500.0))
            limit = max(100, min(int(request.query.get("limit", "12000")), 50000))
        except ValueError:
            return web.json_response({"error": "bad_query"}, status=400)

        scene_cache = self._load_scene_geometry(scene)
        if scene_cache is None:
            return web.json_response({"error": "scene_not_found"}, status=404)
        data = scene_cache["data"]
        stream_cache = scene_cache.setdefault("stream_cache", {})
        cache_key = (
            round(center[0], 3),
            round(center[1], 3),
            round(center[2], 3),
            round(radius, 3),
            limit,
        )
        cached_response = stream_cache.get(cache_key)
        if cached_response is not None:
            return web.json_response(cached_response)

        cx, cy, cz = center
        radius_sq = radius * radius

        def dist_sq(pos):
            try:
                dx = float(pos[0]) - cx
                dy = float(pos[1]) - cy
                dz = float(pos[2]) - cz
                return dx * dx + dy * dy + dz * dz
            except (TypeError, ValueError, IndexError):
                return None

        cell_size = float(scene_cache.get("cell_size") or 48.0)
        point_grid = scene_cache.get("point_grid") or {}
        min_cell = (
            int((cx - radius) // cell_size),
            int((cy - radius) // cell_size),
            int((cz - radius) // cell_size),
        )
        max_cell = (
            int((cx + radius) // cell_size),
            int((cy + radius) // cell_size),
            int((cz + radius) // cell_size),
        )
        candidate_points = []
        for ix in range(min_cell[0], max_cell[0] + 1):
            for iy in range(min_cell[1], max_cell[1] + 1):
                for iz in range(min_cell[2], max_cell[2] + 1):
                    candidate_points.extend(point_grid.get((ix, iy, iz), []))

        ranked_points = []
        for point in candidate_points:
            d2 = dist_sq(point)
            if d2 is not None and d2 <= radius_sq:
                ranked_points.append((d2, point))
        ranked_points.sort(key=lambda item: item[0])
        selected_points = [point for _, point in ranked_points[:limit]]

        def near_item(item):
            d2 = dist_sq(item.get("position"))
            if d2 is not None:
                return d2 <= radius_sq
            bounds = item.get("bounds") or {}
            bmin = bounds.get("min")
            bmax = bounds.get("max")
            if not bmin or not bmax:
                return False
            nearest = (
                min(max(cx, float(bmin[0])), float(bmax[0])),
                min(max(cy, float(bmin[1])), float(bmax[1])),
                min(max(cz, float(bmin[2])), float(bmax[2])),
            )
            return dist_sq(nearest) <= radius_sq

        zones = [zone for zone in data.get("zones", []) if near_item(zone)]
        props = [prop for prop in data.get("props", []) if near_item(prop)]
        metadata = dict(data.get("metadata") or {})
        metadata.update({
            "point_count": len(selected_points),
            "zone_count": len(zones),
            "prop_count": len(props),
            "total_point_count": len(data.get("points", [])),
        })

        response_data = {
            "scene": data.get("scene", scene),
            "version": data.get("version", 1),
            "bounds": data.get("bounds", {"min": [0, 0, 0], "max": [0, 0, 0]}),
            "points": selected_points,
            "zones": zones,
            "props": props,
            "metadata": metadata,
            "stream": {
                "geometry_version": scene_cache.get("geometry_version"),
                "center": [cx, cy, cz],
                "radius": radius,
                "limit": limit,
                "returned_points": len(selected_points),
                "total_points": len(data.get("points", [])),
                "candidate_points": len(candidate_points),
                "truncated": len(ranked_points) > limit,
            },
        }
        if len(stream_cache) > 256:
            stream_cache.pop(next(iter(stream_cache)), None)
        stream_cache[cache_key] = response_data
        return web.json_response(response_data)

    async def handle_hotzone_upload(self, request):
        guard = self._auth_guard(request, scope="ingest")
        if guard is not None:
            return guard

        player_id = request.headers.get("X-Player-ID")
        session_id = request.headers.get("X-Session-ID")
        trigger = request.headers.get("X-Trigger", "auto")
        if not player_id or not session_id:
            return web.json_response({"error": "missing_metadata_headers"}, status=400)

        # Basic security: sanitize IDs
        player_id = "".join(c for c in player_id if c.isalnum() or c in "-_")[:64]
        session_id = "".join(c for c in session_id if c.isalnum() or c in "-_")[:64]

        # Optional spatial context: lets the heatmap pin the hotzone on its cell.
        scene = request.headers.get("X-Scene")
        if scene:
            scene = "".join(c for c in scene if c.isalnum() or c in "-_./")[:128]

        def _parse_grid(header_name):
            raw = request.headers.get(header_name)
            if raw is None or raw == "":
                return None
            try:
                return float(raw)
            except (TypeError, ValueError):
                return None

        grid_x = _parse_grid("X-Grid-X")
        grid_z = _parse_grid("X-Grid-Z")

        # Optional: capture metadata from client headers
        def _parse_float_header(h):
            raw = request.headers.get(h)
            if raw is not None:
                try: return float(raw)
                except (TypeError, ValueError): pass
            return None

        def _parse_int_header(h):
            raw = request.headers.get(h)
            if raw is not None:
                try: return int(raw)
                except (TypeError, ValueError): pass
            return None

        capture_duration = _parse_float_header("X-Capture-Duration")
        capture_frames = _parse_int_header("X-Frame-Count")

        try:
            body = await request.read()
            if len(body) < 32:
                return web.json_response({"error": "payload_too_small"}, status=400)
            if len(body) > 10 * 1024 * 1024: # 10MB cap
                return web.json_response({"error": "payload_too_large"}, status=413)

            # Godot var2bytes format: [4 bytes length] [blob]
            # The blob for a dictionary starts with a type byte and then data.
            # We don't want to deeply parse Godot binary here to stay decoupled,
            # but we can look for the HZN2 magic if it was serialized as part of the dict.
            # In var2bytes(dict), the magic is just data.

            p_dir = os.path.join(HOTZONES_DIR, player_id)
            os.makedirs(p_dir, exist_ok=True)

            hotzone_id = str(uuid.uuid4())
            fpath = os.path.join(p_dir, f"{hotzone_id}.bin")
            file_size = len(body)

            with open(fpath, "wb") as f:
                f.write(body)

            # Record in SQLite
            def record():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT INTO hotzones (id, player_id, session_id, timestamp, file_path, trigger_type, scene, grid_x, grid_z, file_size, capture_duration, frame_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (hotzone_id, player_id, session_id, time.time(), fpath, trigger, scene, grid_x, grid_z, file_size, capture_duration, capture_frames))
                conn.commit()
                conn.close()

            await self._run_query(record)

            logger.info(f"Hotzone uploaded: {hotzone_id} for player {player_id}")

            # Notify dashboards (live event stream) + push subscribers that a new
            # hotzone ghost arrived, with a download link. Same shape as low_fps
            # alerts so the dashboard's notification handling treats it uniformly.
            try:
                tags = await self._run_query(self._fetch_player_tags)
                tag = tags.get(player_id) or {}
                player_label = tag.get("display_name") or player_id[:8]
                event = {
                    "type": "alert",
                    "alertType": "hotzone",
                    "playerId": player_id,
                    "player_id": player_id,
                    "sessionId": session_id,
                    "session_id": session_id,
                    "playerName": player_label,
                    "display_name": tag.get("display_name"),
                    "hotzoneId": hotzone_id,
                    "downloadUrl": f"/hotzones/{hotzone_id}/download",
                    "trigger": trigger,
                    "scene": scene,
                    "capture_duration": capture_duration,
                    "frame_count": capture_frames,
                    "message": f"{player_label}: nueva hotzone ({trigger})",
                    "timestamp": time.time(),
                }
                for sub in self.event_subscribers:
                    try:
                        await sub.send_json(event)
                    except Exception:
                        pass
                asyncio.create_task(self.send_push_to_all(event))
            except Exception as e:
                logger.warning(f"Hotzone notify failed (upload still recorded): {e}")

            return web.json_response({"ok": True, "id": hotzone_id}, status=201)

        except Exception as e:
            logger.error(f"Hotzone upload failed: {e}")
            return web.json_response({"error": str(e)}, status=500)

    async def handle_hotzones_list(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM hotzones ORDER BY timestamp DESC LIMIT 100")
                rows = [dict(row) for row in cursor.fetchall()]

                # Recover the scene for captures uploaded without an X-Scene
                # header: pick the heartbeat scene closest in time within the
                # same session. The scene IS known (the player was somewhere),
                # so we backfill it instead of leaving it "desconocida".
                for row in rows:
                    if row.get("scene"):
                        continue
                    sid = row.get("session_id")
                    ts = row.get("timestamp")
                    if not sid or ts is None:
                        continue
                    cursor.execute(
                        """
                        SELECT scene FROM heartbeats
                        WHERE session_id = ? AND scene IS NOT NULL AND scene != ''
                        ORDER BY ABS(timestamp - ?) ASC
                        LIMIT 1
                        """,
                        (sid, ts),
                    )
                    hit = cursor.fetchone()
                    if hit and hit["scene"]:
                        row["scene"] = hit["scene"]

                conn.close()
                return rows

            rows = await self._run_query(fetch)

            # Resolve player tags
            tags = await self._run_query(self._fetch_player_tags)
            for row in rows:
                pid = row.get("player_id", "")
                tag = tags.get(pid) or {}
                row["display_name"] = tag.get("display_name")
                row["color"] = tag.get("color")
                row["notes"] = tag.get("notes")
                # Add computed fields
                fs = row.get("file_size")
                if fs:
                    row["size_kb"] = round(fs / 1024.0, 1)
                dur = row.get("capture_duration")
                if dur:
                    row["duration_sec"] = round(dur, 1)

            return web.json_response(rows)
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500)

    async def handle_hotzone_dl_link(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        hz_id = request.match_info.get('id')
        expiry = int(time.time() + 300)  # 5 minutes
        payload = f"{hz_id}:{expiry}"
        token = hmac.new(BRIDGE_TOKEN.encode(), payload.encode(), hashlib.sha256).hexdigest()[:16]

        # Use the incoming request's host to build the absolute download URL.
        protocol = "https" if request.headers.get("X-Forwarded-Proto") == "https" else "http"
        host = request.host
        url = f"{protocol}://{host}/hotzones/{hz_id}/download?runbin_token={token}&expires={expiry}"

        return web.json_response({"url": url})

    async def handle_hotzone_download(self, request):
        token = request.query.get("runbin_token")
        expires = request.query.get("expires")
        hz_id = request.match_info.get('id')

        authorized = False
        if token and expires:
            try:
                if int(expires) > time.time():
                    payload = f"{hz_id}:{expires}"
                    expected = hmac.new(BRIDGE_TOKEN.encode(), payload.encode(), hashlib.sha256).hexdigest()[:16]
                    if hmac.compare_digest(token, expected):
                        authorized = True
            except (ValueError, TypeError):
                pass

        if not authorized:
            guard = self._auth_guard(request)
            if guard is not None:
                return guard

        try:
            def fetch():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT file_path FROM hotzones WHERE id = ?", (hz_id,))
                row = cursor.fetchone()
                conn.close()
                return row[0] if row else None

            fpath = await self._run_query(fetch)
            if fpath and os.path.exists(fpath):
                return web.FileResponse(fpath, headers={
                    "Content-Disposition": f'attachment; filename="hotzone_{hz_id}.bin"',
                    "Access-Control-Allow-Origin": "*",
                    "Cross-Origin-Resource-Policy": "cross-origin",
                })
            return web.Response(status=404, text="Hotzone not found", headers={
                "Access-Control-Allow-Origin": "*",
                "Cross-Origin-Resource-Policy": "cross-origin",
            })
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500, headers={"Access-Control-Allow-Origin": "*"})

    async def handle_hotzone_delete(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        hz_id = request.match_info.get('id')
        try:
            def delete():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute("SELECT file_path FROM hotzones WHERE id = ?", (hz_id,))
                row = cursor.fetchone()
                cursor.execute("DELETE FROM hotzones WHERE id = ?", (hz_id,))
                conn.commit()
                conn.close()
                return (row[0] if row else None), cursor.rowcount

            fpath, rowcount = await self._run_query(delete)
            if rowcount == 0:
                return web.json_response({"error": "not_found"}, status=404)
            # Remove the backing blob too; missing file is fine (already gone).
            if fpath and os.path.exists(fpath):
                try:
                    os.remove(fpath)
                except OSError as exc:
                    logger.warning(f"Hotzone {hz_id} row deleted but blob removal failed: {exc}")
            logger.info(f"Hotzone deleted: {hz_id}")
            return web.json_response({"ok": True, "id": hz_id})
        except Exception as e:
            return web.json_response({"error": str(e)}, status=500)

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

        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")

        query = """
        SELECT
            player_id,
            session_id,
            COALESCE(NULLIF(MAX(platform), ''), 'unknown') as platform,
            MIN(timestamp) as start_time,
            MAX(timestamp) as end_time,
            MAX(timestamp) - MIN(timestamp) as duration,
            GROUP_CONCAT(DISTINCT scene) as scenes_visited,
            -- FPS stats only over focused samples so a backgrounded stretch
            -- doesn't drag the session's avg_fps down or inflate low_fps_pct.
            AVG(CASE WHEN COALESCE(focused, 1) = 1 THEN fps END) as avg_fps,
            SUM(CASE WHEN COALESCE(focused, 1) = 1 AND fps < 30 THEN 1 ELSE 0 END) * 100.0
                / NULLIF(SUM(CASE WHEN COALESCE(focused, 1) = 1 THEN 1 ELSE 0 END), 0) as low_fps_pct,
            AVG(memory_mb) as avg_mem,
            COALESCE(NULLIF(MAX(game_version), ''), 'unknown') as game_version,
            COALESCE(NULLIF(MAX(git_commit), ''), '') as git_commit,
            COALESCE(NULLIF(MAX(build_channel), ''), '') as build_channel,
            MAX(COALESCE(official_build, 0)) as official_build,
            -- Prefer an official mode if ANY heartbeat in the session carried one.
            -- Plain MAX(intake_mode) is lexicographic ('telemetry' > 'ingest' > 'admin'),
            -- so one tokenless/early frame would mask an otherwise-official session and
            -- show it as "canary". Rank admin > ingest > telemetry explicitly instead.
            CASE
                WHEN MAX(CASE WHEN intake_mode = 'admin' THEN 1 ELSE 0 END) = 1 THEN 'admin'
                WHEN MAX(CASE WHEN intake_mode = 'ingest' THEN 1 ELSE 0 END) = 1 THEN 'ingest'
                ELSE 'telemetry'
            END as intake_mode
        FROM heartbeats
        WHERE {visible}
        GROUP BY player_id, session_id
        ORDER BY start_time DESC
        LIMIT 200
        """.format(visible=self._visibility_sql(include_server, include_tests))

        try:
            def fetch():
                conn = self._get_db()
                conn.row_factory = sqlite3.Row
                cursor = conn.cursor()
                cursor.execute(query)
                rows = [dict(row) for row in cursor.fetchall()]
                conn.close()
                return rows

            rows = await self._run_query(fetch)
            geo = await self._run_query(self._geo_by_player_id)
            for r in rows:
                loc = geo.get(r.get("player_id"))
                if loc:
                    r["city"] = loc.get("city")
                    r["country"] = loc.get("country")
                    r["country_code"] = loc.get("country_code")
            return web.json_response(rows)
        except Exception as e:
            logger.warning(f"{request.path}: query failed, returning [] ({e})")
            return web.json_response([])

    def _geo_by_player_id(self) -> dict:
        """Map player_id -> {city, country, country_code} from the geo DB so the
        session list can show where each player connected from. Best-effort: a
        missing geo DB or column just yields no location, never an error."""
        if not os.path.exists(GEO_SQLITE_DB):
            return {}
        conn = sqlite3.connect(GEO_SQLITE_DB)
        conn.row_factory = sqlite3.Row
        try:
            cursor = conn.cursor()
            # Most recent geo row per linked player wins.
            cursor.execute("""
                SELECT player_id, city, country, country_code
                FROM geo_ips
                WHERE COALESCE(player_id, '') != ''
                ORDER BY last_seen ASC
            """)
            out = {}
            for row in cursor.fetchall():
                out[row["player_id"]] = {
                    "city": row["city"] or None,
                    "country": row["country"] or None,
                    "country_code": row["country_code"] or None,
                }
            return out
        except sqlite3.OperationalError:
            return {}
        finally:
            conn.close()

    async def handle_milestones(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        all_milestones = []
        for mid, title, icon in MILESTONES:
            all_milestones.append({
                "id": mid,
                "title": title,
                "icon": icon,
                "achieved": mid in self.milestone_checker.achieved_ids
            })
        return web.json_response(all_milestones)

    async def handle_milestones_achieved(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        def fetch():
            conn = self._get_db()
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM milestones ORDER BY achieved_at DESC")
            rows = [dict(row) for row in cursor.fetchall()]
            conn.close()
            return rows

        achieved = await self._run_query(fetch)
        return web.json_response(achieved)

    async def handle_geo_players(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        if not os.path.exists(GEO_SQLITE_DB):
            return web.json_response([])

        now = time.time()

        def fetch():
            conn = sqlite3.connect(GEO_SQLITE_DB)
            conn.row_factory = sqlite3.Row
            try:
                cursor = conn.cursor()
                # Confirmed player-linked rows written by the live WS path.
                cursor.execute("""
                    SELECT ip_hash, player_id, country, country_code, region, city,
                           latitude, longitude, last_seen, hits, source
                    FROM geo_ips
                    WHERE latitude IS NOT NULL
                      AND longitude IS NOT NULL
                      AND player_id IS NOT NULL
                      AND player_id != ''
                    ORDER BY last_seen DESC
                    LIMIT 500
                """)
                players = [dict(row) for row in cursor.fetchall()]

                # Historical telemetry-only rows. Do not use geo_locations here:
                # that aggregate can include plain website hits. The globe must
                # represent game telemetry, so require ws/telemetry counters.
                cursor.execute("""
                    SELECT ip_hash, player_id, country, country_code, region, city,
                           latitude, longitude, last_seen, hits,
                           ws_hits, telemetry_hits
                    FROM geo_ips
                    WHERE latitude IS NOT NULL
                      AND longitude IS NOT NULL
                      AND COALESCE(player_id, '') = ''
                      AND (
                        COALESCE(ws_hits, 0) > 0
                        OR COALESCE(telemetry_hits, 0) > 0
                      )
                    ORDER BY last_seen DESC
                    LIMIT 500
                """)
                historical = [dict(row) for row in cursor.fetchall()]
                return players, historical
            finally:
                conn.close()

        try:
            await self._run_query(self._unlink_weak_historical_geo_rows)
            await self._run_query(self._link_unassigned_geo_rows)
            rows, historical_rows = await self._run_query(fetch)
        except Exception as e:
            logger.warning(f"{request.path}: geo query failed, returning [] ({e})")
            return web.json_response([])

        tags = await self._run_query(self._fetch_player_tags)

        players = []
        for row in rows:
            age = now - float(row.get("last_seen") or 0)
            status = "connected" if age <= 120 else ("recent" if age <= 3600 else "old")
            tag = (tags.get(row.get("player_id")) or {}) if row.get("source") == "live_ws" else {}
            players.append({
                "player_id": row.get("player_id") or f"geo:{row['ip_hash']}",
                "session_id": "live_ws",
                "last_seen": row.get("last_seen"),
                "country": row.get("country") or "Unknown",
                "country_code": row.get("country_code") or "",
                "region": row.get("region") or "",
                "city": row.get("city") or "Unknown",
                "latitude": row.get("latitude"),
                "longitude": row.get("longitude"),
                "display_name": tag.get("display_name"),
                "color": tag.get("color"),
                "status": status,
                "hits": row.get("hits") or 0,
            })
        seen_locations = {
            (
                round(float(p.get("latitude") or 0), 2),
                round(float(p.get("longitude") or 0), 2),
            )
            for p in players
        }
        for row in historical_rows:
            lat = row.get("latitude")
            lng = row.get("longitude")
            key = (round(float(lat or 0), 2), round(float(lng or 0), 2))
            if key in seen_locations:
                continue
            age = now - float(row.get("last_seen") or 0)
            status = "recent" if age <= 3600 else "old"
            city = row.get("city") or "Unknown"
            country = row.get("country") or "Unknown"
            players.append({
                "player_id": "geo:%s:%s" % (city, country),
                "session_id": "historical_geo",
                "last_seen": row.get("last_seen"),
                "country": country,
                "country_code": row.get("country_code") or "",
                "region": row.get("region") or "",
                "city": city,
                "latitude": lat,
                "longitude": lng,
                "display_name": None,
                "color": None,
                "status": status,
                "hits": row.get("telemetry_hits") or row.get("ws_hits") or row.get("hits") or 0,
                "historical": True,
                "player_count": 0,
            })
        return web.json_response(players)

    # --- Player tags ---
    def _fetch_player_tags(self) -> dict:
        """Return {player_id: {display_name, notes, color}}. Self-creates the
        table so reads never fail on a fresh DB."""
        conn = self._get_db()
        conn.row_factory = sqlite3.Row
        try:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS player_tags (
                    player_id TEXT PRIMARY KEY,
                    display_name TEXT, notes TEXT, color TEXT, updated_at REAL
                );
            """)
            cur.execute("SELECT player_id, display_name, notes, color FROM player_tags")
            return {r["player_id"]: dict(r) for r in cur.fetchall()}
        finally:
            conn.close()

    def _fetch_geo_by_player_ids(self, player_ids: list) -> dict:
        ids = sorted({str(pid) for pid in player_ids if pid})
        if not ids or not os.path.exists(GEO_SQLITE_DB):
            return {}
        conn = sqlite3.connect(GEO_SQLITE_DB)
        conn.row_factory = sqlite3.Row
        try:
            self._ensure_geo_schema(conn)
            result = {}
            for index in range(0, len(ids), 200):
                chunk = ids[index:index + 200]
                placeholders = ",".join("?" for _ in chunk)
                rows = conn.execute(
                    f"""
                    SELECT player_id, country, country_code, region, city,
                           latitude, longitude, last_seen
                    FROM geo_ips
                    WHERE player_id IN ({placeholders})
                      AND latitude IS NOT NULL
                      AND longitude IS NOT NULL
                    ORDER BY last_seen DESC
                    """,
                    chunk,
                ).fetchall()
                for row in rows:
                    pid = row["player_id"]
                    if pid not in result:
                        result[pid] = dict(row)
            return result
        finally:
            conn.close()

    @staticmethod
    def _is_useful_session_scene(scene: str) -> bool:
        normalized = (scene or "").strip().lower()
        return bool(normalized) and normalized not in {
            "?",
            "unknown",
            "desconocida",
            "desconocido",
            "undefined",
            "null",
            "boot",
        }

    def _geo_session_candidates(self, first_seen: float, last_seen: float) -> list:
        conn = self._get_db()
        conn.row_factory = sqlite3.Row
        try:
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT player_id, session_id, platform,
                       MIN(timestamp) AS start_time,
                       MAX(timestamp) AS end_time,
                       MAX(timestamp) - MIN(timestamp) AS duration,
                       AVG(fps) AS avg_fps,
                       GROUP_CONCAT(DISTINCT scene) AS scenes_visited,
                       COUNT(*) AS samples
                FROM heartbeats
                WHERE timestamp BETWEEN ? AND ?
                  AND player_id IS NOT NULL
                  AND player_id != ''
                  AND session_id IS NOT NULL
                  AND session_id != ''
                  AND LOWER(COALESCE(platform, '')) != 'server'
                GROUP BY player_id, session_id, platform
                HAVING duration >= ? AND samples >= 10
                """,
                (float(first_seen) - 120.0, float(last_seen) + 120.0, WARMUP_SECONDS),
            )
            candidates = []
            for row in cursor.fetchall():
                scenes = [s.strip() for s in (row["scenes_visited"] or "").split(",")]
                if not any(self._is_useful_session_scene(scene) for scene in scenes):
                    continue
                candidates.append(dict(row))
            return candidates
        finally:
            conn.close()

    def _pick_geo_session_candidate(self, first_seen: float, candidates: list) -> Optional[str]:
        if not candidates:
            return None
        timestamp_prefix = str(int(first_seen))
        prefix_matches = [
            row for row in candidates
            if str(row.get("player_id") or "").startswith(timestamp_prefix)
            or str(row.get("session_id") or "").startswith(timestamp_prefix)
        ]
        if len({row["player_id"] for row in prefix_matches}) == 1:
            return prefix_matches[0]["player_id"]
        return None

    def _unlink_weak_historical_geo_rows(self) -> int:
        """Undo historical access-log links that were only time-window guesses.
        Strong links are those whose player_id/session_id embeds the geo first_seen
        timestamp prefix; anything else should stay unassigned and untagged."""
        if not os.path.exists(GEO_SQLITE_DB):
            return 0
        conn = sqlite3.connect(GEO_SQLITE_DB)
        conn.row_factory = sqlite3.Row
        try:
            self._ensure_geo_schema(conn)
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT ip_hash, player_id, first_seen
                FROM geo_ips
                WHERE COALESCE(player_id, '') != ''
                  AND COALESCE(source, '') != 'live_ws'
                  AND first_seen IS NOT NULL
                """
            )
            rows = cursor.fetchall()
            unlinked = 0
            for row in rows:
                prefix = str(int(float(row["first_seen"] or 0)))
                player_id = str(row["player_id"] or "")
                if player_id.startswith(prefix):
                    continue
                if self._player_has_session_prefix(player_id, prefix):
                    continue
                cursor.execute("UPDATE geo_ips SET player_id = NULL WHERE ip_hash = ?", (row["ip_hash"],))
                unlinked += cursor.rowcount
            if unlinked:
                conn.commit()
                logger.info("Unlinked %s weak historical geo rows", unlinked)
            return unlinked
        finally:
            conn.close()

    def _player_has_session_prefix(self, player_id: str, prefix: str) -> bool:
        if not player_id or not prefix:
            return False
        conn = self._get_db()
        try:
            row = conn.execute(
                "SELECT 1 FROM heartbeats WHERE player_id = ? AND session_id LIKE ? LIMIT 1",
                (player_id, prefix + "%"),
            ).fetchone()
            return row is not None
        finally:
            conn.close()

    def _link_unassigned_geo_rows(self) -> int:
        """Backfill geo rows imported from access logs with the most likely
        telemetry player. Conservative by design: ambiguous rows stay unlinked."""
        if not os.path.exists(GEO_SQLITE_DB):
            return 0
        conn = sqlite3.connect(GEO_SQLITE_DB)
        conn.row_factory = sqlite3.Row
        try:
            self._ensure_geo_schema(conn)
            cursor = conn.cursor()
            cursor.execute(
                """
                SELECT ip_hash, first_seen, last_seen
                FROM geo_ips
                WHERE latitude IS NOT NULL
                  AND longitude IS NOT NULL
                  AND COALESCE(player_id, '') = ''
                  AND (
                    COALESCE(telemetry_hits, 0) > 0
                    OR COALESCE(ws_hits, 0) > 0
                  )
                  AND first_seen IS NOT NULL
                  AND last_seen IS NOT NULL
                ORDER BY last_seen DESC
                LIMIT 200
                """
            )
            rows = cursor.fetchall()
            linked = 0
            for row in rows:
                first_seen = float(row["first_seen"] or 0)
                last_seen = float(row["last_seen"] or first_seen)
                candidate = self._pick_geo_session_candidate(
                    first_seen,
                    self._geo_session_candidates(first_seen, last_seen),
                )
                if not candidate:
                    continue
                cursor.execute(
                    "UPDATE geo_ips SET player_id = ? WHERE ip_hash = ? AND COALESCE(player_id, '') = ''",
                    (candidate, row["ip_hash"]),
                )
                linked += cursor.rowcount
            if linked:
                conn.commit()
                logger.info("Linked %s historical geo rows to telemetry players", linked)
            return linked
        finally:
            conn.close()

    async def handle_player_tags_list(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        try:
            tags = await self._run_query(self._fetch_player_tags)
        except Exception as e:
            logger.warning(f"{request.path}: tag query failed ({e})")
            return web.json_response([])
        return web.json_response(list(tags.values()))

    async def handle_player_tag_upsert(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        try:
            data = await request.json()
        except Exception:
            return web.json_response({"error": "bad_json"}, status=400)

        player_id = str(data.get("player_id") or "").strip()
        display_name = str(data.get("display_name") or "").strip()
        if not player_id or not display_name:
            return web.json_response({"error": "player_id and display_name required"}, status=400)
        notes = str(data.get("notes") or "")[:1000]
        color = str(data.get("color") or "")[:32]

        def write():
            conn = self._get_db()
            try:
                cur = conn.cursor()
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS player_tags (
                        player_id TEXT PRIMARY KEY,
                        display_name TEXT, notes TEXT, color TEXT, updated_at REAL
                    );
                """)
                cur.execute(
                    """INSERT OR REPLACE INTO player_tags
                         (player_id, display_name, notes, color, updated_at)
                       VALUES (?, ?, ?, ?, ?)""",
                    (player_id, display_name, notes, color, time.time()),
                )
                conn.commit()
            finally:
                conn.close()

        try:
            await self._run_query(write)
        except Exception as e:
            logger.warning(f"{request.path}: tag upsert failed ({e})")
            return web.json_response({"error": "write_failed"}, status=500)
        return web.json_response({
            "player_id": player_id, "display_name": display_name,
            "notes": notes, "color": color,
        })

    async def handle_player_tag_delete(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard
        player_id = request.match_info.get("player_id", "")
        if not player_id:
            return web.json_response({"error": "player_id required"}, status=400)

        def write():
            conn = self._get_db()
            try:
                cur = conn.cursor()
                cur.execute("DELETE FROM player_tags WHERE player_id = ?", (player_id,))
                conn.commit()
            finally:
                conn.close()

        try:
            await self._run_query(write)
        except Exception as e:
            logger.warning(f"{request.path}: tag delete failed ({e})")
            return web.json_response({"error": "write_failed"}, status=500)
        return web.json_response({"ok": True, "player_id": player_id})

    async def handle_ghosts_active(self, request):
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        tags = await self._run_query(self._fetch_player_tags)
        now = time.time()
        active = []
        for pid, hb in self.heartbeats.items():
            if not self._is_visible_telemetry(hb, include_server, include_tests):
                continue
            last_seen = self.last_update.get(pid, 0)
            if now - last_seen < 30:
                p_data = hb.get("player", {})
                pos = p_data.get("position", [0, 0, 0])
                tag = tags.get(pid) or {}
                active.append({
                    "player_id": pid,
                    "session_id": hb.get("session_id"),
                    "scene": p_data.get("scene"),
                    "pos_x": pos[0],
                    "pos_y": pos[1],
                    "pos_z": pos[2],
                    "fps": p_data.get("fps"),
                    "last_seen": last_seen,
                    "display_name": tag.get("display_name"),
                    "color": tag.get("color"),
                })
        return web.json_response(active)

    async def handle_ghosts_stats(self, request):
        """Aggregate Ghost stats per scene + headline metrics."""
        guard = self._auth_guard(request)
        if guard is not None:
            return guard

        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        visible_sql = self._visibility_sql(include_server, include_tests)

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
                WHERE {visible_sql} AND {_PAST_WARMUP}
                GROUP BY scene
                """
                cursor.execute(query_scenes)
                scene_stats = [dict(row) for row in cursor.fetchall()]

                # Headline stats for dashboard compatibility
                now = time.time()
                day, week, month = 86400, 604800, 2592000

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats WHERE {visible_sql}"
                )
                unique_total = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {visible_sql} AND timestamp >= ?",
                    (now - day,),
                )
                unique_day = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {visible_sql} AND timestamp >= ?",
                    (now - week,),
                )
                unique_week = cursor.fetchone()["n"] or 0

                cursor.execute(
                    f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {visible_sql} AND timestamp >= ?",
                    (now - month,),
                )
                unique_month = cursor.fetchone()["n"] or 0

                # Previous-window counts (the equally-sized window just before the
                # current one) so the dashboard can show a delta/trend per card.
                def unique_between(start, end):
                    cursor.execute(
                        f"SELECT COUNT(DISTINCT player_id) AS n FROM heartbeats "
                        f"WHERE {visible_sql} AND timestamp >= ? AND timestamp < ?",
                        (start, end),
                    )
                    return cursor.fetchone()["n"] or 0

                prev_day = unique_between(now - 2 * day, now - day)
                prev_week = unique_between(now - 2 * week, now - week)
                prev_month = unique_between(now - 2 * month, now - month)

                # Daily unique-player series for the last 30 days, for sparklines.
                # Bucketed by UTC day; gaps are filled with 0 below so the chart
                # has one point per day regardless of activity.
                cursor.execute(
                    f"SELECT CAST((timestamp) / ? AS INTEGER) AS day_idx, "
                    f"COUNT(DISTINCT player_id) AS n FROM heartbeats "
                    f"WHERE {visible_sql} AND timestamp >= ? GROUP BY day_idx",
                    (day, now - month),
                )
                by_day = {int(r["day_idx"]): (r["n"] or 0) for r in cursor.fetchall()}
                first_idx = int((now - month) / day)
                last_idx = int(now / day)
                daily_players = [by_day.get(i, 0) for i in range(first_idx, last_idx + 1)]

                cursor.execute(
                    f"SELECT MIN(timestamp) AS start, MAX(timestamp) AS end "
                    f"FROM heartbeats WHERE {visible_sql} "
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
                        # Previous equally-sized window, for trend/delta display.
                        "players_prev_day": prev_day,
                        "players_prev_week": prev_week,
                        "players_prev_month": prev_month,
                        # Daily unique players over the last 30d (sparkline).
                        "players_daily": daily_players,
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
        include_server = self._include_flag(request, "include_server")
        include_tests = self._include_flag(request, "include_tests")
        visible_sql = self._visibility_sql(include_server, include_tests)
        try:
            def fetch():
                conn = self._get_db()
                cursor = conn.cursor()
                cursor.execute(
                    f"SELECT DISTINCT scene FROM heartbeats WHERE scene IS NOT NULL AND scene != '' AND {visible_sql}"
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
                            # BRIDGE_TOKEN es admin; ODISEA_CENTRAL_INGEST_TOKEN solo identifica ingest.
                            mode = self._token_mode(token)
                            
                            authenticated = True
                            peer_id = data.get("peer_id")
                            if not peer_id or peer_id == "unknown":
                                peer_id = "anon_" + str(uuid.uuid4())[:8]
                            
                            self.active_peers[ws] = peer_id
                            self.peer_ws[peer_id] = ws
                            
                            logger.info(f"Peer conectado ({mode}): {peer_id}")
                            await ws.send_json({"type": "handshake_ack", "status": "ok", "mode": mode,
                                                "compression": "deflate"})
                        else:
                            logger.warning("Peer sent message before handshake.")
                            await ws.close(code=WSCloseCode.POLICY_VIOLATION)
                            break

                    elif msg_type == "heartbeat":
                        await self._process_heartbeat(
                            data,
                            inferred_platform=inferred_platform,
                            client_ip=self._client_ip(request),
                            intake_mode=self._token_mode(data.get("token")) if data.get("token") else mode,
                        )

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
                
                if pid:
                    tags = await self._run_query(self._fetch_player_tags)
                    tag = tags.get(pid) or {}
                    label = tag.get("display_name") or pid[:8]
                    asyncio.create_task(self.send_push_to_all({
                        "type": "disconnect",
                        "playerId": pid,
                        "playerName": label,
                        "display_name": tag.get("display_name"),
                        "message": f"{label} disconnected"
                    }))
            logger.info(f"Peer disconnected: {peer_id}")

        return ws

    async def _process_heartbeat(self, data: dict, inferred_platform: str = "", client_ip: str = "", intake_mode: str = "telemetry"):
        player_id = data.get("player_id")
        session_id = data.get("session_id")

        if not player_id or not session_id:
            return

        data["intake_mode"] = intake_mode if intake_mode in ("admin", "ingest", "telemetry") else "telemetry"
        tag = {}
        player_label = player_id[:8]

        now = time.time()
        last_time = self.session_rate_limit.get(session_id, 0)
        if now - last_time < 0.05:
            return

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
        is_test_telemetry = self._is_test_telemetry(data)
        # An unfocused (backgrounded) game throttles itself and legitimately drops
        # FPS — don't raise low-FPS alerts for it. `focused` defaults to True so
        # older clients that don't send the flag behave exactly as before.
        is_unfocused = p_data.get("focused", True) is False

        if platform == "server" or is_test_telemetry or is_unfocused:
            self.low_fps_timers.pop(player_id, None)
            self.low_fps_sessions.pop(session_id, None)
        elif fps < 15:
            # Player-based alert
            if player_id not in self.low_fps_timers:
                self.low_fps_timers[player_id] = now
            elif now - self.low_fps_timers[player_id] > 5:
                # Throttle alerts: max 1 per 60s
                if now - self.last_alert_time.get(player_id, 0) > 60:
                    self.last_alert_time[player_id] = now
                    tags = await self._run_query(self._fetch_player_tags)
                    tag = tags.get(player_id) or {}
                    player_label = tag.get("display_name") or player_id[:8]
                    alert = {
                        "type": "alert",
                        "alertType": "low_fps",
                        "playerId": player_id,
                        "player_id": player_id,
                        "playerName": player_label,
                        "display_name": tag.get("display_name"),
                        "platform": platform,
                        "message": f"{player_label}: low FPS detected ({fps} FPS)",
                        "fps": fps,
                        "timestamp": now
                    }
                    for sub in self.event_subscribers:
                        try:
                            await sub.send_json(alert)
                        except Exception: pass
                    asyncio.create_task(self.send_push_to_all(alert))
                    self.milestone_checker.record_low_fps()

            # Session-based alert (Prompt 9)
            if session_id not in self.low_fps_sessions:
                self.low_fps_sessions[session_id] = now
            elif now - self.low_fps_sessions[session_id] > 5:
                # Persistent low FPS alert
                alert = {
                    "type": "alert",
                    "alertType": "low_fps",
                    "playerId": player_id,
                    "player_id": player_id,
                    "playerName": player_label,
                    "display_name": tag.get("display_name"),
                    "session_id": session_id,
                    "platform": platform,
                    "message": f"{player_label}: low FPS detected (>5s)",
                    "fps": fps,
                    "timestamp": now
                }
                for sub in self.event_subscribers:
                    try:
                        asyncio.create_task(sub.send_json(alert))
                    except Exception: pass
                asyncio.create_task(self.send_push_to_all(alert))
                self.milestone_checker.record_low_fps()
        else:
            self.low_fps_timers.pop(player_id, None)
            self.low_fps_sessions.pop(session_id, None)

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
        self.last_known_hb[player_id] = data.copy()
        self.metrics.record_heartbeat(session_id)
        
        # Milestone Detector
        self.milestone_checker.record_heartbeat(data)
        await self.milestone_checker.check_and_notify()

        if self.metrics.heartbeats_total % 100 == 0:
            logger.info(f"Heartbeat 100x: {player_id}")

        if STORE_GHOSTS:
            self._store_ghost(player_id, session_id, data)

        if self._is_visible_telemetry(data):
            # Record this IP as a confirmed real player (web or native) for the
            # geo map. Gated by _is_visible_telemetry so server peers, tests and
            # warmup never count. Throttled to once per session to spare the DB;
            # record_geo_player still refreshes last_seen via the batch view.
            if client_ip and session_id not in self.geo_recorded_sessions:
                self.geo_recorded_sessions.add(session_id)
                self.record_geo_player(client_ip, player_id)

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
            CREATE TABLE IF NOT EXISTS hotzones (
                id TEXT PRIMARY KEY,
                player_id TEXT,
                session_id TEXT,
                timestamp REAL,
                file_path TEXT,
                trigger_type TEXT DEFAULT 'auto'
            );
        """)
        # scene + grid coords let the heatmap pin hotzones in-situ on their cell.
        # Older rows predate these columns; migrate in place (NULL = unknown).
        for column, coltype in (
            ("scene", "TEXT"),
            ("grid_x", "REAL"),  # world X of the capture (resolution-agnostic)
            ("grid_z", "REAL"),  # world Z of the capture
            ("file_size", "INTEGER"),
            ("capture_duration", "REAL"),
            ("frame_count", "INTEGER"),
        ):
            try:
                cursor.execute(f"ALTER TABLE hotzones ADD COLUMN {column} {coltype};")
            except sqlite3.OperationalError as exc:
                if "duplicate column name" not in str(exc).lower():
                    raise
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
                game_version TEXT,
                git_commit TEXT,
                build_id TEXT,
                build_channel TEXT,
                official_host TEXT,
                official_build INTEGER,
                intake_mode TEXT,
                peer_id TEXT,
                focused INTEGER DEFAULT 1,
                draw_calls REAL,
                objects REAL,
                vertices REAL,
                nodes REAL,
                UNIQUE(player_id, session_id, timestamp)
            );
        """)
        for column, coltype in (
            ("game_version", "TEXT"),
            ("git_commit", "TEXT"),
            ("build_id", "TEXT"),
            ("build_channel", "TEXT"),
            ("official_host", "TEXT"),
            ("official_build", "INTEGER"),
            ("intake_mode", "TEXT"),
            ("focused", "INTEGER DEFAULT 1"),
            ("draw_calls", "REAL"),
            ("objects", "REAL"),
            ("vertices", "REAL"),
            ("nodes", "REAL"),
        ):
            try:
                cursor.execute(f"ALTER TABLE heartbeats ADD COLUMN {column} {coltype};")
            except sqlite3.OperationalError as exc:
                if "duplicate column name" not in str(exc).lower():
                    raise
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_scene ON heartbeats(scene);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_timestamp ON heartbeats(timestamp);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_platform ON heartbeats(platform);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_session ON heartbeats(session_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_combined ON heartbeats(player_id, scene, timestamp);")
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS player_tags (
                player_id TEXT PRIMARY KEY,
                display_name TEXT,
                notes TEXT,
                color TEXT,
                updated_at REAL
            );
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS milestones (
                milestone_id TEXT PRIMARY KEY,
                title TEXT,
                icon TEXT,
                achieved_at REAL,
                value REAL
            );
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS push_subscriptions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                subscription_json TEXT UNIQUE,
                player_id TEXT,
                settings_json TEXT,
                updated_at REAL
            );
        """)
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
                    perf = player_data.get("perf") or {}
                    if not isinstance(perf, dict):
                        perf = {}

                    cursor.execute("""
                        INSERT OR IGNORE INTO heartbeats (
                            player_id, session_id, timestamp, scene, platform,
                            fps, memory_mb, pos_x, pos_y, pos_z,
                            engine_version, game_version, git_commit, build_id,
                            build_channel, official_host, official_build,
                            intake_mode, peer_id, focused,
                            draw_calls, objects, vertices, nodes
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        data.get("game_version"),
                        data.get("git_commit"),
                        data.get("build_id"),
                        data.get("build_channel"),
                        data.get("official_host"),
                        1 if data.get("official_build") else 0,
                        data.get("intake_mode", "telemetry"),
                        data.get("peer_id"),
                        0 if player_data.get("focused", True) is False else 1,
                        perf.get("dc"),
                        perf.get("obj"),
                        perf.get("vtx"),
                        perf.get("nodes"),
                    ))

                conn.commit()
                for _ in batch:
                    self.db_queue.task_done()
            except Exception as e:
                logger.error(f"DB worker error: {e}")
                await asyncio.sleep(1)

    def _latest_published_build(self) -> dict:
        """Latest heartbeat carrying official build metadata for dashboard display."""
        try:
            conn = self._get_db()
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()
            cursor.execute("""
                SELECT game_version, git_commit, build_id, build_channel,
                       official_host, timestamp
                FROM heartbeats
                WHERE COALESCE(official_build, 0) = 1
                   OR COALESCE(build_channel, '') IN ('nightly', 'tip', 'release')
                   OR COALESCE(official_host, '') != ''
                ORDER BY
                    CASE
                        WHEN COALESCE(git_commit, '') != '' THEN 0
                        WHEN COALESCE(build_id, '') != '' THEN 1
                        ELSE 2
                    END,
                    timestamp DESC
                LIMIT 1
            """)
            row = cursor.fetchone()
            conn.close()
            return dict(row) if row else {}
        except Exception:
            return {}

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

    # Headers necesarios para SharedArrayBuffer en builds HTML5.
    _COOP_COEP_HEADERS = {
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Embedder-Policy": "credentialless",
        "Access-Control-Allow-Origin": "*",
    }

    @staticmethod
    def _add_coop_coep_headers(response: web.StreamResponse) -> None:
        for k, v in OdiseaCentral._COOP_COEP_HEADERS.items():
            response.headers[k] = v

    async def handle_index(self, request):
        index_path = os.path.join(STATIC_DIR, "index.html")
        if os.path.exists(index_path):
            resp = web.FileResponse(index_path)
            self._add_coop_coep_headers(resp)
            return resp
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
        # Los headers COOP/COEP son obligatorios para SharedArrayBuffer en HTML5.
        headers.update(self._COOP_COEP_HEADERS)
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

    # --- Geo helpers ---
    @staticmethod
    def _geo_ip_hash(ip: str) -> str:
        return hashlib.sha256((GEO_HASH_SALT + ":" + ip).encode()).hexdigest()[:16]

    def _ensure_geo_schema(self, conn):
        """Create the geo tables if missing. Shared shape with
        scripts/import_nginx_geo.py so live rows and backfilled rows coexist."""
        cur = conn.cursor()
        cur.execute(
            """CREATE TABLE IF NOT EXISTS geo_ips (
                ip_hash TEXT PRIMARY KEY,
                country TEXT, country_code TEXT, region TEXT, city TEXT,
                latitude REAL, longitude REAL,
                first_seen REAL, last_seen REAL,
                hits INTEGER, candidate_hits INTEGER,
                ws_hits INTEGER, telemetry_hits INTEGER,
                api_hits INTEGER, site_hits INTEGER, scanner_hits INTEGER,
                tagged_at REAL, source TEXT
            )"""
        )
        # player_id links a confirmed real player to the hashed IP. Older DBs
        # created by the import script may lack it; add it idempotently.
        for column, coltype in (("player_id", "TEXT"),):
            try:
                cur.execute(f"ALTER TABLE geo_ips ADD COLUMN {column} {coltype}")
            except sqlite3.OperationalError as exc:
                if "duplicate column name" not in str(exc).lower():
                    raise
        conn.commit()

    def record_geo_player(self, ip: str, player_id: str):
        """Record (hashed) that a real player connected from this IP, and queue
        the raw IP for deferred geolocation. The raw IP is held only in memory
        (self.geo_pending_lookup) until the batch task resolves lat/lng; only the
        hash is persisted. Only called for telemetry passing _is_visible_telemetry."""
        if not ip or ip == "unknown" or not player_id:
            return
        ip_hash = self._geo_ip_hash(ip)
        # Queue raw IP for the batch geolocator (in-memory only, never on disk).
        self.geo_pending_lookup[ip_hash] = ip

        def write():
            now = time.time()
            conn = sqlite3.connect(GEO_SQLITE_DB)
            try:
                self._ensure_geo_schema(conn)
                cur = conn.cursor()
                cur.execute(
                    """INSERT INTO geo_ips
                         (ip_hash, player_id, first_seen, last_seen,
                          hits, ws_hits, telemetry_hits, source)
                       VALUES (?, ?, ?, ?, 1, 1, 1, 'live_ws')
                       ON CONFLICT(ip_hash) DO UPDATE SET
                          player_id = excluded.player_id,
                          last_seen = excluded.last_seen,
                          hits = COALESCE(geo_ips.hits, 0) + 1,
                          ws_hits = COALESCE(geo_ips.ws_hits, 0) + 1,
                          source = 'live_ws'""",
                    (ip_hash, player_id, now, now),
                )
                conn.commit()
            finally:
                conn.close()

        try:
            return asyncio.get_running_loop().run_in_executor(None, write)
        except RuntimeError:
            write()

    async def _geo_lookup_task(self):
        """Resolve queued raw IPs to lat/lng via ip-api.com and write the geo
        fields back keyed by hash. Runs out-of-band so the WS path stays fast."""
        await asyncio.sleep(15)  # let the server settle before first run
        while True:
            try:
                pending = dict(self.geo_pending_lookup)
                if pending:
                    resolved = await self._run_query(self._geo_batch_lookup, list(pending.values()))
                    if resolved:
                        await self._run_query(self._geo_write_locations, pending, resolved)
                    for h in pending:
                        self.geo_pending_lookup.pop(h, None)
            except Exception as e:
                logger.warning(f"geo lookup task error: {e}")
            await asyncio.sleep(60)

    @staticmethod
    def _geo_batch_lookup(ips: list) -> dict:
        """Batch geolocate raw IPs. Mirrors scripts/import_nginx_geo.py.geo_lookup."""
        import urllib.request
        result = {}
        fields = "status,country,countryCode,regionName,city,lat,lon,query"
        for index in range(0, len(ips), 100):
            batch = ips[index:index + 100]
            body = json.dumps([{"query": ip, "fields": fields} for ip in batch]).encode()
            req = urllib.request.Request(
                "http://ip-api.com/batch", data=body,
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=20) as response:
                data = json.loads(response.read().decode())
            for row in data:
                if row.get("status") == "success":
                    result[row["query"]] = row
            time.sleep(1.2)  # ip-api free tier rate limit
        return result

    def _geo_write_locations(self, hash_to_ip: dict, resolved: dict):
        conn = sqlite3.connect(GEO_SQLITE_DB)
        try:
            self._ensure_geo_schema(conn)
            cur = conn.cursor()
            now = time.time()
            for ip_hash, ip in hash_to_ip.items():
                info = resolved.get(ip)
                if not info:
                    continue
                cur.execute(
                    """UPDATE geo_ips SET
                         country=?, country_code=?, region=?, city=?,
                         latitude=?, longitude=?, tagged_at=?
                       WHERE ip_hash=?""",
                    (
                        info.get("country"), info.get("countryCode"),
                        info.get("regionName"), info.get("city"),
                        info.get("lat"), info.get("lon"), now, ip_hash,
                    ),
                )
            conn.commit()
        finally:
            conn.close()

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

    async def _on_prepare(self, request: web.Request, response: web.StreamResponse) -> None:
        # Inyecta headers COOP/COEP a todas las respuestas del dashboard,
        # cubriendo assets/ y cualquier otra ruta estática que no pase por
        # los handlers explícitos.
        self._add_coop_coep_headers(response)

    async def run(self):
        app = web.Application(client_max_size=16 * 1024 * 1024)
        app.on_response_prepare.append(self._on_prepare)
        app.add_routes([
            web.get('/', self.handle_index),
            web.get('/index.html', self.handle_index),
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
            web.post('/hotzone', self.handle_hotzone_upload),
            web.get('/hotzones', self.handle_hotzones_list),
            web.get('/hotzones/{id}/dl-link', self.handle_hotzone_dl_link),
            web.get('/hotzones/{id}/download', self.handle_hotzone_download),
            web.delete('/hotzones/{id}', self.handle_hotzone_delete),
            web.post('/command', self.handle_command),
            web.get('/health', self.handle_health),
            web.get('/api/milestones', self.handle_milestones),
            web.get('/api/milestones/achieved', self.handle_milestones_achieved),
            web.get('/api/scene-data/{scene}', self.handle_scene_geometry_stream),
            web.get('/api/geo-players', self.handle_geo_players),
            web.get('/api/player-tags', self.handle_player_tags_list),
            web.post('/api/player-tags', self.handle_player_tag_upsert),
            web.delete('/api/player-tags/{player_id}', self.handle_player_tag_delete),
            web.get('/game/version', self.handle_game_version),
            web.get('/game/updates/v1/manifest', self.handle_update_manifest),
            web.post('/telemetry', self.handle_web_telemetry),
            web.get('/telemetry/web', self.handle_web_telemetry_list),
            web.options('/telemetry', self.handle_web_telemetry_options),

            # PWA Push Notifications
            web.get('/push/key', self.handle_vapid_public_key),
            web.post('/push/subscribe', self.handle_push_subscribe),
            web.post('/push/send', self.handle_push_send),

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
            scene_data_dir = os.path.join(STATIC_DIR, "scene-data")
            if os.path.isdir(scene_data_dir):
                app.router.add_static('/scene-data/', path=scene_data_dir, name='scene-data')
                logger.info(f"Serving scene geometry from {scene_data_dir}")
                for scene in DEFAULT_SCENES:
                    self._load_scene_geometry(scene)

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, '0.0.0.0', CENTRAL_HTTP_PORT)
        await site.start()
        logger.info(f"Odisea Central V2 running on port {CENTRAL_HTTP_PORT}")

        await self.milestone_checker.load()
        cleanup_task = asyncio.create_task(self._cleanup_loop())
        db_worker_task = asyncio.create_task(self._db_worker())
        import_task = asyncio.create_task(self._import_task())
        geo_lookup_task = asyncio.create_task(self._geo_lookup_task())

        try:
            while True:
                await asyncio.sleep(3600)
        finally:
            logger.info("Odisea Central shutting down")
            cleanup_task.cancel()
            db_worker_task.cancel()
            import_task.cancel()
            geo_lookup_task.cancel()
            await runner.cleanup()

if __name__ == "__main__":
    if BRIDGE_TOKEN == DEV_DEFAULT_TOKEN:
        logger.warning("Using INSECURE dev default token. Set ODISEA_BRIDGE_TOKEN for production.")

    central = OdiseaCentral()
    try:
        asyncio.run(central.run())
    except KeyboardInterrupt:
        pass
