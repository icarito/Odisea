#!/usr/bin/env python3
"""Agrega heartbeats por (escena, semana ISO) y poda con consentimiento.

Objetivo: poder retener solo lo necesario en ghosts.db sin perder la senal
agregada. Antes de borrar una (scene, week) hay que haber exportado su
agregado a un sidecar independiente. El prune NUNCA toca filas cuya
(scene, week) no tenga ya una fila en el sidecar.

Diseno (compatibiliza con lo existente, no lo duplica):
  * Eje espacial: usa pos_x/pos_z, la misma convencion que el heatmap vivo
    (odisea_central.py handle_ghosts_heatmap: grid_x = pos_x/res, grid_z =
    pos_z/res). En Godot pos_y es la altura; el plano de interes es XZ.
  * Escenas: se conservan los strings crudos de la columna scene, igual que
    el dashboard, para que el archivo case con /scenes y con los agregados.
  * Semana: ISO 8601 (lunes), calculada por indice de semana desde un lunes
    epoch fijo (1970-01-05 00:00:00 UTC). Misma aritmetica en SQL y en Python.
  * Sidecar y JSON: separados de ghosts.db; ghosts.db solo recibe el DELETE
    del prune (y nunca en esta primera corrida, que es no-op).
  * Perf: fps/memoria se leen con el mismo criterio tolerante a NULL que el
    central (AVG ignora NULL; fps<=0 no forma parte del promedio).

Privacidad: solo se persisten conteos, rangos e histogramas. Ningun
player_id/session_id crudo sale del script ni aparece en logs.

Salida: stdout (journalctl -u odisea-heartbeats-prune lo captura).

Env:
  CENTRAL_SQLITE_DB / CENTRAL_DB_PATH   ruta a ghosts.db (default data/ghosts.db)
  ODISEA_AGGREGATES_DB                  sidecar (default data/telemetry_aggregates.db)
  ODISEA_HEATMAP_ARCHIVE_DIR            JSON por semana (default data/heatmap_archive)
  ODISEA_HEARTBEAT_RETENTION_DAYS       retencion; default 180, minimo 90 (clampea)
"""

from __future__ import annotations

import argparse
import array
import datetime as dt
import json
import logging
import os
import shutil
import sqlite3
import struct
import sys
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _path_from_env(env_name: str, default_rel: str) -> str:
    value = os.environ.get(env_name) or default_rel
    if not os.path.isabs(value):
        value = os.path.join(REPO_ROOT, value)
    return os.path.abspath(value)


DB_PATH = _path_from_env(
    "CENTRAL_SQLITE_DB",
    os.environ.get("CENTRAL_DB_PATH", os.path.join("data", "ghosts.db")),
)
SIDECAR_DB = _path_from_env("ODISEA_AGGREGATES_DB", os.path.join("data", "telemetry_aggregates.db"))
ARCHIVE_DIR = _path_from_env("ODISEA_HEATMAP_ARCHIVE_DIR", os.path.join("data", "heatmap_archive"))

HIST_BINS = 32
HIST_CELLS = HIST_BINS * HIST_BINS
DELETE_BATCH = 5000
BATCH_YIELD_S = 0.2

# 1970-01-05 00:00:00 UTC es lunes: punto de anclaje para indexar semanas ISO.
MONDAY_EPOCH = 345600.0
WEEK_SECONDS = 604800.0

DEFAULT_RETENTION_DAYS = 180
MIN_RETENTION_DAYS = 90
VACUUM_MIN_FREE_BYTES = 2 * 1024 ** 3
VACUUM_MIN_PCT = 5.0

# Semanas ISO indexadas como lunes. CAST trunca hacia cero; los timestamps son
# positivos, asi que equivale a floor.
_WEEK_SQL = "CAST((timestamp - 345600.0) / 604800.0 AS INTEGER)"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("heartbeat_aggregate")


def db_connect(path: str, timeout: float = 15.0) -> sqlite3.Connection:
    """Mismo patron que odisea_central.py:74-85 (WAL + busy_timeout).

    WAL deja leer mientras el central escribe; busy_timeout hace que el DELETE
    por lotes espere el lock en vez de fallar al instante.
    """
    conn = sqlite3.connect(path, timeout=timeout)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA busy_timeout=8000")
        conn.execute("PRAGMA synchronous=NORMAL")
    except sqlite3.Error:
        pass
    return conn


def week_label(week_index: int) -> tuple[str, float]:
    """(etiqueta ISO 'YYYY-Www', timestamp del lunes 00:00 UTC)."""
    start = MONDAY_EPOCH + week_index * WEEK_SECONDS
    start_dt = dt.datetime.fromtimestamp(start, tz=dt.timezone.utc)
    iso_year, iso_week, _ = start_dt.isocalendar()
    return f"{iso_year}-W{iso_week:02d}", start


def _bucket(value: float, lo: float, hi: float) -> int:
    if lo is None or hi is None or hi <= lo:
        return 0
    idx = int((value - lo) / (hi - lo) * HIST_BINS)
    if idx < 0:
        return 0
    if idx >= HIST_BINS:
        return HIST_BINS - 1
    return idx


def export_aggregates() -> dict:
    """Dos pasadas de solo lectura sobre heartbeats; una por escena-semana.

    Pasada 1: conteos, jugadores/sesiones distintas, rangos y perf.
    Pasada 2: histograma 2D pos_x/pos_z normalizado al rango observado de cada
    semana. Ambas son SELECT sueltos (sin transaccion larga) para no impedir
    que WAL haga checkpoint mientras el central escribe.
    """
    conn = db_connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    total = cur.execute("SELECT COUNT(*) FROM heartbeats").fetchone()[0]
    log.info("heartbeats totales en ghosts.db: %d", total)

    records: dict[tuple[str, int], dict] = {}
    stats_sql = f"""
        SELECT
            COALESCE(scene, '') AS scene,
            {_WEEK_SQL} AS wk,
            COUNT(*) AS n_frames,
            COUNT(DISTINCT player_id) AS n_players,
            COUNT(DISTINCT session_id) AS n_sessions,
            MIN(pos_x) AS pos_x_min, MAX(pos_x) AS pos_x_max,
            MIN(pos_z) AS pos_z_min, MAX(pos_z) AS pos_z_max,
            AVG(CASE WHEN fps > 0 THEN fps END) AS fps_avg,
            MIN(CASE WHEN fps > 0 THEN fps END) AS fps_min,
            MAX(CASE WHEN fps > 0 THEN fps END) AS fps_max,
            AVG(memory_mb) AS mem_avg,
            MAX(timestamp) AS source_max_ts
        FROM heartbeats
        GROUP BY scene, wk
    """
    for row in cur.execute(stats_sql):
        key = (row["scene"], int(row["wk"]))
        records[key] = {
            "n_frames": row["n_frames"],
            "n_players": row["n_players"],
            "n_sessions": row["n_sessions"],
            "pos_x_min": row["pos_x_min"], "pos_x_max": row["pos_x_max"],
            "pos_z_min": row["pos_z_min"], "pos_z_max": row["pos_z_max"],
            "fps_avg": row["fps_avg"], "fps_min": row["fps_min"], "fps_max": row["fps_max"],
            "mem_avg": row["mem_avg"],
            "source_max_ts": row["source_max_ts"],
            "hist": array.array("I", [0]) * HIST_CELLS,
        }

    hist_sql = f"""
        SELECT COALESCE(scene, '') AS scene, {_WEEK_SQL} AS wk, pos_x, pos_z
        FROM heartbeats
        WHERE pos_x IS NOT NULL AND pos_z IS NOT NULL
    """
    hist_rows = 0
    for scene, wk, pos_x, pos_z in cur.execute(hist_sql):
        key = (scene, int(wk))
        rec = records.get(key)
        if rec is None:
            # Fila no vista en la pasada 1 (escritura concurrente del central).
            rec = {
                "n_frames": 0, "n_players": 0, "n_sessions": 0,
                "pos_x_min": pos_x, "pos_x_max": pos_x,
                "pos_z_min": pos_z, "pos_z_max": pos_z,
                "fps_avg": None, "fps_min": None, "fps_max": None,
                "mem_avg": None, "source_max_ts": None,
                "hist": array.array("I", [0]) * HIST_CELLS,
            }
            records[key] = rec
        bx = _bucket(pos_x, rec["pos_x_min"], rec["pos_x_max"])
        bz = _bucket(pos_z, rec["pos_z_min"], rec["pos_z_max"])
        rec["hist"][bz * HIST_BINS + bx] += 1
        hist_rows += 1

    conn.close()
    log.info(
        "agregados calculados: %d escena-semanas, %d filas posicionadas, %d filas totales",
        len(records), hist_rows, total,
    )
    return {"records": records, "total": total, "hist_rows": hist_rows}


def write_sidecar(records: dict) -> int:
    os.makedirs(os.path.dirname(SIDECAR_DB), exist_ok=True)
    conn = db_connect(SIDECAR_DB)
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS aggregates (
            scene           TEXT    NOT NULL,
            week            TEXT    NOT NULL,
            week_start_ts   REAL    NOT NULL,
            n_frames        INTEGER NOT NULL,
            n_players       INTEGER NOT NULL,
            n_sessions      INTEGER NOT NULL,
            pos_x_min       REAL,
            pos_x_max       REAL,
            pos_z_min       REAL,
            pos_z_max       REAL,
            fps_avg         REAL,
            fps_min         REAL,
            fps_max         REAL,
            mem_avg         REAL,
            hist_bins       INTEGER NOT NULL,
            hist            BLOB    NOT NULL,
            source_max_ts   REAL,
            computed_at     REAL    NOT NULL,
            PRIMARY KEY (scene, week)
        )
        """
    )
    cur.execute("CREATE INDEX IF NOT EXISTS idx_aggregates_week ON aggregates(week)")
    now = time.time()
    written = 0
    for (scene, wk), rec in sorted(records.items(), key=lambda kv: (kv[0][1], kv[0][0])):
        label, start = week_label(wk)
        blob = struct.pack("<%dI" % HIST_CELLS, *rec["hist"])
        cur.execute(
            """
            INSERT INTO aggregates (
                scene, week, week_start_ts, n_frames, n_players, n_sessions,
                pos_x_min, pos_x_max, pos_z_min, pos_z_max,
                fps_avg, fps_min, fps_max, mem_avg,
                hist_bins, hist, source_max_ts, computed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(scene, week) DO UPDATE SET
                week_start_ts=excluded.week_start_ts,
                n_frames=excluded.n_frames,
                n_players=excluded.n_players,
                n_sessions=excluded.n_sessions,
                pos_x_min=excluded.pos_x_min, pos_x_max=excluded.pos_x_max,
                pos_z_min=excluded.pos_z_min, pos_z_max=excluded.pos_z_max,
                fps_avg=excluded.fps_avg, fps_min=excluded.fps_min, fps_max=excluded.fps_max,
                mem_avg=excluded.mem_avg,
                hist_bins=excluded.hist_bins, hist=excluded.hist,
                source_max_ts=excluded.source_max_ts, computed_at=excluded.computed_at
            """,
            (
                scene, label, start, rec["n_frames"], rec["n_players"], rec["n_sessions"],
                rec["pos_x_min"], rec["pos_x_max"], rec["pos_z_min"], rec["pos_z_max"],
                rec["fps_avg"], rec["fps_min"], rec["fps_max"], rec["mem_avg"],
                HIST_BINS, blob, rec["source_max_ts"], now,
            ),
        )
        written += 1
    conn.commit()
    conn.close()
    log.info("sidecar %s: %d filas escena-semana (upsert)", SIDECAR_DB, written)
    return written


def write_json_archive(records: dict) -> int:
    """Un JSON por semana ISO con todas las escenas (escritura atomica)."""
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    by_week: dict[str, dict] = {}
    for (scene, wk), rec in records.items():
        label, start = week_label(wk)
        week = by_week.setdefault(
            label,
            {
                "week": label,
                "week_start_utc": dt.datetime.fromtimestamp(
                    start, tz=dt.timezone.utc
                ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "bins": HIST_BINS,
                "axes": ["pos_x", "pos_z"],
                "scenes": {},
            },
        )
        rows = [
            rec["hist"][bz * HIST_BINS:(bz + 1) * HIST_BINS].tolist()
            for bz in range(HIST_BINS)
        ]
        week["scenes"][scene] = {
            "n_frames": rec["n_frames"],
            "n_players": rec["n_players"],
            "n_sessions": rec["n_sessions"],
            "pos_x_range": [rec["pos_x_min"], rec["pos_x_max"]],
            "pos_z_range": [rec["pos_z_min"], rec["pos_z_max"]],
            "fps": {"avg": rec["fps_avg"], "min": rec["fps_min"], "max": rec["fps_max"]},
            "memory_mb_avg": rec["mem_avg"],
            "histogram": rows,
        }
    generated = dt.datetime.now(tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for label, payload in by_week.items():
        payload["generated_at"] = generated
        path = os.path.join(ARCHIVE_DIR, f"{label}.json")
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, separators=(",", ":"), sort_keys=True)
        os.replace(tmp, path)
    log.info("archivo JSON: %d semanas en %s", len(by_week), ARCHIVE_DIR)
    return len(by_week)


def prune(retention_days: int, total_rows: int) -> int:
    """Borra por lotes solo escena-semanas ya agregadas y vencidas."""
    cutoff = time.time() - retention_days * 86400.0
    side = db_connect(SIDECAR_DB)
    try:
        candidates = [
            (scene, start)
            for scene, start in side.execute(
                "SELECT DISTINCT scene, week_start_ts FROM aggregates"
            )
            if start + WEEK_SECONDS <= cutoff  # semana cerrada por completo antes del corte
        ]
    except sqlite3.OperationalError as exc:
        log.error("prune: sidecar sin tabla aggregates (%s); no se borra nada", exc)
        side.close()
        return 0
    side.close()

    conn = db_connect(DB_PATH)
    cur = conn.cursor()
    log.info(
        "prune: %d escena-semanas agregadas son anteriores al corte de %d dias",
        len(candidates), retention_days,
    )

    deleted = 0
    for scene, start in candidates:
        while True:
            cur.execute(
                """
                DELETE FROM heartbeats
                WHERE id IN (
                    SELECT id FROM heartbeats
                    WHERE scene = ? AND timestamp >= ? AND timestamp < ?
                    LIMIT ?
                )
                """,
                (scene, start, cutoff, DELETE_BATCH),
            )
            n = cur.rowcount
            conn.commit()
            deleted += n
            if n < DELETE_BATCH:
                break
            time.sleep(BATCH_YIELD_S)  # cede el lock de escritura al importador

    if deleted:
        log.info("prune: %d filas borradas de %d escena-semanas", deleted, len(candidates))
    else:
        log.info("prune: 0 filas borradas (no-op seguro)")

    maybe_vacuum(conn, deleted, total_rows)
    conn.close()
    return deleted


def maybe_vacuum(conn: sqlite3.Connection, deleted: int, total_rows: int) -> None:
    pct = (deleted / total_rows * 100.0) if total_rows else 0.0
    if deleted <= 0:
        log.info("vacuum: omitido (0 filas borradas)")
        return
    if pct <= VACUUM_MIN_PCT:
        log.info("vacuum: omitido (%.2f%% borrado <= %.1f%%)", pct, VACUUM_MIN_PCT)
        return
    free = shutil.disk_usage(os.path.dirname(DB_PATH)).free
    log.info(
        "vacuum: candidato (%.2f%% borrado); espacio libre %d bytes (%.1f GB)",
        pct, free, free / 1024 ** 3,
    )
    if free < VACUUM_MIN_FREE_BYTES:
        log.warning("vacuum: omitido, espacio libre < 2 GB")
        return
    try:
        vconn = db_connect(DB_PATH, timeout=60.0)
        vconn.execute("PRAGMA busy_timeout=60000")
        vconn.execute("VACUUM")
        vconn.close()
        log.info("vacuum: completado")
    except sqlite3.Error as exc:
        log.warning("vacuum: fallo (se conserva la poda ya confirmada): %s", exc)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="calcula y reporta sin escribir")
    parser.add_argument("--skip-prune", action="store_true", help="solo exporta agregados")
    args = parser.parse_args()

    started = time.time()
    try:
        raw_retention = int(os.environ.get("ODISEA_HEARTBEAT_RETENTION_DAYS", DEFAULT_RETENTION_DAYS))
    except (TypeError, ValueError):
        log.warning("ODISEA_HEARTBEAT_RETENTION_DAYS invalido; uso default %d", DEFAULT_RETENTION_DAYS)
        raw_retention = DEFAULT_RETENTION_DAYS
    retention_days = raw_retention
    if raw_retention < MIN_RETENTION_DAYS:
        log.warning(
            "ODISEA_HEARTBEAT_RETENTION_DAYS=%d < minimo %d; clampeado a %d",
            raw_retention, MIN_RETENTION_DAYS, MIN_RETENTION_DAYS,
        )
        retention_days = MIN_RETENTION_DAYS

    if not os.path.exists(DB_PATH):
        log.error("ghosts.db no existe: %s", DB_PATH)
        return 1

    result = export_aggregates()
    records = result["records"]
    total = result["total"]
    weeks = {week_label(wk)[0] for _, wk in records}
    log.info("semanas ISO cubiertas: %d (%s .. %s)", len(weeks), min(weeks), max(weeks))
    aggregated_frames = sum(r["n_frames"] for r in records.values())
    log.info("filas agregadas (suma n_frames): %d / total %d", aggregated_frames, total)

    if not args.dry_run:
        write_sidecar(records)
        write_json_archive(records)
    else:
        log.info("dry-run: sidecar y JSON no escritos")

    deleted = 0
    if args.skip_prune or args.dry_run:
        log.info("prune: omitido (--skip-prune/--dry-run)")
    else:
        deleted = prune(retention_days, total)

    log.info(
        "listo: total=%d agregadas=%d semanas=%d borradas=%d retencion=%dd duracion=%.1fs",
        total, aggregated_frames, len(weeks), deleted, retention_days, time.time() - started,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
