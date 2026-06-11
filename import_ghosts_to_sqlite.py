import sqlite3
import os
import json
import time
import logging

# --- Configuration ---
GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
DB_PATH = os.environ.get("CENTRAL_DB_PATH", "./data/ghosts.db")

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger("import_ghosts")

def init_db():
    conn = sqlite3.connect(DB_PATH)
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
    )
    """)
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_scene ON heartbeats(scene)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_timestamp ON heartbeats(timestamp)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_heartbeats_platform ON heartbeats(platform)")
    conn.commit()
    return conn

def import_ghosts():
    conn = init_db()
    cursor = conn.cursor()

    if not os.path.exists(GHOSTS_DIR):
        logger.error(f"Ghosts directory {GHOSTS_DIR} does not exist.")
        return

    count = 0
    skipped = 0

    for pid in os.listdir(GHOSTS_DIR):
        p_path = os.path.join(GHOSTS_DIR, pid)
        if not os.path.isdir(p_path):
            continue

        for sid_file in os.listdir(p_path):
            if not sid_file.endswith(".jsonl"):
                continue

            f_path = os.path.join(p_path, sid_file)
            sid = sid_file[:-6]

            with open(f_path, 'r') as f:
                for line in f:
                    try:
                        data = json.loads(line)
                        player_data = data.get("player", {})
                        pos = player_data.get("position", [0, 0, 0])

                        # Handle potential empty platform from legacy data
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
                        if cursor.rowcount > 0:
                            count += 1
                        else:
                            skipped += 1
                    except Exception as e:
                        logger.error(f"Error parsing line in {f_path}: {e}")

            # Commit per file to avoid huge transactions
            conn.commit()

    logger.info(f"Import finished. Added {count} heartbeats, skipped {skipped} duplicates.")
    conn.close()

if __name__ == "__main__":
    import_ghosts()
