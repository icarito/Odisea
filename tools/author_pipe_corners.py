#!/usr/bin/env python3
"""author_pipe_corners.py — Convierte los tes de extremo de cada anillo en patas
de polilinea, para que PipeRoute coloque un codo del kit en vez de una T con el
tercer porto colgando hacia el vacio.

En el diseno original cada anillo cerraba en si mismo y las uniones con los
verticales eran T verdaderas (linea que sigue de un lado, rama al otro). Con la
serpentina el anillo dejo de cerrar: sus extremos son ahora la T de Rail-A (el
riser pasa de largo) y el fin de linea en Rail-B. El T en punta dibuja el bloque
de 3 puertos con un porton al aire; la geometria correcta es codo + pata corta
que empalma contra el cap del vertical o del bucle.
"""

import math
import re
import sys

SRC = "core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
STUB = 0.392

# (parent, rama del T en el primer punto, rama del T en el ultimo punto)
# None = ese extremo no tiene T (fin de linea a tope).
GROUPS = [
    ("TowerCoolantRiser/TowerCoolantRiser_L1_Ring", (0.987688, 0.0, 0.156434), (0.0, 1.0, 0.0)),
    ("TowerCoolantRiser/TowerCoolantRiser_L2_Ring", (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)),
    ("TowerCoolantRiser/TowerCoolantRiser_L3_Ring", (0.0, -1.0, 0.0), (0.0, 1.0, 0.0)),
    ("TowerCoolantRiser/TowerCoolantRiser_L4_Ring", (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)),
    ("TowerCoolantRiser/TowerCoolantRiser_L5_Ring", (0.0, -1.0, 0.0), None),
    ("TowerCoolantRiserEast/TowerCoolantRiserEast_L1_Ring", (-0.970296, 0.0, -0.241922), (0.0, 1.0, 0.0)),
    ("TowerCoolantRiserEast/TowerCoolantRiserEast_L2_Ring", (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)),
    ("TowerCoolantRiserEast/TowerCoolantRiserEast_L3_Ring", (0.0, -1.0, 0.0), (0.0, 1.0, 0.0)),
    ("TowerCoolantRiserEast/TowerCoolantRiserEast_L4_Ring", (0.0, 1.0, 0.0), (0.0, -1.0, 0.0)),
    ("TowerCoolantRiserEast/TowerCoolantRiserEast_L5_Ring", (0.0, -1.0, 0.0), None),
]


def parse_pts(raw):
    nums = [float(x) for x in raw.split(",")]
    return [(nums[i], nums[i + 1], nums[i + 2]) for i in range(0, len(nums), 3)]


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (v[0] / l, v[1] / l, v[2] / l) if l > 1e-9 else (0.0, 1.0, 0.0)


def fmt_pts(pts):
    return ", ".join("%.8g" % v for p in pts for v in p)


def main():
    src = open(SRC).read()
    for parent, rama_first, rama_last in GROUPS:
        hdr = f'[node name="Route" type="Spatial" parent="{parent}"]'
        start = src.index(hdr)
        nl = src.find("\n[", start + 1)
        end = (nl + 1) if nl != -1 else len(src)
        body = src[start:end]
        tes_m = re.search(r"tes = PoolIntArray\( ([^)]*) \)", body)
        ramas_m = re.search(r"tes_ramas = PoolVector3Array\( ([^)]*) \)", body)
        pts_m = re.search(r"puntos = PoolVector3Array\( ([^)]*) \)", body)
        if pts_m is None:
            print(f"FALTA puntos en {parent}")
            sys.exit(1)
        old_tes = [int(x) for x in tes_m.group(1).split(",") if x.strip()] if tes_m else []
        ramas = split_ramas(ramas_m.group(1)) if ramas_m else []
        pts = parse_pts(pts_m.group(1))
        n = len(pts)
        # Idempotencia: si ya hay pata, el primer/ultimo punto se desvia del anillo r=12.
        r0 = math.hypot(pts[0][0], pts[0][2])
        rl = math.hypot(pts[-1][0], pts[-1][2])
        if r0 > 12.2 or rl > 12.2:
            print(f"SALTA {parent}: ya tiene patas (r0={r0:.3f}, rl={rl:.3f})")
            continue
        new_pts = list(pts)
        new_tes = []
        new_ramas = []
        for i, rama in zip(old_tes, ramas):
            if i == 0:
                if rama_first:
                    new_pts.insert(0, add(pts[0], mul(norm(rama_first), STUB)))
            elif i == n - 1:
                if rama_last:
                    new_pts.append(add(pts[-1], mul(norm(rama_last), STUB)))
            else:
                new_tes.append(i + (1 if rama_first else 0))
                new_ramas.append(rama)
        # bloque nuevo desde cero: sin tes si quedo vacio
        lines = [hdr, "script = ExtResource( 10 )"]
        if new_tes:
            lines.append("tes = PoolIntArray( " + ", ".join(str(t) for t in new_tes) + " )")
            flat = []
            for r in new_ramas:
                flat += ["%.8g" % v for v in r]
            lines.append("tes_ramas = PoolVector3Array( " + ", ".join(flat) + " )")
        lines.append("puntos = PoolVector3Array( " + fmt_pts(new_pts) + " )")
        src = src[:start] + "\n".join(lines) + "\n" + src[end:]
        print(f"OK {parent}: pts={len(new_pts)} tes={new_tes}")
    open(SRC, "w").write(src)


def fmt_tes(tes):
    # contenido pelado: el wrapper "PoolIntArray( ... )" ya viene en los grupos
    return ", ".join(str(t) for t in tes)


def fmt_ramas(ramas):
    flat = []
    for r in ramas:
        flat += ["%.8g" % v for v in r]
    return ", ".join(flat)


def split_ramas(raw):
    # PoolVector3Array plano: 3 floats por Vector3, sin separadores propios.
    nums = [float(x) for x in raw.split(",")]
    return [tuple(nums[i:i + 3]) for i in range(0, len(nums), 3)]


if __name__ == "__main__":
    main()
