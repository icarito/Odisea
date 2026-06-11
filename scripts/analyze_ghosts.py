#!/usr/bin/env python3
"""
analyze_ghosts.py — Analiza ghosts grabados por el bridge central y performance_log.json.

Extrae:
- Zonas más visitadas por escena (agrupación por escena)
- Correlación FPS bajo + posición
- Objetos/zonas candidatas a optimización
- Tiempo de sesión por jugador

Uso:
    python3 scripts/analyze_ghosts.py <ghosts_dir>
    python3 scripts/analyze_ghosts.py --perflog <performance_log.json>

Ejemplo:
    python3 scripts/analyze_ghosts.py /home/ubuntu/anna-central/data/ghosts/
    python3 scripts/analyze_ghosts.py --perflog ~/.local/share/godot/app_userdata/Odisea/performance_log.json
"""

import sys
import os
import json
import glob
import csv
import argparse
from datetime import datetime
from collections import defaultdict, Counter
from statistics import mean, median, stdev


def load_ghosts(ghosts_dir: str):
    """Carga todos los ghosts de todas las sesiones."""
    records = []
    sessions = 0
    players = set()

    for player_dir in sorted(os.listdir(ghosts_dir)):
        player_path = os.path.join(ghosts_dir, player_dir)
        if not os.path.isdir(player_path):
            continue
        players.add(player_dir)

        for jsonl_file in sorted(os.listdir(player_path)):
            if not jsonl_file.endswith(".jsonl"):
                continue
            sessions += 1
            filepath = os.path.join(player_path, jsonl_file)
            with open(filepath, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        record = json.loads(line)
                        records.append(record)
                    except json.JSONDecodeError:
                        continue

    return records, players, sessions


def load_performance_log(filepath: str):
    """Carga un performance_log.json (un solo reporte de lag spike)."""
    records = []
    if not os.path.isfile(filepath):
        print(f"  ⚠ Archivo no encontrado: {filepath}")
        return records, set(), 0

    with open(filepath, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            print(f"  ⚠ JSON inválido en: {filepath}")
            return records, set(), 0

    schema = report.get("schema_version", 0)
    ts = report.get("timestamp", 0)
    fps = report.get("fps", 0)
    drop = report.get("drop", 0)
    scene = report.get("scene", "unknown")
    pos = report.get("player_position", [0, 0, 0])
    node_count = report.get("node_count", 0)
    draw_calls = report.get("draw_calls", 0)
    objects_in_frame = report.get("objects_in_frame", 0)
    vertices_in_frame = report.get("vertices_in_frame", 0)
    memory_mb = report.get("memory_mb", 0)
    process_ms = report.get("process_time_ms", 0)

    hb = {
        "type": "heartbeat",
        "player_id": "local",
        "timestamp": ts,
        "player": {
            "fps": fps,
            "scene": scene,
            "position": pos,
            "memory_mb": memory_mb,
        },
        "performance_log": {
            "drop": drop,
            "draw_calls": draw_calls,
            "objects_in_frame": objects_in_frame,
            "vertices_in_frame": vertices_in_frame,
            "node_count": node_count,
            "process_time_ms": process_ms,
            "schema_version": schema,
        }
    }
    records.append(hb)
    return records, {"local"}, 1


def analyze(records, players, sessions):
    print(f"\n{'='*60}")
    print(f"  ANALISIS DE GHOSTS — ODISEA BRIDGE CENTRAL")
    print(f"{'='*60}")
    print(f"\n  Jugadores unicos:  {len(players)}")
    print(f"  Sesiones totales:  {sessions}")
    print(f"  Frames grabados:   {len(records)}")
    print()

    hbs = [r for r in records if r.get("type") == "heartbeat" and "player" in r]
    if not hbs:
        print("  ⚠ No se encontraron heartbeats con datos de player.")
        return

    print(f"  Heartbeats con datos: {len(hbs)}")
    print()

    # --- 1. Escenas mas visitadas ---
    print(f"{'─'*60}")
    print("  1. ZONAS MAS VISITADAS")
    print(f"{'─'*60}")

    scene_counter = Counter()
    scene_fps = defaultdict(list)
    scene_memory = defaultdict(list)
    scene_time = defaultdict(float)

    for hb in hbs:
        p = hb.get("player", {})
        scene = p.get("scene", "unknown")
        scene_counter[scene] += 1
        fps = p.get("fps", 0)
        if fps > 0:
            scene_fps[scene].append(fps)
        mem = p.get("memory_mb", 0)
        if mem > 0:
            scene_memory[scene].append(mem)

    HEARTBEAT_INTERVAL_S = 0.1
    for hb in hbs:
        p = hb.get("player", {})
        scene = p.get("scene", "unknown")
        scene_time[scene] += HEARTBEAT_INTERVAL_S

    print(f"\n  {'Escena':<25} {'Frames':>8} {'Tiempo':>10} {'FPS avg':>8} {'FPS min':>8} {'Mem MB':>8}")
    print(f"  {'─'*25} {'─'*8} {'─'*10} {'─'*8} {'─'*8} {'─'*8}")
    for scene, count in scene_counter.most_common():
        fps_avg = mean(scene_fps[scene]) if scene_fps.get(scene) else 0
        fps_min = min(scene_fps[scene]) if scene_fps.get(scene) else 0
        mem_avg = mean(scene_memory[scene]) if scene_memory.get(scene) else 0
        time_s = scene_time.get(scene, 0)
        time_str = f"{int(time_s//60)}m{int(time_s%60):02d}s"
        print(f"  {scene:<25} {count:>8} {time_str:>10} {fps_avg:>8.1f} {fps_min:>8} {mem_avg:>8.1f}")

    # --- 2. Correlacion FPS bajo + escena ---
    print(f"\n{'─'*60}")
    print("  2. CORRELACION FPS BAJO + ESCENA")
    print(f"{'─'*60}")

    LOW_FPS_THRESHOLD = 20
    low_fps_events = [hb for hb in hbs if hb.get("player", {}).get("fps", 60) < LOW_FPS_THRESHOLD]

    if low_fps_events:
        low_fps_scenes = Counter()
        for hb in low_fps_events:
            scene = hb.get("player", {}).get("scene", "unknown")
            low_fps_scenes[scene] += 1

        print(f"\n  FPS < {LOW_FPS_THRESHOLD}: {len(low_fps_events)} frames ({len(low_fps_events)/max(len(hbs),1)*100:.1f}% del total)")
        print(f"\n  {'Escena':<25} {'Frames bajos':>14} {'% del total':>12}")
        print(f"  {'─'*25} {'─'*14} {'─'*12}")
        for scene, count in low_fps_scenes.most_common(5):
            total = scene_counter.get(scene, 1)
            print(f"  {scene:<25} {count:>14} {count/total*100:>11.1f}%")
    else:
        print(f"\n  ✅ Sin frames con FPS < {LOW_FPS_THRESHOLD}.")

    # --- Perflog extra info ---
    for hb in hbs:
        plog = hb.get("performance_log")
        if plog:
            print(f"\n{'─'*60}")
            print("  PERF LOG DETAILS")
            print(f"{'─'*60}")
            print(f"\n  Schema version:  {plog.get('schema_version')}")
            print(f"  FPS drop:        {plog.get('drop')}")
            print(f"  Draw calls:      {plog.get('draw_calls')}")
            print(f"  Objects in frame:{plog.get('objects_in_frame')}")
            print(f"  Vertices in frame:{plog.get('vertices_in_frame')}")
            print(f"  Node count:      {plog.get('node_count')}")
            print(f"  Process time ms: {plog.get('process_time_ms'):.2f}")
            break  # solo primer perflog

    # --- 3. Analisis de posicion en FPS bajo ---
    print(f"\n{'─'*60}")
    print("  3. POSICIONES EN FPS BAJO")
    print(f"{'─'*60}")

    if low_fps_events:
        position_grid = Counter()
        for hb in low_fps_events:
            pos = hb.get("player", {}).get("position", [0, 0, 0])
            grid_key = (round(pos[0] / 2) * 2, round(pos[1] / 2) * 2, round(pos[2] / 2) * 2)
            position_grid[grid_key] += 1

        print(f"\n  Top 10 hotspots de bajo rendimiento (grid 2m):")
        print(f"  {'Posicion (x, y, z)':<30} {'Eventos':>10}")
        print(f"  {'─'*30} {'─'*10}")
        for pos, count in position_grid.most_common(10):
            x, y, z = pos
            print(f"  ({x:>6.0f}, {y:>6.0f}, {z:>6.0f}){'':10} {count:>10}")

    # --- 4. Jugadores por escena ---
    print(f"\n{'─'*60}")
    print("  4. JUGADORES UNICOS POR ESCENA")
    print(f"{'─'*60}")

    scene_players = defaultdict(set)
    for hb in hbs:
        scene = hb.get("player", {}).get("scene", "unknown")
        pid = hb.get("player_id", "unknown")
        scene_players[scene].add(pid)

    print(f"\n  {'Escena':<25} {'Jugadores':>12}")
    print(f"  {'─'*25} {'─'*12}")
    for scene, pids in sorted(scene_players.items(), key=lambda x: -len(x[1])):
        print(f"  {scene:<25} {len(pids):>12}")

    # --- 5. Memoria por escena ---
    print(f"\n{'─'*60}")
    print("  5. USO DE MEMORIA POR ESCENA")
    print(f"{'─'*60}")

    print(f"\n  {'Escena':<25} {'Mem avg':>10} {'Mem max':>10} {'Mem min':>10}")
    print(f"  {'─'*25} {'─'*10} {'─'*10} {'─'*10}")
    for scene, mems in sorted(scene_memory.items(), key=lambda x: -mean(x[1])):
        print(f"  {scene:<25} {mean(mems):>10.1f} {max(mems):>10.1f} {min(mems):>10.1f}")

    # --- 6. RESUMEN ---
    print(f"\n{'─'*60}")
    print("  6. RECOMENDACIONES")
    print(f"{'─'*60}")
    print()

    problem_scenes = []
    for scene, fps_list in scene_fps.items():
        avg = mean(fps_list)
        mini = min(fps_list)
        if avg < 30 or mini < 15:
            problem_scenes.append((scene, avg, mini))

    if problem_scenes:
        print("  🚨 Escenas que necesitan optimizacion:")
        for scene, avg, mini in sorted(problem_scenes, key=lambda x: x[1]):
            print(f"     • {scene}: FPS avg {avg:.1f}, min {mini}")
    else:
        print("  ✅ Sin escenas problematicas (FPS avg > 30 en todas).")

    print()
    fpps = [hb.get("player", {}).get("fps", 60) for hb in hbs if hb.get("player", {}).get("fps", 0) > 0]
    if fpps:
        print(f"  📊 FPS global: avg {mean(fpps):.1f}, min {min(fpps)}, max {max(fpps)}")
        mem_readings = [hb.get("player", {}).get("memory_mb", 0) for hb in hbs if hb.get("player", {}).get("memory_mb", 0) > 0]
        if mem_readings:
            print(f"  📊 Memoria global: avg {mean(mem_readings):.1f} MB")
    print()

    print(f"{'='*60}")
    print(f"  Fin del analisis.")
    print(f"{'='*60}\n")


def generate_hotspot_mapping(records, output_file=None):
    """
    Groups heartbeats into 5m x 5m cells and analyzes performance (Prompt 2).
    """
    print(f"\n{'─'*60}")
    print("  HOTSPOT MAPPING (5m x 5m cells)")
    print(f"{'─'*60}")

    hbs = [r for r in records if r.get("type") == "heartbeat" and "player" in r]
    if not hbs:
        print("  ⚠ No heartbeats found for mapping.")
        return

    # scene -> (cell_x, cell_z) -> stats
    grid = defaultdict(lambda: defaultdict(lambda: {"total": 0, "low": 0, "fps_sum": 0}))
    CELL_SIZE = 5

    for hb in hbs:
        p = hb.get("player", {})
        scene = p.get("scene", "unknown")
        pos = p.get("position", [0, 0, 0])
        fps = p.get("fps", 60)

        cx = round(pos[0] / CELL_SIZE) * CELL_SIZE
        cz = round(pos[2] / CELL_SIZE) * CELL_SIZE

        cell = grid[scene][(cx, cz)]
        cell["total"] += 1
        if fps < 30:
            cell["low"] += 1
        cell["fps_sum"] += fps

    hotspots_data = []
    critical_hotspots = []

    for scene, cells in grid.items():
        for (cx, cz), stats in cells.items():
            total = stats["total"]
            low = stats["low"]
            pct_low = (low / total) * 100
            avg_fps = stats["fps_sum"] / total

            entry = {
                "scene": scene,
                "cell_x": cx,
                "cell_z": cz,
                "total_frames": total,
                "low_fps_frames": low,
                "pct_low": round(pct_low, 2),
                "avg_fps": round(avg_fps, 2)
            }
            hotspots_data.append(entry)

            if pct_low > 50:
                critical_hotspots.append(entry)

    # 1. List critical hotspots
    if critical_hotspots:
        print(f"\n  🚨 HOTSPOTS CRÍTICOS (>50% frames < 30 FPS):")
        print(f"  {'Escena':<20} {'Cell (X, Z)':<15} {'% Low':>8} {'Avg FPS':>8}")
        for h in sorted(critical_hotspots, key=lambda x: x["pct_low"], reverse=True)[:15]:
            print(f"  {h['scene']:<20} ({h['cell_x']:>4}, {h['cell_z']:>4}) {h['pct_low']:>7.1f}% {h['avg_fps']:>8.1f}")
    else:
        print("\n  ✅ No critical hotspots found.")

    # 2. Export CSV
    csv_filename = "hotspots.csv"
    try:
        with open(csv_filename, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=["scene", "cell_x", "cell_z", "total_frames", "low_fps_frames", "pct_low", "avg_fps"])
            writer.writeheader()
            writer.writerows(hotspots_data)
        print(f"\n  💾 CSV exportado: {csv_filename}")
    except Exception as e:
        print(f"\n  ❌ Error exportando CSV: {e}")

    # 3. Export JSON
    timestamp = int(datetime.now().timestamp())
    json_filename = output_file if output_file else f"hotspots_{timestamp}.json"
    try:
        with open(json_filename, 'w') as f:
            json.dump(hotspots_data, f, indent=2)
        print(f"  💾 JSON exportado: {json_filename}")
    except Exception as e:
        print(f"  ❌ Error exportando JSON: {e}")


def main():
    parser = argparse.ArgumentParser(description="Analyze Odisea ghost heartbeats.")
    parser.add_argument("ghosts_dir", nargs="?", default="/home/ubuntu/anna-central/data/ghosts/", help="Directory containing ghost JSONL files.")
    parser.add_argument("--perflog", help="Analyze a specific performance log JSON file.")
    parser.add_argument("--output", "-o", help="Specific JSON output file for hotspots.")
    args = parser.parse_args()

    if args.perflog:
        print(f"  Cargando performance log desde: {args.perflog}")
        records, players, sessions = load_performance_log(args.perflog)
    else:
        ghosts_dir = args.ghosts_dir
        if not os.path.isdir(ghosts_dir):
            print(f"  ❌ Directorio no encontrado: {ghosts_dir}")
            sys.exit(1)
        print(f"  Cargando ghosts desde: {ghosts_dir}")
        records, players, sessions = load_ghosts(ghosts_dir)

    analyze(records, players, sessions)
    generate_hotspot_mapping(records, args.output)


if __name__ == "__main__":
    main()
