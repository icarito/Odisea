#!/usr/bin/env python3
"""
telemetry_stats.py — Estadísticas de telemetría desde ghosts.db del Bridge Central.

Lee la DB SQLite de heartbeats y genera reporte resumido de:
- Jugadores únicos y sesiones
- Distribución por plataforma y escena
- Rankings de actividad
- Estimación de jugadores "reales" (anónimos vs recurrentes)

Uso:
    python3 scripts/telemetry_stats.py --db <path_to_ghosts.db>
    python3 scripts/telemetry_stats.py                               # busca default
    python3 scripts/telemetry_stats.py --json                         # output JSON
    python3 scripts/telemetry_stats.py --cron                         # modo breve para cron
"""

import sqlite3
import sys
import os
import json
import argparse
from datetime import datetime, timezone
from collections import defaultdict, Counter

DEFAULT_DB = "/home/ubuntu/anna-central/data/ghosts.db"
DEFAULT_STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".telemetry_stats_state.json")


def connect(db_path: str) -> sqlite3.Connection:
    if not os.path.exists(db_path):
        print(f"ERROR: DB no encontrada: {db_path}", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def ts_to_iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def run(db_path: str, as_json: bool, cron_mode: bool, state_file: str = ""):
    conn = connect(db_path)
    cur = conn.cursor()

    # --- Totales generales ---
    cur.execute("""
        SELECT
            COUNT(DISTINCT player_id) AS unique_players,
            COUNT(DISTINCT session_id) AS unique_sessions,
            COUNT(*) AS total_hb,
            MIN(timestamp) AS first_ts,
            MAX(timestamp) AS last_ts,
            COUNT(DISTINCT scene) AS unique_scenes
        FROM heartbeats
    """)
    row = cur.fetchone()
    totals = dict(row)

    # --- Por plataforma ---
    cur.execute("""
        SELECT
            CASE
                WHEN platform LIKE '%HTML5%' THEN 'HTML5 (web)'
                WHEN platform LIKE '%Android%' THEN 'Android'
                WHEN platform LIKE '%Windows%' THEN 'Windows'
                WHEN platform LIKE '%X11%' OR platform LIKE '%Linux%'
                     OR platform = 'Unix' OR platform = 'Server' THEN 'Linux/Server'
                WHEN platform IS NULL OR platform = '' THEN 'desconocida'
                ELSE platform
            END AS platform_group,
            COUNT(DISTINCT player_id) AS players,
            COUNT(DISTINCT session_id) AS sessions,
            COUNT(*) AS heartbeats
        FROM heartbeats
        GROUP BY platform_group
        ORDER BY players DESC
    """)
    by_platform = [dict(r) for r in cur.fetchall()]

    # --- Por escena (top 15) ---
    cur.execute("""
        SELECT
            CASE WHEN scene IS NULL OR scene = '' THEN '(sin escena)' ELSE scene END AS scene_name,
            COUNT(DISTINCT player_id) AS players,
            COUNT(DISTINCT session_id) AS sessions,
            COUNT(*) AS heartbeats,
            MIN(timestamp) AS first_seen,
            MAX(timestamp) AS last_seen
        FROM heartbeats
        GROUP BY scene_name
        ORDER BY players DESC
        LIMIT 15
    """)
    by_scene = [dict(r) for r in cur.fetchall()]

    # --- Por día (últimos 14) ---
    cur.execute("""
        SELECT
            strftime('%Y-%m-%d', timestamp, 'unixepoch') AS day,
            COUNT(DISTINCT player_id) AS players,
            COUNT(DISTINCT session_id) AS sessions,
            COUNT(*) AS heartbeats
        FROM heartbeats
        GROUP BY day
        ORDER BY day DESC
        LIMIT 14
    """)
    by_day = [dict(r) for r in cur.fetchall()]

    # --- Players con más sesiones (top 10) ---
    cur.execute("""
        SELECT
            player_id,
            COUNT(DISTINCT session_id) AS sessions,
            COUNT(*) AS heartbeats,
            MIN(timestamp) AS first_seen,
            MAX(timestamp) AS last_seen
        FROM heartbeats
        GROUP BY player_id
        ORDER BY heartbeats DESC
        LIMIT 10
    """)
    top_players = [dict(r) for r in cur.fetchall()]

    # --- Distribución de sesiones por player ---
    cur.execute("""
        SELECT
            CASE
                WHEN sessions_count = 1 THEN '1 sesión (anónimo web)'
                WHEN sessions_count <= 3 THEN '2-3 sesiones'
                WHEN sessions_count <= 10 THEN '4-10 sesiones'
                ELSE '10+ sesiones (recurrente)'
            END AS bucket,
            COUNT(*) AS players,
            SUM(sessions_count) AS total_sessions,
            SUM(heartbeats_count) AS total_heartbeats
        FROM (
            SELECT player_id, COUNT(DISTINCT session_id) AS sessions_count,
                   COUNT(*) AS heartbeats_count
            FROM heartbeats
            GROUP BY player_id
        )
        GROUP BY bucket
        ORDER BY MIN(sessions_count)
    """)
    session_dist = [dict(r) for r in cur.fetchall()]

    # --- Peer grouping (conexiones conocidas vs anónimas) ---
    cur.execute("""
        SELECT
            CASE WHEN peer_id IS NULL OR peer_id = '' OR peer_id = 'unknown'
                 THEN 'anónimo (sin peer)'
                 ELSE 'con peer_id conocido'
            END AS peer_group,
            COUNT(DISTINCT player_id) AS players,
            COUNT(*) AS heartbeats
        FROM heartbeats
        GROUP BY peer_group
    """)
    peer_dist = [dict(r) for r in cur.fetchall()]

    conn.close()

    # --- Ensamblado ---
    report = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "db_file": db_path,
        "periodo": {
            "desde": ts_to_iso(totals["first_ts"]),
            "hasta": ts_to_iso(totals["last_ts"]),
        },
        "totales": {
            "jugadores_unicos": totals["unique_players"],
            "sesiones_unicas": totals["unique_sessions"],
            "heartbeats_totales": totals["total_hb"],
            "escenas_distintas": totals["unique_scenes"],
        },
        "distribucion_plataforma": [
            {
                "plataforma": p["platform_group"],
                "jugadores": p["players"],
                "sesiones": p["sessions"],
                "heartbeats": p["heartbeats"],
            }
            for p in by_platform
        ],
        "top_escenas": [
            {
                "escena": s["scene_name"],
                "jugadores": s["players"],
                "sesiones": s["sessions"],
                "heartbeats": s["heartbeats"],
                "primera_vista": ts_to_iso(s["first_seen"]),
                "ultima_vista": ts_to_iso(s["last_seen"]),
            }
            for s in by_scene
        ],
        "actividad_por_dia": [
            {
                "dia": d["day"],
                "jugadores": d["players"],
                "sesiones": d["sessions"],
                "heartbeats": d["heartbeats"],
            }
            for d in by_day
        ],
        "top_jugadores_recurrentes": [
            {
                "player_id": p["player_id"],
                "sesiones": p["sessions"],
                "heartbeats": p["heartbeats"],
                "primera_vez": ts_to_iso(p["first_seen"]),
                "ultima_vez": ts_to_iso(p["last_seen"]),
                "probable_desarrollador": p["heartbeats"] > 2000,
            }
            for p in top_players
        ],
        "estimacion_jugadores_reales": {
            "anónimos_una_sola_visita": 0,
            "recurrentes_10_mas_sesiones": 0,
            "probables_desarrolladores": 0,
            "estimado_jugadores_externos": 0,
        },
    }

    # Cálculo de estimación real:
    anon = 0
    recur = 0
    dev = 0
    for d in session_dist:
        if "1 sesión" in d["bucket"]:
            anon = d["players"]
        elif "10+" in d["bucket"]:
            recur = d["players"]
    # De esos recurrentes, cuántos son probablemente desarrolladores (heartbeats > 2000)
    dev = sum(1 for p in top_players if p["heartbeats"] > 2000)
    report["estimacion_jugadores_reales"] = {
        "visitantes_anonimos_1_sesión": anon,
        "jugadores_con_recurrencia_4+_sesiones": sum(
            d["players"] for d in session_dist if "4" in d["bucket"] or "10+" in d["bucket"]
        ),
        "probables_desarrolladores_(heartbeats>2000)": dev,
        "estimado_jugadores_externos_reales": max(
            0, recur - dev
        ),
    }

    if cron_mode:
        prev = _load_state(state_file) if state_file else {}
        summary = _cron_summary(report, prev)
        if state_file:
            _save_state(state_file, report)
        if summary:
            print(summary)
        # Si no hay cambios, no imprime nada — el cron superior decide si reportar o no
        return

    if as_json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return

    # --- Salida formateada para humano ---
    pad = "  "
    print("=" * 60)
    print("  TELEMETRÍA ODISEA — RESUMEN DE ESTADÍSTICAS")
    print("=" * 60)
    print(f"\n  Período: {report['periodo']['desde']} → {report['periodo']['hasta']}")
    print(f"  Generado: {report['generated_at']}")
    print()

    print("  ── Totales ──")
    t = report["totales"]
    print(f"{pad}Jugadores únicos:  {t['jugadores_unicos']}")
    print(f"{pad}Sesiones únicas:   {t['sesiones_unicas']}")
    print(f"{pad}Heartbeats totales: {t['heartbeats_totales']}")
    print(f"{pad}Escenas distintas: {t['escenas_distintas']}")
    print()

    print("  ── Por plataforma ──")
    print(f"{pad}{'Plataforma':<20} {'Jug.':>6} {'Ses.':>6} {'HBs':>8}")
    for p in report["distribucion_plataforma"]:
        print(f"{pad}{p['plataforma']:<20} {p['jugadores']:>6} {p['sesiones']:>6} {p['heartbeats']:>8}")
    print()

    print("  ── Top escenas (jugadores) ──")
    print(f"{pad}{'Escena':<25} {'Jug.':>6} {'Ses.':>6} {'HBs':>8}")
    for s in report["top_escenas"]:
        print(f"{pad}{s['escena'][:24]:<25} {s['jugadores']:>6} {s['sesiones']:>6} {s['heartbeats']:>8}")
    print()

    print("  ── Actividad por día (últimos 14) ──")
    print(f"{pad}{'Día':<12} {'Jug.':>5} {'Ses.':>5} {'HBs':>7}")
    for d in report["actividad_por_dia"]:
        print(f"{pad}{d['dia']:<12} {d['jugadores']:>5} {d['sesiones']:>5} {d['heartbeats']:>7}")
    print()

    print("  ── Jugadores más activos ──")
    print(f"{pad}{'Player ID':<35} {'Ses.':>5} {'HBs':>7} {'¿Dev?':<6}")
    for p in report["top_jugadores_recurrentes"]:
        tag = "🧑‍💻" if p["probable_desarrollador"] else "  "
        pid = p["player_id"][:34]
        print(f"{pad}{pid:<35} {p['sesiones']:>5} {p['heartbeats']:>7} {tag:<6}")
    print()

    print("  ── Estimación de jugadores reales ──")
    e = report["estimacion_jugadores_reales"]
    print(f"{pad}Visitantes anónimos (1 sesión):     {e['visitantes_anonimos_1_sesión']}")
    print(f"{pad}Jug. con recurrencia (4+ sesiones): {e['jugadores_con_recurrencia_4+_sesiones']}")
    print(f"{pad}Probables desarrolladores:          {e['probables_desarrolladores_(heartbeats>2000)']}")
    print(f"{pad}Jugadores externos reales (estim.): {e['estimado_jugadores_externos_reales']}")
    print()
    print("=" * 60)


def _load_state(state_file: str) -> dict:
    if os.path.exists(state_file):
        try:
            with open(state_file) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _save_state(state_file: str, data: dict) -> None:
    with open(state_file, "w") as f:
        json.dump(data, f)


def _cron_summary(report: dict, prev: dict) -> str:
    """Genera un resumen breve del reporte actual vs el anterior.
    Retorna el texto del reporte si hay cambios significativos
    respecto a prev, o si es la primera vez (prev vacío).
    Si no hay cambios, retorna string vacío."""
    tot = report["totales"]
    est = report["estimacion_jugadores_reales"]

    lines = []
    first_time = not prev or "totales" not in prev

    if first_time:
        lines.append(f"📊 {tot['jugadores_unicos']} jugadores únicos | "
                     f"{est['visitantes_anonimos_1_sesión']} anónimos | "
                     f"{est['probables_desarrolladores_(heartbeats>2000)']} devs | "
                     f"{est['estimado_jugadores_externos_reales']} externos | "
                     f"{tot['heartbeats_totales']} heartbeats")
        return "\n".join(lines)

    # Solo reportar si hay cambios reales
    changes = []
    delta_players = tot['jugadores_unicos'] - prev['totales']['jugadores_unicos']
    delta_hb = tot['heartbeats_totales'] - prev['totales']['heartbeats_totales']
    delta_externos = est['estimado_jugadores_externos_reales'] - prev.get('estimacion_jugadores_reales', {}).get('estimado_jugadores_externos_reales', 0)

    if delta_players != 0:
        changes.append(f"jugadores {'+' if delta_players > 0 else ''}{delta_players}")
    if delta_externos != 0:
        changes.append(f"externos {'+' if delta_externos > 0 else ''}{delta_externos}")
    if delta_hb > 1000:
        changes.append(f"+{delta_hb} heartbeats")

    # Detectar escenas nuevas en top 5
    old_scenes = {s["escena"] for s in prev.get("top_escenas", [])[:5]}
    new_scenes = {s["escena"] for s in report.get("top_escenas", [])[:5]}
    added = new_scenes - old_scenes
    if added:
        changes.append(f"🆕 {', '.join(sorted(added))}")

    if not changes:
        return ""  # Sin novedades — no reportar

    summary = f"📊 {tot['jugadores_unicos']} únicos | {est['estimado_jugadores_externos_reales']} externos | {tot['heartbeats_totales']} HBs"
    return summary + "\n↳ " + ", ".join(changes)


def main():
    parser = argparse.ArgumentParser(description="Estadísticas de telemetría desde ghosts.db")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"Ruta a ghosts.db (default: {DEFAULT_DB})")
    parser.add_argument("--json", action="store_true", help="Salida en JSON")
    parser.add_argument("--cron", action="store_true", help="Salida breve para cron")
    parser.add_argument("--state-file", default=DEFAULT_STATE_FILE, help="Archivo de estado persistente")
    args = parser.parse_args()
    run(args.db, args.json, args.cron, args.state_file)


if __name__ == "__main__":
    main()
