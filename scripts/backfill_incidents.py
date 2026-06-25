#!/usr/bin/env python3
"""Idempotent incident backfill from existing hotzones and heartbeat data.

Creates incident_groups and incident_occurrences for existing data that
predates the v1 dashboard incident system. Can be run repeatedly — groups
are keyed by stable signature hashes so duplicates are impossible.
"""

import hashlib
import json
import logging
import os
import sqlite3
import time
from typing import Optional

GHOSTS_DIR = os.environ.get("CENTRAL_GHOSTS_DIR", "./data/ghosts")
SQLITE_DB = os.environ.get("CENTRAL_SQLITE_DB", os.environ.get("CENTRAL_DB_PATH", "./data/ghosts.db"))
INCIDENT_FPS_THRESHOLD = int(os.environ.get("CENTRAL_INCIDENT_FPS_THRESHOLD", 15))
INCIDENT_DURATION_S = int(os.environ.get("CENTRAL_INCIDENT_DURATION_S", 5))
INCIDENT_SPATIAL_CLUSTER_RADIUS = float(os.environ.get("CENTRAL_INCIDENT_CLUSTER_RADIUS", 5.0))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("backfill_incidents")


def db_connect(path):
    conn = sqlite3.connect(path, timeout=15.0)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=8000")
        conn.execute("PRAGMA synchronous=NORMAL")
    except sqlite3.Error:
        pass
    return conn


def ensure_tables(conn):
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS incident_groups (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            scene TEXT,
            zone TEXT DEFAULT '',
            spatial_cluster_x REAL,
            spatial_cluster_z REAL,
            status TEXT NOT NULL DEFAULT 'open',
            count INTEGER NOT NULL DEFAULT 0,
            first_seen REAL,
            last_seen REAL,
            builds_seen TEXT DEFAULT '[]'
        );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_incident_groups_status ON incident_groups(status);")
    cur.execute("CREATE INDEX IF NOT EXISTS idx_incident_groups_type ON incident_groups(type);")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS incident_occurrences (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            player_id TEXT,
            session_id TEXT,
            fps REAL,
            timestamp REAL,
            scene TEXT,
            build_id TEXT,
            FOREIGN KEY (group_id) REFERENCES incident_groups(id)
        );
    """)
    cur.execute("CREATE INDEX IF NOT EXISTS idx_incident_occurrences_group ON incident_occurrences(group_id);")
    conn.commit()


def incident_signature(incident_type, scene, zone, pos_x, pos_z, radius=INCIDENT_SPATIAL_CLUSTER_RADIUS):
    quant_x = round(pos_x / radius) * radius
    quant_z = round(pos_z / radius) * radius
    key = f"{incident_type}:{scene}:{zone}:{quant_x}:{quant_z}"
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def backfill_hotzones(conn):
    """Create incident groups for every existing hotzone that lacks a group link."""
    cur = conn.cursor()
    cur.execute("""
        SELECT id, player_id, session_id, timestamp, scene, grid_x, grid_z
        FROM hotzones
        WHERE scene IS NOT NULL AND scene != ''
        ORDER BY timestamp ASC
    """)
    rows = cur.fetchall()

    created_groups = 0
    created_occs = 0
    for row in rows:
        hz_id, pid, sid, ts, scene, gx, gz = row
        gx = gx or 0
        gz = gz or 0
        sig = incident_signature("hotzone", scene, "", gx, gz, INCIDENT_SPATIAL_CLUSTER_RADIUS)

        occ_id = f"hotzone:{hz_id}"
        cur.execute("SELECT id FROM incident_groups WHERE id = ?", (sig,))
        existing = cur.fetchone()
        cur.execute("SELECT 1 FROM incident_occurrences WHERE id = ?", (occ_id,))
        occurrence_exists = cur.fetchone() is not None
        if existing and not occurrence_exists:
            cur.execute(
                """UPDATE incident_groups
                   SET count = count + 1, last_seen = MAX(last_seen, ?)
                   WHERE id = ?""",
                (ts, sig),
            )
        elif not existing:
            cur.execute(
                """INSERT INTO incident_groups
                   (id, type, scene, zone, spatial_cluster_x, spatial_cluster_z,
                    status, count, first_seen, last_seen, builds_seen)
                   VALUES (?, 'hotzone', ?, '', ?, ?, 'open', 1, ?, ?, '[]')""",
                (sig, scene, gx, gz, ts, ts),
            )
            created_groups += 1

        cur.execute(
            """INSERT OR IGNORE INTO incident_occurrences
               (id, group_id, player_id, session_id, fps, timestamp, scene, build_id)
               VALUES (?, ?, ?, ?, 0, ?, ?, '')""",
            (occ_id, sig, pid, sid, ts, scene),
        )
        if cur.rowcount > 0:
            created_occs += 1

    conn.commit()
    logger.info("Hotzone backfill: %d groups, %d occurrences", created_groups, created_occs)
    return created_groups, created_occs


def backfill_low_fps(conn):
    """Scan focused, visible heartbeats for sustained low-FPS windows and create incidents.

    A window is: at least INCIDENT_DURATION_S of consecutive samples
    (within a single session) where fps < INCIDENT_FPS_THRESHOLD.
    """

    cur = conn.cursor()
    cur.execute("""
        SELECT player_id, session_id, timestamp, fps, scene,
               pos_x, pos_z, build_id
        FROM heartbeats
        WHERE COALESCE(focused, 1) = 1
          AND LOWER(COALESCE(platform, '')) != 'server'
          AND scene IS NOT NULL AND scene != ''
        ORDER BY player_id, session_id, timestamp ASC
    """)
    rows = cur.fetchall()

    created_groups = 0
    created_occs = 0
    window_start = None
    window_rows = []
    current_sid = None

    def flush_window():
        nonlocal created_groups, created_occs
        if not window_rows:
            return
        if len(window_rows) < INCIDENT_DURATION_S:
            return
        first = window_rows[0]
        last = window_rows[-1]
        dur = last[1] - first[1]
        if dur < INCIDENT_DURATION_S:
            return

        mean_x = sum(r[3] or 0 for r in window_rows) / len(window_rows)
        mean_z = sum(r[4] or 0 for r in window_rows) / len(window_rows)

        sig = incident_signature("low_fps", first[0], "", mean_x, mean_z, INCIDENT_SPATIAL_CLUSTER_RADIUS)
        pid_val = first[5]  # player_id
        sid_val = first[6]  # session_id

        occ_id = f"lowfps:{sig}:{pid_val}:{sid_val}:{int(first[1])}:{int(last[1])}"
        cur.execute("SELECT 1 FROM incident_occurrences WHERE group_id = ? AND player_id = ? AND session_id = ?",
                    (sig, pid_val, sid_val))
        if cur.fetchone():
            return

        cur.execute("SELECT id FROM incident_groups WHERE id = ?", (sig,))
        if cur.fetchone():
            cur.execute(
                """UPDATE incident_groups
                   SET count = count + 1, last_seen = MAX(last_seen, ?)
                   WHERE id = ?""",
                (last[1], sig),
            )
        else:
            builds = [first[6]] if first[6] else []
            cur.execute(
                """INSERT INTO incident_groups
                   (id, type, scene, zone, spatial_cluster_x, spatial_cluster_z,
                    status, count, first_seen, last_seen, builds_seen)
                   VALUES (?, 'low_fps', ?, '', ?, ?, 'open', 1, ?, ?, ?)""",
                (sig, first[0], mean_x, mean_z, first[1], last[1], json.dumps(builds)),
            )
            created_groups += 1

        cur.execute(
            """INSERT OR IGNORE INTO incident_occurrences
               (id, group_id, player_id, session_id, fps, timestamp, scene, build_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (occ_id, sig, pid_val, sid_val, first[2], last[1], first[0], first[6] or ""),
        )
        if cur.rowcount > 0:
            created_occs += 1

    for row in rows:
        scene, ts, fps, pos_x, pos_z, pid, sid, build_id = (
            row[4], row[2], row[3], row[5] or 0, row[6] or 0,
            row[0], row[1], row[7] or "",
        )

        if window_rows and (sid != current_sid or pid != window_rows[0][5]):
            flush_window()
            window_rows = []
            window_start = None
            current_sid = sid
        elif current_sid is None:
            current_sid = sid

        if fps < INCIDENT_FPS_THRESHOLD:
            if window_start is None:
                window_start = ts
            window_rows.append((scene, ts, fps, pos_x, pos_z, pid, sid, build_id))
        else:
            flush_window()
            window_rows = []
            window_start = None

    flush_window()
    conn.commit()
    logger.info("Low-FPS backfill: %d groups, %d occurrences", created_groups, created_occs)
    return created_groups, created_occs


def main():
    logger.info("Starting incident backfill (SQLite: %s)", SQLITE_DB)

    if not os.path.exists(SQLITE_DB):
        logger.error("Database not found: %s", SQLITE_DB)
        return 1

    conn = db_connect(SQLITE_DB)
    try:
        ensure_tables(conn)
        hz_groups, hz_occs = backfill_hotzones(conn)
        fps_groups, fps_occs = backfill_low_fps(conn)
        logger.info(
            "Backfill complete: %d new groups, %d new occurrences",
            hz_groups + fps_groups, hz_occs + fps_occs,
        )
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
