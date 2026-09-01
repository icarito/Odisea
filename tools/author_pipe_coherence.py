#!/usr/bin/env python3
"""author_pipe_coherence.py — Coherencia del circuito de frio (Dome_Intro).

Problemas que corrige:
1. Ramal muerto por piso: cada linea de piso iba de az 264->105 (oeste) / 84->285
   (este) y el tramo detras del riser (az 180->264 / 0->84, ~7.3 m por piso)
   terminaba capitoneado sin nada conectado. Se recorta a az 189->105 (L1_Ring,
   conserva la T del hub CryoLoop en az 189) y az 180->105 (L2..L5_Ring).
2. Stub V5-top (Route2 de L5_Ring): subia desde la linea del piso 6 hasta 24.15
   en Rail-B con la valvula F5 montada en la punta. F5 no esta en la red
   (PipeNetworkResource no la referencia): girarla no movia nada. Se borra el
   stub del source y las dos valvulas F5 de Dome_Intro.
3. ValveInterlink: quedo suelto cuando se elimino la interconexion oeste-este.
   No pertenece a ninguna rama de la red. Se borra de Dome_Intro.
4. Fugas huerfanas: Leak{West,East}Ring0 (y=0, debajo de F0: si activara seria
   indetenerable) y Leak{West,East}Floor5 (flotaban a la altura vieja 22.08,
   sin referencia en la red). Se borran con sus Patch/FissureVisual.
5. Fugas cableadas a la altura vieja: Ring1..5 y Floor2..4 quedaron 0.52 m por
   debajo de las lineas serpentina (4.6/9.1/13.6/18.1/22.6). Se realinean.
6. Colisiones stale: los Collision_0..22 de cada anillo son cilindros del
   diseno VIEJO (semicirculo az 90..270 a y vieja). Se regeneran desde las
   rutas recortadas (cylinder r=0.2 por segmento, altura = cuerda).

Uso: python3 tools/author_pipe_coherence.py [--apply]
Sin --apply escribe los cambios en /tmp/kilo y no toca el repo.
"""
import math
import re
import sys

SRC = "core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
DOME = "core_v2/levels/interiors/Dome_Intro.tscn"

APPLY = "--apply" in sys.argv

UP = (0.0, 1.0, 0.0)


def fmt(v: float) -> str:
    s = "%.8g" % v
    return s


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    return (v[0] / l, v[1] / l, v[2] / l) if l > 1e-9 else (0.0, 1.0, 0.0)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def parse_puntos(raw: str):
    nums = [float(x) for x in raw.split(",")]
    return [(nums[i], nums[i + 1], nums[i + 2]) for i in range(0, len(nums), 3)]


def fmt_puntos(pts):
    flat = []
    for p in pts:
        flat += [fmt(p[0]), fmt(p[1]), fmt(p[2])]
    return ", ".join(flat)


# ---------------------------------------------------------------- source ----
def trim_source(text: str) -> str:
    for side in ("TowerCoolantRiser", "TowerCoolantRiserEast"):
        for n in range(1, 6):
            keep = 5 if n == 1 else 6
            group = f"{side}/{side}_L{n}_Ring"
            text = _trim_route_block(text, group, keep)
    # borrar Route2 de L5_Ring (stub V5-top con la valvula F5 muerta, ambas torres)
    for side in ("TowerCoolantRiser", "TowerCoolantRiserEast"):
        pat = re.compile(
            r'\[node name="Route2" type="Spatial" parent="' + re.escape(side) + '/' + re.escape(side) + r'_L5_Ring"\]\n'
            r'script = ExtResource\( 10 \)\n'
            r'puntos = PoolVector3Array\([^)]*\)\n\n?')
        text, cnt = pat.subn("", text)
        if cnt != 1:
            print(f"FALTA Route2 en {side}_L5_Ring (borre {cnt})")
            sys.exit(1)
    return text


def _trim_route_block(text: str, group: str, keep: int) -> str:
    """Recorta la ruta del anillo a los puntos [keep..] y renumera sus tes."""
    hdr = f'[node name="Route" type="Spatial" parent="{group}"]'
    start = text.index(hdr)
    end = text.index("\n[", start + 1) + 1
    block = text[start:end]
    tes_m = re.search(r"tes = PoolIntArray\( ([^)]*) \)", block)
    pts_m = re.search(r"puntos = PoolVector3Array\(([^)]*)\)", block)
    old_tes = [int(x) for x in tes_m.group(1).split(",")]
    pts = parse_puntos(pts_m.group(1))
    new_pts = pts[keep:]
    new_tes = [v - keep for v in old_tes]
    new_block = re.sub(
        r"tes = PoolIntArray\( [^)]* \)",
        "tes = PoolIntArray( " + ", ".join(str(t) for t in new_tes) + " )",
        block)
    new_block = re.sub(
        r"puntos = PoolVector3Array\([^)]*\)",
        "puntos = PoolVector3Array( " + fmt_puntos(new_pts) + " )",
        new_block)
    return text[:start] + new_block + text[end:]


def fmt_puntos_field(tes):
    return ", ".join(str(t) for t in tes)


# ------------------------------------------------------------ dome intro ----
NODE_RE = re.compile(r'\[node name="([^"]+)"[^\]]*?parent="([^"]*)"[^\]]*\]')


def parse_nodes(text: str):
    """[(line_idx, name, parent)] de todos los headers."""
    out = []
    for m in NODE_RE.finditer(text):
        out.append((m.start(), m.group(1), m.group(2)))
    return out


def delete_family(text: str, parent: str, name: str) -> str:
    """Borra el nodo `name` (hijo de `parent`) y todo su subarbol."""
    nodes = parse_nodes(text)
    target = None
    for idx, (pos, n, p) in enumerate(nodes):
        if n == name and p == parent:
            target = idx
            break
    if target is None:
        print(f"FALTA nodo {parent}/{name}")
        sys.exit(1)
    start_pos = nodes[target][0]
    # fin = proximo header que no sea descendiente
    end_pos = len(text)
    for pos, n, p in nodes[target + 1:]:
        if not p.startswith(f"{parent}/{name}"):
            end_pos = pos
            break
    return text[:start_pos] + text[end_pos:]


def delete_node_exact(text: str, parent: str, name: str) -> str:
    """Como delete_family pero sin subarbol: borra hasta el proximo header."""
    nodes = parse_nodes(text)
    for idx, (pos, n, p) in enumerate(nodes):
        if n == name and p == parent:
            end_pos = nodes[idx + 1][0] if idx + 1 < len(nodes) else len(text)
            return text[:pos] + text[end_pos:]
    print(f"FALTA nodo exacto {parent}/{name}")
    sys.exit(1)


def retarget_leak_y(text: str, parent: str, name: str, new_y: float) -> str:
    """Ajusta solo la Y del transform del nodo."""
    pat = re.compile(
        r'(\[node name="' + re.escape(name) + r'" type="Spatial" parent="' + re.escape(parent) + r'"\]\n'
        r'transform = Transform\( )([^)]*?)( \))'
    )
    m = pat.search(text)
    if not m:
        print(f"FALTA transform de {parent}/{name}")
        sys.exit(1)
    nums = [float(x) for x in m.group(2).split(",")]
    nums[10] = new_y
    new_t = ", ".join(fmt(x) for x in nums)
    return text[:m.start()] + m.group(1) + new_t + m.group(3) + text[m.end():]


def shape_id_for(text: str, side: str, n: int) -> str:
    """El id del CylinderShape que usaban las colisiones viejas del anillo."""
    ring_node = f"{side}/{side}_L{n}_Ring"
    pat = re.compile(
        r'\[node name="Collision_0" type="CollisionShape" parent="' + re.escape(ring_node) + r'/StaticBody"\]\n'
        r'transform = [^\n]*\n'
        r'shape = SubResource\( (\d+) \)')
    m = pat.search(text)
    return m.group(1) if m else "533"


def replace_ring_collisions(text: str, side: str, n: int, route_pts, shape_id: str) -> str:
    """Borra los Collision_* del anillo y mete uno por segmento de la ruta trimmeada."""
    ring_node = f"{side}/{side}_L{n}_Ring"
    # 1. borrar los Collision_* existentes bajo <ring>/StaticBody
    nodes = parse_nodes(text)
    start = None
    for idx, (pos, nm, p) in enumerate(nodes):
        if nm.startswith("Collision_") and p == f"{ring_node}/StaticBody":
            if start is None:
                start = idx
        elif start is not None and not p.startswith(f"{ring_node}/StaticBody"):
            end = pos
            text = text[:nodes[start][0]] + text[end:]
            break
    # 2. generar nuevos
    pts = route_pts
    blocks = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        chord = math.dist(a, b)
        if chord < 1e-4:
            continue
        d = norm(sub(b, a))
        s = chord * 0.5
        y_img = mul(d, s)
        x_img = norm(cross(UP, d))
        z_img = norm(cross(x_img, y_img))
        mid = mul(add(a, b), 0.5)
        row0 = (x_img[0], y_img[0], z_img[0])
        row1 = (x_img[1], y_img[1], z_img[1])
        row2 = (x_img[2], y_img[2], z_img[2])
        nums = list(row0) + list(row1) + list(row2) + [mid[0], mid[1], mid[2]]
        tr = ", ".join(fmt(v) for v in nums)
        blocks.append(
            f'[node name="Collision_{i}" type="CollisionShape" parent="{ring_node}/StaticBody"]\n'
            f"transform = Transform( {tr} )\n"
            f"shape = SubResource( {shape_id} )\n"
        )
    # insertar despues del header del StaticBody del anillo
    anchor = f'[node name="StaticBody" parent="{ring_node}" instance='
    m = re.search(re.escape(anchor), text)
    if not m:
        print(f"FALTA StaticBody de {ring_node}")
        sys.exit(1)
    insert_at = text.index("\n", m.start()) + 1
    return text[:insert_at] + "".join(blocks) + text[insert_at:]


def main() -> None:
    src = open(SRC).read()
    dome = open(DOME).read()

    # --- 1. rutas recortadas en el source
    src = trim_source(src)

    # --- 2. Dome_Intro: nodos huerfanos fuera
    for parent, name in [
        (".", "ValveInterlink"),
        ("TowerCoolantRiser", "ValveWestFloor5"),
        ("TowerCoolantRiserEast", "ValveEastFloor5"),
        ("TowerCoolantRiser", "LeakWestRing0"),
        ("TowerCoolantRiser", "LeakWestRing0_Patch"),
        ("TowerCoolantRiserEast", "LeakEastRing0"),
        ("TowerCoolantRiserEast", "LeakEastRing0_Patch"),
        ("TowerCoolantRiser", "LeakWestFloor5"),
        ("TowerCoolantRiser", "LeakWestFloor5_Patch"),
        ("TowerCoolantRiserEast", "LeakEastFloor5"),
        ("TowerCoolantRiserEast", "LeakEastFloor5_Patch"),
    ]:
        dome = delete_family(dome, parent, name)

    # --- 3. fugas cableadas a la altura nueva de linea
    line_y = {1: 4.6, 2: 9.1, 3: 13.6, 4: 18.1, 5: 22.6}
    for side in ("West", "East"):
        tower = "TowerCoolantRiser" if side == "West" else "TowerCoolantRiserEast"
        for n in range(1, 6):
            dome = retarget_leak_y(dome, tower, f"Leak{side}Ring{n}", line_y[n])
        for n in (2, 3, 4):
            dome = retarget_leak_y(dome, tower, f"Leak{side}Floor{n}", line_y[n])

    # --- 4. colisiones de anillo regeneradas desde las rutas trimmeadas
    for side in ("TowerCoolantRiser", "TowerCoolantRiserEast"):
        for n in range(1, 6):
            # puntos trimmeados: mismos que en el source (el trim ya corrio)
            pat = re.compile(
                r'\[node name="Route" type="Spatial" parent="' + re.escape(side) + '/' + re.escape(side) + f'_L{n}' + r'_Ring"\]\n'
                r'script = ExtResource\( 10 \)\n[^[]*?puntos = PoolVector3Array\(([^)]*)\)')
            m = pat.search(src)
            pts = parse_puntos(m.group(1))
            shape_id = shape_id_for(dome, side, n)
            dome = replace_ring_collisions(dome, side, n, pts, shape_id)

    if APPLY:
        open(SRC, "w").write(src)
        open(DOME, "w").write(dome)
        print("APLICADO a repo")
    else:
        open("/tmp/kilo/DomeIntro_PipeNetworkSource.coherence.tscn", "w").write(src)
        open("/tmp/kilo/Dome_Intro.coherence.tscn", "w").write(dome)
        print("preview en /tmp/kilo/*.coherence.tscn")

    # resumen
    for label, t in (("source", src), ("dome", dome)):
        bad = [x for x in ("ValveInterlink", "LeakWestRing0", "LeakEastRing0",
                           "LeakWestFloor5", "LeakEastFloor5",
                           "ValveWestFloor5", "ValveEastFloor5") if x in t and label == "dome"]
        print(label, "residuos:", bad if bad else "ninguno")


if __name__ == "__main__":
    main()
