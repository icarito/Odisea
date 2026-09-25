#!/usr/bin/env python3
"""Resamplea un replay de Odisea de 60 Hz a otra tasa (30/20 Hz) para medir perf.

El replay es una lista de inputs por tick de fisica con compresion RLE
(`{"frame": N, "input": {...}}` + `{"hold": K}`), precedida por un snapshot
inicial. `SessionManager.expand_buffer()` la expande a un input por tick.

Para medir el frame a 30/20 Hz hace falta que la secuencia de inputs recorra el
MISMO camino en la MISMA duracion de simulacion, con menos ticks. `merge`
(por defecto) agrupa N ticks de origen en uno de salida:

  - analogos (move_vec, mouse_delta, zoom_delta) -> PROMEDIO del grupo. Si el
    paso del jugador pasa a 1/hz, el desplazamiento total del grupo se conserva.
  - booleanos -> OR (una pulsacion en cualquier tick del grupo sobrevive; con
    `hold`/`drop` los flancos que caen en ticks intermedios se perdian y el
    replay no abria la puerta del criopod).
  - valores discretos (fov_override, hud_slot, hud_nav, hud_widget_activate_slot)
    -> ultimo valor no nulo del grupo.

Los `events` (CALL/CINEMATIC/PRINT) se reindexan a la tasa nueva para que
disparen en el mismo instante de simulacion.

IMPORTANTE: correr el resultado con ODISEA_PHYSICS_FPS=<hz> **y**
ODISEA_REPLAY_PHYSICS_DT=1. Sin lo segundo el paso manual del jugador sigue a
1/60 por tick y el path deriva.

Uso:
    tools/resample_replay.py <in.json> <out.json> --hz 20
"""

import argparse
import json
import sys

SRC_HZ = 60
# move_vec se consume multiplicado por el dt del paso: con dt=1/hz (3x mayor) hay
# que PROMEDIAR para conservar el desplazamiento del grupo.
MEAN_KEYS = ("move_vec",)
# mouse_delta/zoom_delta se aplican por tick (yaw -= mouse_delta.x * sens, sin dt):
# hay que SUMAR para conservar la rotacion/zoom total del grupo.
SUM_KEYS = ("mouse_delta",)
SUM_FLOAT_KEYS = ("zoom_delta",)
LATCH_KEYS = ("fov_override", "hud_slot", "hud_nav", "hud_widget_activate_slot")


def expand(buffer):
    """Replica SessionManager.expand_buffer(): snapshot inicial + un input por tick."""
    expanded = []
    start = 0
    if buffer and isinstance(buffer[0], dict) and "snapshot" in buffer[0]:
        expanded.append(buffer[0])
        start = 1
    last = None
    for entry in buffer[start:]:
        if not isinstance(entry, dict):
            expanded.append(entry)
            continue
        if "hold" in entry:
            for _ in range(int(entry["hold"])):
                expanded.append({"input": json.loads(json.dumps(last)) if last is not None else None})
        elif "input" in entry:
            last = entry["input"]
            expanded.append({"input": last})
        else:
            expanded.append(entry)
    return expanded


def _mean_analog(key, values):
    nums = [v for v in values if isinstance(v, (int, float))]
    if not nums:
        return None
    return sum(nums) / float(len(nums))


def _mean_vec(values):
    xs = [v[0] for v in values if isinstance(v, list) and len(v) == 2]
    ys = [v[1] for v in values if isinstance(v, list) and len(v) == 2]
    if not xs:
        return None
    return [sum(xs) / float(len(xs)), sum(ys) / float(len(ys))]


def _sum_vec(values):
    xs = [v[0] for v in values if isinstance(v, list) and len(v) == 2]
    ys = [v[1] for v in values if isinstance(v, list) and len(v) == 2]
    if not xs:
        return None
    return [sum(xs), sum(ys)]


def merge_group(group):
    """Fusiona los inputs de un grupo de ticks de origen en uno de salida."""
    if all(g is None for g in group):
        return None
    live = [g for g in group if isinstance(g, dict)]
    keys = set()
    for g in live:
        keys.update(g.keys())
    out = {}
    for k in sorted(keys):
        vals = [g.get(k) for g in live if k in g]
        if k in MEAN_KEYS:
            merged = _mean_vec(vals)
            if merged is not None:
                out[k] = merged
        elif k in SUM_KEYS:
            merged = _sum_vec(vals)
            if merged is not None:
                out[k] = merged
        elif k in SUM_FLOAT_KEYS:
            nums = [v for v in vals if isinstance(v, (int, float))]
            if nums:
                out[k] = sum(nums)
        elif k in LATCH_KEYS:
            last = None
            for v in vals:
                if v is not None:
                    last = v
            out[k] = last
        else:
            # booleanos y flags: OR. Un flanco en cualquier tick sobrevive.
            out[k] = any(bool(v) for v in vals)
    return out


def merge_resample(flat, step):
    n_out = int(len(flat) / step)
    resampled = []
    for i in range(n_out):
        a = int(i * step)
        b = min(len(flat), int((i + 1) * step))
        resampled.append(merge_group(flat[a:b]))
    return resampled


def encode(snapshot, inputs):
    """Emite snapshot + prefijo neutro como hold + un input explicito por tick."""
    out = []
    if snapshot is not None:
        out.append({"snapshot": snapshot})
    start = 0
    while start < len(inputs) and inputs[start] is None:
        start += 1
    if start > 0:
        out.append({"hold": start})
    for i in range(start, len(inputs)):
        out.append({"frame": i, "input": inputs[i]})
    return out


def remap_events(events, step):
    if not isinstance(events, dict):
        return events
    out = {}
    for key, val in events.items():
        try:
            new_key = str(int(int(key) / step))
        except (TypeError, ValueError):
            new_key = str(key)
        if new_key in out:
            out[new_key] = out[new_key] + list(val)
        else:
            out[new_key] = list(val)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--hz", type=float, required=True)
    ap.add_argument("--src-hz", type=float, default=SRC_HZ)
    ap.add_argument("--mode", choices=["merge", "hold", "drop"], default="merge",
                    help="merge (default): promedio analogos + OR booleanos, mismo camino. "
                         "hold/drop: legacy, NO preservan el path a Hz != 60.")
    args = ap.parse_args()

    data = json.load(open(args.src))
    buffer = data.get("buffer", [])
    if not buffer:
        print("replay sin buffer", file=sys.stderr)
        return 1

    expanded = expand(buffer)
    snapshot = expanded[0]["snapshot"] if expanded and "snapshot" in expanded[0] else None
    flat = [e.get("input") for e in expanded[1:]] if snapshot is not None else [e.get("input") for e in expanded]
    total_ticks = len(flat)

    step = args.src_hz / float(args.hz)
    if args.mode == "merge":
        if abs(step - round(step)) > 1e-6:
            print("merge requiere un factor entero (src_hz/hz)", file=sys.stderr)
            return 1
        step = int(round(step))
        resampled = merge_resample(flat, step)
    else:
        n_out = int(total_ticks / step)
        resampled = []
        for i in range(n_out):
            src = min(total_ticks - 1, int(round(i * step)) if args.mode == "drop" else int(i / step))
            resampled.append(flat[src])

    out = dict(data)
    out["buffer"] = encode(snapshot, resampled)
    out["events"] = remap_events(data.get("events", {}), step)
    meta = dict(out.get("meta", {}))
    meta["resampled_from_hz"] = args.src_hz
    meta["resampled_to_hz"] = args.hz
    meta["resampled_src_ticks"] = total_ticks
    meta["resampled_mode"] = args.mode
    out["meta"] = meta

    with open(args.dst, "w") as f:
        json.dump(out, f, separators=(",", ":"))

    print("ticks %d -> %d (%.1f Hz, mode=%s), buffer %d -> %d entradas -> %s"
          % (total_ticks, len(resampled), args.hz, args.mode, len(buffer), len(out["buffer"]), args.dst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
