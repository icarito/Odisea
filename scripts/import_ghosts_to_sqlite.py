import os
import json
import sqlite3
import logging
from typing import Optional

# Configuration
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
SQLITE_DB = os.environ.get("CENTRAL_SQLITE_DB", "./data/ghosts.db")

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("import_ghosts")

def init_db(conn):
    cursor = conn.cursor()
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
    # Idempotent ALTER TABLE: align older DBs with the central schema. Each
    # call ignores "duplicate column name" so re-runs are safe. This mirrors the
    # ALTER block in odisea_central.py:_init_db so re-imports land perf data.
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
        ("transition_stage", "TEXT"),
        ("transition_path", "TEXT"),
        ("transition_current_scene", "TEXT"),
        ("transition_elapsed_ms", "INTEGER"),
        ("transition_progress", "REAL"),
        ("transition_loader_stage", "INTEGER"),
        ("transition_preloading", "INTEGER"),
        ("transition_overlay_visible", "INTEGER"),
        ("transition_overlay_alpha", "REAL"),
        ("transition_error", "TEXT"),
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
    conn.commit()

def import_ghosts():
    if not os.path.exists(GHOSTS_DIR):
        logger.warning(f"Ghosts directory not found: {GHOSTS_DIR}")
        return

    os.makedirs(os.path.dirname(SQLITE_DB), exist_ok=True)
    conn = sqlite3.connect(SQLITE_DB)
    init_db(conn)
    cursor = conn.cursor()

    count = 0
    for root, _, files in os.walk(GHOSTS_DIR):
        for file in files:
            if file.endswith(".jsonl"):
                path = os.path.join(root, file)
                count += process_file(path, cursor)
                conn.commit()

    logger.info(f"Imported {count} new heartbeats.")
    conn.close()

def process_file(path: str, cursor: sqlite3.Cursor) -> int:
    new_records = 0
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    data = json.loads(line)
                    player_id = data.get("player_id")
                    session_id = data.get("session_id")
                    timestamp = data.get("timestamp")

                    if not player_id or not session_id or timestamp is None:
                        continue

                    player_data = data.get("player", {})
                    pos = player_data.get("position", [0, 0, 0])
                    perf = player_data.get("perf") or {}
                    if not isinstance(perf, dict):
                        perf = {}
                    transition = player_data.get("transition") or {}
                    if not isinstance(transition, dict):
                        transition = {}
                    platform = player_data.get("platform") or data.get("platform") or "unknown"

                    # Mapping data from JSON to Table. perf.dc/obj/vtx/nodes come
                    # from the `perf` sub-dict ANNAV2 sends; older JSONL without
                    # perf leave them NULL (AVG ignores NULLs in the heatmap).
                    record = (
                        player_id,
                        session_id,
                        timestamp,
                        player_data.get("scene", "unknown"),
                        platform,
                        player_data.get("fps", 0.0),
                        player_data.get("memory_mb", 0.0),
                        pos[0], pos[1], pos[2],
                        data.get("godot_version", "unknown"),
                        data.get("peer_id", "unknown"),
                        data.get("game_version"),
                        data.get("git_commit"),
                        data.get("build_id"),
                        data.get("build_channel"),
                        data.get("official_host"),
                        1 if data.get("official_build") else 0,
                        data.get("intake_mode", "telemetry"),
                        0 if player_data.get("focused", True) is False else 1,
                        perf.get("dc"),
                        perf.get("obj"),
                        perf.get("vtx"),
                        perf.get("nodes"),
                        transition.get("stage"),
                        transition.get("path"),
                        transition.get("current_scene"),
                        transition.get("elapsed_ms"),
                        transition.get("progress"),
                        transition.get("loader_stage"),
                        1 if transition.get("preloading") else 0,
                        1 if transition.get("overlay_visible") else 0,
                        transition.get("overlay_alpha"),
                        transition.get("error"),
                    )

                    try:
                        cursor.execute("""
                        INSERT OR IGNORE INTO heartbeats (
                            player_id, session_id, timestamp, scene, platform,
                            fps, memory_mb, pos_x, pos_y, pos_z,
                            engine_version, peer_id,
                            game_version, git_commit, build_id, build_channel,
                            official_host, official_build, intake_mode, focused,
                            draw_calls, objects, vertices, nodes,
                            transition_stage, transition_path, transition_current_scene,
                            transition_elapsed_ms, transition_progress, transition_loader_stage,
                            transition_preloading, transition_overlay_visible,
                            transition_overlay_alpha, transition_error
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """, record)
                        if cursor.rowcount > 0:
                            new_records += 1
                    except sqlite3.Error as e:
                        logger.error(f"Error inserting record: {e}")
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        logger.error(f"Error processing file {path}: {e}")

    if new_records > 0:
        logger.info(f"File {path}: {new_records} new records.")
    return new_records

if __name__ == "__main__":
    import_ghosts()
