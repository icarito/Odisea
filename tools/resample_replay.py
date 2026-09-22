#!/usr/bin/env python3
"""Resamplea un replay de Odisea de 60 Hz a otra tasa (30/20 Hz).

El replay es una lista de inputs por tick de fisica con compresion RLE
(`{"frame": N, "input": {...}}` + `{"hold": K}`), precedida por un snapshot
inicial. `SessionManager.expand_buffer()` la expande a un input por tick.

Para medir el frame a 30/20 Hz hace falta que la secuencia de inputs dure lo
mismo en tiempo real pero con menos ticks: se expande, se decima (cada 2do tick
para 30 Hz, cada 3ro para 20 Hz) y se vuelve a comprimir. El resultado es el
mismo recorrido visual en la misma duracion, con la mitad/tercio de ticks, que
es justo el workload de gameplay de esos tiers.

Uso:
    tools/resample_replay.py <in.json> <out.json> --hz 30
"""

import argparse
import json
import sys

SRC_HZ = 60


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


def encode(snapshot, inputs):
    """Emite snapshot + prefijo neutro como hold + un input explicito por tick.

    Sin RLE: una entrada por tick es lo mas simple de consumir y de auditar. El
    prefijo sin input (los primeros ticks tras el snapshot) va como un unico
    `hold` para que `expand_buffer` lo rellene con un InputDataV2 neutro, igual
    que el replay original.
    """
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--hz", type=float, required=True)
    ap.add_argument("--src-hz", type=float, default=SRC_HZ)
    ap.add_argument("--mode", choices=["hold", "drop"], default="hold",
                    help="hold: repite cada input de 60 Hz durante N ticks (conserva "
                         "los totales de mouse_delta/move_vec, misma trayectoria). "
                         "drop: toma 1 de cada N (pierde la mitad/tercio del input).")
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
    n_out = int(total_ticks / step)
    resampled = []
    for i in range(n_out):
        # hold: cada input de 60 Hz cubre 1/hz s (mismos totales). drop: 1 de cada N.
        src = min(total_ticks - 1, int(round(i * step)) if args.mode == "drop" else int(i / step))
        resampled.append(flat[src])

    out = dict(data)
    out["buffer"] = encode(snapshot, resampled)
    meta = dict(out.get("meta", {}))
    meta["resampled_from_hz"] = args.src_hz
    meta["resampled_to_hz"] = args.hz
    meta["resampled_src_ticks"] = total_ticks
    meta["resampled_mode"] = args.mode
    out["meta"] = meta
    # El estado final esperado ya no aplica (otra cadencia de ticks): se deja una
    # nota y el runner compara con tolerancia. Los tests de performance no dependen
    # del veredicto de drift.
    out["final_expected_state_note"] = "resampled to %g Hz: drift esperado, no valido para determinismo" % args.hz

    with open(args.dst, "w") as f:
        json.dump(out, f, separators=(",", ":"))

    print("ticks %d -> %d (%.1f Hz), buffer %d -> %d entradas -> %s"
          % (total_ticks, n_out, args.hz, len(buffer), len(out["buffer"]), args.dst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
