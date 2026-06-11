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
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_scene ON heartbeats(scene);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_timestamp ON heartbeats(timestamp);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_platform ON heartbeats(platform);")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_session ON heartbeats(session_id);")
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

                    # Mapping data from JSON to Table
                    record = (
                        player_id,
                        session_id,
                        timestamp,
                        player_data.get("scene", "unknown"),
                        data.get("platform", "unknown"),
                        player_data.get("fps", 0.0),
                        player_data.get("memory_mb", 0.0),
                        pos[0], pos[1], pos[2],
                        data.get("godot_version", "unknown"),
                        data.get("peer_id", "unknown")
                    )

                    try:
                        cursor.execute("""
                        INSERT OR IGNORE INTO heartbeats (
                            player_id, session_id, timestamp, scene, platform,
                            fps, memory_mb, pos_x, pos_y, pos_z,
                            engine_version, peer_id
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
