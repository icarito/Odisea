#!/usr/bin/env python3
"""Sincroniza meta_properties.size de las point classes con el AABB real del prop.

Insumo: el JSON que produce tools/qodot_audit_props.gd.

    godot3-bin --no-window -s tools/qodot_audit_props.gd
    python3 tools/qodot_sync_point_class_sizes.py --dry-run
    python3 tools/qodot_sync_point_class_sizes.py

Toca UNA sola linea de cada .tres (la del "size"); el resto del recurso queda igual.

Dos convenciones que es facil equivocar:

  * Qodot abusa de AABB en meta_properties["size"]: `position` guarda el MIN y `size`
    guarda el MAX, no la extension. build_def_text() los imprime crudos como
    `size(minx miny minz, maxx maxy maxz)`.
  * El .map es Z-up y Qodot mapea quake(x,y,z) -> godot(y,z,x), o sea
    quake.x = godot.z, quake.y = godot.x, quake.z = godot.y.
"""
import argparse
import math
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROPS_FGD = os.path.join(REPO, "core_v2", "qodot_fgd", "props", "*.tres")

SCALE = 16.0      # inverse_scale_factor de QodotMap
MIN_SPAN = 4.0    # 0.25 m: por debajo de esto la caja no se agarra en TrenchBroom
HUGE = 1024.0     # 64 m: se reporta para revision manual, no se corrige solo

SIZE_RE = re.compile(r'("size": )AABB\([^)]*\)')
EXT_RE = re.compile(r'\[ext_resource path="([^"]+)"[^\]]*id=(\d+)\]')


def quake_box(godot_aabb):
    px, py, pz, sx, sy, sz = godot_aabb
    gmin = (px, py, pz)
    gmax = (px + sx, py + sy, pz + sz)
    qmin = [gmin[2] * SCALE, gmin[0] * SCALE, gmin[1] * SCALE]
    qmax = [gmax[2] * SCALE, gmax[0] * SCALE, gmax[1] * SCALE]
    # A unidades enteras (1 u = 6.25 cm): de sobra para una caja de editor, y evita que
    # build_def_text() escupa -57.599998 en el .fgd. Se redondea hacia afuera para que
    # la caja nunca quede mas chica que el prop.
    qmin = [math.floor(v) for v in qmin]
    qmax = [math.ceil(v) for v in qmax]
    for i in range(3):
        if qmax[i] - qmin[i] < MIN_SPAN:
            c = (qmax[i] + qmin[i]) / 2.0
            qmin[i] = int(math.floor(c - MIN_SPAN / 2.0))
            qmax[i] = int(math.ceil(c + MIN_SPAN / 2.0))
    return qmin, qmax


def fmt_aabb(qmin, qmax):
    def n(v):
        return str(int(v)) if float(v).is_integer() else str(v)
    return "AABB( %s )" % ", ".join(n(v) for v in qmin + qmax)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", default="/tmp/qodot_props_audit.json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(args.audit):
        sys.exit("Falta %s. Corre antes:\n"
                 "  QODOT_AUDIT_OUT=%s godot3-bin --no-window -s tools/qodot_audit_props.gd"
                 % (args.audit, args.audit))

    audit = json.load(open(args.audit))
    changed = skipped = huge = 0

    for path in sorted(glob.glob(PROPS_FGD)):
        txt = open(path).read()
        name = os.path.basename(path)

        ext = {i: p for p, i in EXT_RE.findall(txt)}
        m_scene = re.search(r'^scene_file = ExtResource\( (\d+) \)', txt, re.M)
        m_size = SIZE_RE.search(txt)
        if not m_scene or not m_size:
            print("--  %-44s sin scene_file o sin size" % name)
            skipped += 1
            continue

        entry = audit.get(ext[m_scene.group(1)])
        box = entry.get("aabb_union") if entry else None
        if not box:
            print("--  %-44s sin medicion (emisor puro / geometria en runtime)" % name)
            skipped += 1
            continue

        qmin, qmax = quake_box(box)
        new = fmt_aabb(qmin, qmax)
        old = m_size.group(0).split("AABB", 1)[1]
        if max(qmax[i] - qmin[i] for i in range(3)) > HUGE:
            print("!!  %-44s caja > %.0f u (%s) — revisar a mano"
                  % (name, HUGE, new))
            huge += 1

        if ("AABB" + old) == new:
            continue

        print("FIX %-44s AABB%s -> %s" % (name, old, new))
        if not args.dry_run:
            open(path, "w").write(SIZE_RE.sub(lambda mo: mo.group(1) + new, txt, count=1))
        changed += 1

    print("\n%d corregidas, %d sin medicion, %d enormes%s"
          % (changed, skipped, huge, " (dry-run)" if args.dry_run else ""))


if __name__ == "__main__":
    main()
