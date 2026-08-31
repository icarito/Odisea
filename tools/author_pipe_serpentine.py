#!/usr/bin/env python3
"""author_pipe_serpentine.py — Reescribe la red de canerias de Dome_Intro como
serpentina de dos rieles (FD-270 v5).

Diseno (torre oeste; este = rotacion 180 grados):
- Riel A: az 180  (-12, y, 0)        — verticales V0/V2/V4 con valvulas F0/F2/F4.
- Riel B: az 105  (-3.10582, y, 11.59111) — verticales V1/V3/V5 con F1/F3/F5
  (rosa la ventana libre G1 [100,127] en todos los pisos).
- Cada piso = linea unica az [264..105] con T en az 180 (vertical) y T de
  extremo en az 105 (vertical); el tramo az 180..264 queda como ramal muerto
  con punta capitoneada implicita (fin de ruta).
- Flujo: V0 -> linea piso2 -> V1 -> linea piso3 -> V2 -> ... -> V5 (punta).
- Las ramas de hub (CryoLoop*) cuelgan radiales de la linea de piso 2 (az 189/14).
- Valvulas: F0/F2/F4 quedan en su lugar (az 180/0); F1/F3/F5 se mudan al riel B.
- Leaks de tronco (FloorN) se recolocan ENCIMA de la valvula de su run;
  leaks de anillo (RingN) sobre el brazo troncal de su piso (az 145/325).

Uso: python3 tools/author_pipe_serpentine.py [--dry]
"""
import re
import sys
import math

SRC = "core_v2/levels/interiors/DomeIntro_PipeNetworkSource.tscn"
MAIN = "core_v2/levels/interiors/Dome_Intro.tscn"

R = 12.0
STUB = 0.098 * 4.0  # vastago de T: vertice + rama * 0.098 * grosor

def pt(az_deg: float, y: float) -> tuple:
    a = math.radians(az_deg)
    return (round(R * math.cos(a), 5), y, round(R * math.sin(a), 5))

def fmt_pts(pts) -> str:
    flat = []
    for p in pts:
        flat += [f"{p[0]:.5f}", f"{p[1]:.5f}", f"{p[2]:.5f}"]
    return "PoolVector3Array( " + ", ".join(flat) + "  )"

AZ_W = [264, 249, 234, 219, 204, 189, 180, 165, 150, 135, 120, 105]
AZ_E = [84, 70, 56, 42, 28, 14, 0, 345, 330, 315, 300, 285]

# ramas por piso: (rama_en_az180, rama_en_extremo_az105|285)
BRANCH_W = {2: ((0, -1, 0), (0, 1, 0)), 3: ((0, 1, 0), (0, -1, 0)),
            4: ((0, -1, 0), (0, 1, 0)), 5: ((0, 1, 0), (0, -1, 0)),
            6: ((0, -1, 0), (0, 1, 0))}
BRANCH_E = dict(BRANCH_W)
HUB_W = (0.987688, 0, 0.156434)    # inward az 189
HUB_E = (-0.970296, 0, -0.241922)  # inward az 14

Y = {2: 4.6, 3: 9.1, 4: 13.6, 5: 18.1, 6: 22.6}
SLOTS = {0: (1.65, 3.25), 1: (6.15, 7.75), 2: (10.65, 12.25),
         3: (15.15, 16.75), 4: (19.65, 21.25), 5: (24.15, 25.75)}

def v_routes(az: tuple, floor_lo: int, floor_hi: int, valve: int):
    """Rutas del vertical entre piso floor_lo y floor_hi con slot de valvula."""
    x, z = az
    lo, hi = Y[floor_lo], Y[floor_hi]
    s_lo, s_hi = SLOTS[valve]
    out = []
    b = lo + (STUB if floor_lo != 0 else 0.0)
    if floor_lo == 0:
        out.append({"pts": [(x, 0.0, z), (x, s_lo, z)]})
    else:
        out.append({"pts": [(x, b, z), (x, s_lo, z)]})
    t = hi - STUB
    out.append({"pts": [(x, s_hi, z), (x, t, z)]})
    return out

def line_route(azs, y, tes, ramas):
    return {"tes": tes, "ramas": ramas, "pts": [pt(a, y) for a in azs]}

W_RAIL_A = (-12.0, 0.0)
W_RAIL_B = (-3.10582, 11.59111)
E_RAIL_A = (12.0, 0.0)
E_RAIL_B = (3.10582, -11.59111)

def build_source_routes():
    """Devuelve dict parent_path -> lista de bloques Route (props completos)."""
    routes = {}
    # Oeste: verticales
    routes["TowerCoolantRiser/TowerCoolantRiser_L1"] = [
        {"pts": [(W_RAIL_A[0], 0.0, 0.0), (W_RAIL_A[0], SLOTS[0][0], 0.0)]},
        {"pts": [(W_RAIL_A[0], SLOTS[0][1], 0.0), (W_RAIL_A[0], 4.208, 0.0)]},
    ]
    for floor in (2, 3, 4, 5):
        valve = floor - 1
        rail = W_RAIL_A if floor % 2 == 1 else W_RAIL_B  # V2(180) V3(105) V4(180)... floor2->V1(105)
        rail = W_RAIL_B if floor % 2 == 0 else W_RAIL_A
        routes[f"TowerCoolantRiser/TowerCoolantRiser_L{floor}"] = v_routes(
            rail, floor, floor + 1, valve)
    # Oeste: lineas de piso (el nodo L{floor-1}_Ring contiene la linea del piso `floor`)
    for floor in (2, 3, 4, 5, 6):
        b180, bend = BRANCH_W[floor]
        tes = [6, 11]
        ramas = [b180, bend]
        if floor == 2:
            tes = [5, 6, 11]
            ramas = [HUB_W, b180, bend]
        routes[f"TowerCoolantRiser/TowerCoolantRiser_L{floor - 1}_Ring"] = [
            {"tes": tes, "ramas": ramas, "pts": [pt(a, Y[floor]) for a in AZ_W]}
        ] + ([{"pts": [(W_RAIL_B[0], 22.992, W_RAIL_B[1]),
                       (W_RAIL_B[0], SLOTS[5][0], W_RAIL_B[1])]}] if floor == 6 else [])
    # Este: verticales
    routes["TowerCoolantRiserEast/TowerCoolantRiserEast_L1"] = [
        {"pts": [(E_RAIL_A[0], 0.0, 0.0), (E_RAIL_A[0], SLOTS[0][0], 0.0)]},
        {"pts": [(E_RAIL_A[0], SLOTS[0][1], 0.0), (E_RAIL_A[0], 4.208, 0.0)]},
    ]
    for floor in (2, 3, 4, 5):
        valve = floor - 1
        rail = E_RAIL_B if floor % 2 == 0 else E_RAIL_A
        routes[f"TowerCoolantRiserEast/TowerCoolantRiserEast_L{floor}"] = v_routes(
            rail, floor, floor + 1, valve)
    for floor in (2, 3, 4, 5, 6):
        b180, bend = BRANCH_E[floor]
        tes = [6, 11]
        ramas = [b180, bend]
        if floor == 2:
            tes = [5, 6, 11]
            ramas = [HUB_E, b180, bend]
        routes[f"TowerCoolantRiserEast/TowerCoolantRiserEast_L{floor - 1}_Ring"] = [
            {"tes": tes, "ramas": ramas, "pts": [pt(a, Y[floor]) for a in AZ_E]}
        ] + ([{"pts": [(E_RAIL_B[0], 22.992, E_RAIL_B[1]),
                       (E_RAIL_B[0], SLOTS[5][0], E_RAIL_B[1])]}] if floor == 6 else [])
    return routes

def route_block(parent: str, data: dict, name: str = "Route") -> str:
    s = f'\n[node name="{name}" type="Spatial" parent="{parent}"]\n'
    s += "script = ExtResource( 10 )\n"
    if "tes" in data:
        s += "tes = PoolIntArray( " + ", ".join(str(i) for i in data["tes"]) + " )\n"
        r = []
        for v in data["ramas"]:
            r += [f"{v[0]:.6f}", f"{v[1]:.6f}", f"{v[2]:.6f}"]
        s += "tes_ramas = PoolVector3Array( " + ", ".join(r) + " )\n"
    s += "puntos = " + fmt_pts(data["pts"]) + "\n"
    return s

# ---- flow_dir por run node (fallback visual; el bake hornea eje por vertice) ----
T_W_ODD = (-0.965926, 0, -0.258819)   # entrada az 105 hacia az creciente
T_W_EVEN = (0.0, 0, 1.0)              # entrada az 180 hacia az decreciente
T_E_ODD = (0.965926, 0, 0.258819)
T_E_EVEN = (0.0, 0, -1.0)

FLOW_DIRS = {}
for f in (1, 2, 3, 4, 5):
    FLOW_DIRS[f"TowerCoolantRiser/TowerCoolantRiser_L{f}"] = (0, 1, 0)
    FLOW_DIRS[f"TowerCoolantRiserEast/TowerCoolantRiserEast_L{f}"] = (0, 1, 0)
for f in (2, 3, 4, 5, 6):
    k = (f - 2) % 2  # 0 = par (riel A arriba), 1 = impar
    FLOW_DIRS[f"TowerCoolantRiser/TowerCoolantRiser_L{f - 1}_Ring"] = T_W_EVEN if k == 0 else T_W_ODD
    FLOW_DIRS[f"TowerCoolantRiserEast/TowerCoolantRiserEast_L{f - 1}_Ring"] = T_E_EVEN if k == 0 else T_E_ODD

# ---- CryoLoop hub runs: radiales desde la linea de piso 2 ----
def hub_transform(vertex_az: float, inward: tuple) -> str:
    v = pt(vertex_az, 4.6)
    start = (v[0] + STUB * inward[0], 4.6, v[2] + STUB * inward[2])
    mid = (start[0] + 3.0 * inward[0], 4.6, start[2] + 3.0 * inward[2])
    xax = inward
    yax = (0, 1, 0)
    zax = (xax[1] * yax[2] - xax[2] * yax[1],
           xax[2] * yax[0] - xax[0] * yax[2],
           xax[0] * yax[1] - xax[1] * yax[0])
    nums = [xax[0], yax[0], zax[0], xax[1], yax[1], zax[1],
            xax[2], yax[2], zax[2], mid[0], mid[1], mid[2]]
    return "Transform( " + ", ".join(f"{n:.5f}" for n in nums) + " )"

HUB_W_TF = hub_transform(189, HUB_W)
HUB_E_TF = hub_transform(14, HUB_E)

def valve_tf(az: float, y: float) -> str:
    c, s = math.cos(math.radians(az)), math.sin(math.radians(az))
    xax = (-s, 0.0, c)           # tangente
    yax = (0.0, 1.0, 0.0)
    zax = (-c, 0.0, -s)          # inward
    nums = [xax[0], yax[0], zax[0], xax[1], yax[1], zax[1],
            xax[2], yax[2], zax[2], R * c, y, R * s]
    return "Transform( " + ", ".join(f"{n:.6f}" for n in nums) + " )"

# ---- reescritura genérica de bloques [node ...] ----
NODE_RE = re.compile(r"\n?\[node name=\"([^\"]+)\" type=\"Spatial\" parent=\"([^\"]*)\"\][^\[]*?(?=\n\[node|\Z)", re.S)

def rewrite_source(txt: str) -> str:
    routes = build_source_routes()
    # 0) eliminar valvulas stale del source (instancias PipeValve viejas)
    txt = re.sub(
        r'\n?\[node name="Valve[^"]*"[^\n]*instance=ExtResource\( 4 \)\]\n(?:[^\[]*?)(?=\n\[node|\Z)',
        "\n", txt)
    # 1) eliminar bloques de valvulas stale del source
    def drop_valves(m):
        name, parent, body = m.group(1), m.group(2), m.group(0)
        if name.startswith("Valve") and ("TowerCoolantRiser" in parent):
            return "\n"
        return body
    txt = NODE_RE.sub(drop_valves, txt)

    # 2) reemplazar bloques Route existentes y borrar Route3 de EastL5
    replaced = set()

    def repl(m):
        name, parent, body = m.group(1), m.group(2), m.group(0)
        if name.startswith("Valve"):
            return body
        if parent in routes:
            if parent in replaced:
                return "\n"  # hijos Route* adicionales del grupo: fuera
            replaced.add(parent)
            out = ""
            for i, d in enumerate(routes[parent]):
                out += route_block(parent, d, "Route" if i == 0 else f"Route{i + 1}")
            return out
        if name == "Route3" and parent == "TowerCoolantRiserEast/TowerCoolantRiserEast_L5":
            return "\n"
        if name in ("Route2", "Route3") and "TowerCoolantRiser" in parent and "_Ring" not in parent:
            return "\n"
        return body
    txt = NODE_RE.sub(repl, txt)

    # 3) flow_dir de runs
    for parent, d in FLOW_DIRS.items():
        pat = re.compile(
            r'(\[node name="[^"]+" type="Spatial" parent="' + re.escape(parent) + r'"\]\n(?:[^\[]*?))flow_dir = Vector3\([^)]*\)')
        txt = pat.sub(lambda m: m.group(1) + f"flow_dir = Vector3( {d[0]}, {d[1]}, {d[2]} )", txt, count=1)

    # 4) transforms de CryoLoop (runs de hub)
    txt = re.sub(
        r'(\[node name="CryoLoopWest" type="Spatial" parent="\."\]\n)transform = Transform\([^)]*\)',
        lambda m: m.group(1) + "transform = " + HUB_W_TF, txt, count=1)
    txt = re.sub(
        r'(\[node name="CryoLoopEast" type="Spatial" parent="\."\]\n)transform = Transform\([^)]*\)',
        lambda m: m.group(1) + "transform = " + HUB_E_TF, txt, count=1)
    return txt

# ---- Dome_Intro: valvulas, leaks, patches, CryoLoop, ValveInterlink ----
def transform_setter(new_tf: str):
    def repl(m):
        return m.group(1) + "transform = " + new_tf
    return repl

def rewrite_main(txt: str) -> str:
    # valvulas que se mudan al riel B
    moves = {
        "ValveWestFloor1": valve_tf(105, SLOTS[1][0]),
        "ValveWestFloor3": valve_tf(105, SLOTS[3][0]),
        "ValveWestFloor5": valve_tf(105, SLOTS[5][0]),
        "ValveEastFloor1": valve_tf(285, SLOTS[1][0]),
        "ValveEastFloor3": valve_tf(285, SLOTS[3][0]),
        "ValveEastFloor5": valve_tf(285, SLOTS[5][0]),
    }
    for name, tf in moves.items():
        pat = re.compile(
            r'(\[node name="' + name + r'" [^\n]*\]\n)transform = Transform\([^)]*\)')
        txt, n = pat.subn(transform_setter(tf), txt, count=1)
        if n != 1:
            print(f"AVISO: {name} no encontrado")

    # ValveInterlink fuera (sin wiring)
    txt = re.sub(r"\n?\[node name=\"ValveInterlink\" [^\[]*?(?=\n\[node|\Z)", "\n", txt, flags=re.S)

    # leaks: tronco (encima de la valvula de su run) y anillo (brazo troncal az 145/325)
    def leak_pos(name: str):
        if name.startswith("LeakWest"):
            tag = name[8:]
            if tag.startswith("Ring"):
                n = int(tag[4:])
                if n == 0:
                    return None
                p = pt(145, Y[n + 1])
                return (round(p[0] + 0.3 * math.cos(math.radians(145)), 5), p[1],
                        round(p[2] + 0.3 * math.sin(math.radians(145)), 5))
            else:
                n = int(tag[5:])
                offs = {0: 3.9, 2: 13.0, 3: 17.4, 4: 21.9}
                if n not in offs:
                    return None
                if n == 3:
                    return (round(W_RAIL_B[0] - 0.077646, 5), offs[n],
                            round(W_RAIL_B[1] + 0.289778, 5))
                return (-12.3, offs[n], 0.3)
        else:
            tag = name[8:]
            if tag.startswith("Ring"):
                n = int(tag[4:])
                if n == 0:
                    return None
                p = pt(325, Y[n + 1])
                return (round(p[0] + 0.3 * math.cos(math.radians(325)), 5), p[1],
                        round(p[2] + 0.3 * math.sin(math.radians(325)), 5))
            else:
                n = int(tag[5:])
                offs = {0: 3.9, 2: 13.0, 3: 17.4, 4: 21.9}
                if n not in offs:
                    return None
                if n == 3:
                    return (round(E_RAIL_B[0] + 0.077646, 5), offs[n],
                            round(E_RAIL_B[1] - 0.289778, 5))
                return (12.3, offs[n], 0.3)

    for m in list(re.finditer(r'\[node name="(Leak(?:West|East)[^"]*)" parent="[^"]*"\]\ntransform = Transform\([^)]*\)', txt)):
        name = m.group(1)
        pos = leak_pos(name)
        if pos is None:
            continue
        new = (f'[node name="{name}" parent="' + re.search(r'parent="([^"]*)"', m.group(0)).group(1) +
               f'"]\ntransform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, {pos[1]}, {pos[2]} )')
        txt = txt.replace(m.group(0), new, 1)

    # CryoLoop transforms
    txt = re.sub(r'(\[node name="CryoLoopWest" type="Spatial" parent="\."\]\n)transform = Transform\([^)]*\)',
                 lambda m: m.group(1) + "transform = " + HUB_W_TF, txt, count=1)
    txt = re.sub(r'(\[node name="CryoLoopEast" type="Spatial" parent="\."\]\n)transform = Transform\([^)]*\)',
                 lambda m: m.group(1) + "transform = " + HUB_E_TF, txt, count=1)
    return txt

if __name__ == "__main__":
    dry = "--dry" in sys.argv
    for path, fn in ((SRC, rewrite_source), (MAIN, rewrite_main)):
        txt = open(path).read()
        out = fn(txt)
        if dry:
            print(f"{path}: {'SIN CAMBIOS' if out == txt else 'cambios pendientes (--dry)'}")
            continue
        open(path, "w").write(out)
        print(f"{path}: reescrito ({len(txt)} -> {len(out)} bytes)")
