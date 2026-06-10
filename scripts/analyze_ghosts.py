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


def main():
    if len(sys.argv) < 2:
        ghosts_dir = "/home/ubuntu/anna-central/data/ghosts/"
        print(f"  Usando directorio por defecto: {ghosts_dir}")
        print(f"  Uso alternativo: python3 {sys.argv[0]} <ghosts_dir>")
        print(f"  O con performance_log: python3 {sys.argv[0]} --perflog <path>")
        print()
    elif sys.argv[1] == "--perflog":
        perf_log_path = sys.argv[2] if len(sys.argv) > 2 else None
        if not perf_log_path:
            print("  Uso: python3 analyze_ghosts.py --perflog <performance_log.json>")
            sys.exit(1)
        print(f"  Cargando performance log desde: {perf_log_path}")
        records, players, sessions = load_performance_log(perf_log_path)
        analyze(records, players, sessions)
        return
    else:
        ghosts_dir = sys.argv[1]

    if not os.path.isdir(ghosts_dir):
        print(f"  ❌ Directorio no encontrado: {ghosts_dir}")
        sys.exit(1)

    print(f"  Cargando ghosts desde: {ghosts_dir}")
    records, players, sessions = load_ghosts(ghosts_dir)
    analyze(records, players, sessions)


if __name__ == "__main__":
    main()
