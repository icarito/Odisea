"""Chunks de andamio Transit-Run — arte low-poly generado desde el registro.

Las MEDIDAS no viven aqui: salen de tools/scaffold_chunks/chunks.json, exportado desde
core_v2/systems/scaffold/ScaffoldChunkRegistry.gd. Este script solo las viste (chapa,
bastidor, barandas, cercha, franjas, props). La colision la arma el baker desde el registro.

Env: CHUNK=<id del registro>  (un chunk por corrida)

Regenerar todo (desde la raiz del repo): tools/scaffold_chunks/build.sh

Objetos con prefijo `Dyn_` (mamparo cortable, cable, carro) se hornean a una malla aparte:
son el lugar de los props dinamicos (LaserGate, cuerda, carro) y no deben quedar soldados.
"""
import json
import math
import os

import bpy
from mathutils import Vector

from odisea_lib import (apply_mat, mat_brushed_steel_dark, mat_brushed_steel_light,
                        mat_interactable_cyan, mat_matte_plastic, mat_warning_yellow)

CHUNK = os.environ.get("CHUNK", "scaffold_sprint_chute")
NAME = CHUNK
SELF_CAMERA = True

_HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(_HERE, "chunks.json")))
L = DATA["chunk_length"]
W = DATA["walkway_width"]
RAIL = DATA["rail_height"]

PLATE_T = 0.12
FRAME = 0.12
POST = 0.07
SPINE_DROP = 1.8

M = {}


def g2b(p):
    """Godot (x, y arriba, z a lo largo) -> Blender (x, -z, y arriba)."""
    return Vector((p[0], -p[2], p[1]))


def prism(name, p0, p1, w, h, mat, dx=0.0, dy=0.0):
    """Barra de seccion w x h entre dos puntos Godot, desplazada (dx lateral, dy vertical)."""
    a = g2b((p0[0] + dx, p0[1] + dy, p0[2]))
    b = g2b((p1[0] + dx, p1[1] + dy, p1[2]))
    d = b - a
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(a + b) / 2.0)
    o = bpy.context.active_object
    o.name = name
    o.scale = (w, d.length, h)
    o.rotation_euler = d.to_track_quat("Y", "Z").to_euler()
    apply_mat(o, M[mat])
    return o


def box(name, center, size, mat):
    """Caja alineada a los ejes: centro y tamano en Godot (x, y, z)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(center))
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    apply_mat(o, M[mat])
    return o


def z_range(n):
    return n["position"][2] - n["size"][2] / 2.0, n["position"][2] + n["size"][2] / 2.0


def ends(n):
    """Extremos (x, y, z) de la superficie caminable; una rampa sube `rise` de z0 a z1."""
    x, y, _ = n["position"]
    z0, z1 = z_range(n)
    half = n.get("rise", 0.0) / 2.0
    return (x, y - half, z0), (x, y + half, z1)


def neighbour_on_side(n, nodes, sign):
    z0, z1 = z_range(n)
    for o in nodes:
        if o is n or abs(o["position"][0] - (n["position"][0] + sign * W)) > 0.1:
            continue
        oz0, oz1 = z_range(o)
        if min(z1, oz1) - max(z0, oz0) > 0.2:
            return True
    return False


def continues(n, nodes, z_end):
    """Hay otra plataforma a la misma altura pegada a este extremo (no hace falta franja)."""
    for o in nodes:
        if o is n or o.get("rise") or n.get("rise"):
            continue
        if abs(o["position"][0] - n["position"][0]) > 0.1 or abs(o["position"][1] - n["position"][1]) > 0.1:
            continue
        oz0, oz1 = z_range(o)
        if oz0 - 0.05 <= z_end <= oz1 + 0.05:
            return True
    return False


def deck(n, nodes):
    nid = n["id"]
    p0, p1 = ends(n)
    sx = n["size"][0]
    prism(f"Deck_{nid}", p0, p1, sx, PLATE_T, "light", dy=-PLATE_T / 2.0)
    for sign in (-1, 1):
        off = sign * (sx / 2.0 - FRAME / 2.0)
        prism(f"Frame_{nid}_{sign}", p0, p1, FRAME, 0.24, "dark", dx=off, dy=-0.2)
        if neighbour_on_side(n, nodes, sign):
            continue
        rail_dx = sign * (sx / 2.0 - POST / 2.0)
        prism(f"Rail_{nid}_{sign}", p0, p1, POST, POST, "dark", dx=rail_dx, dy=RAIL)
        count = max(2, int(round((p1[2] - p0[2]) / 2.0)) + 1)
        for i in range(count):
            t = i / (count - 1)
            base = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
            prism(f"Post_{nid}_{sign}_{i}", base, (base[0], base[1] + RAIL, base[2]), POST, POST, "dark", dx=rail_dx)
    span = p1[2] - p0[2]
    for i in range(max(2, int(span / 2.0) + 1)):
        t = (i + 0.5) / max(2, int(span / 2.0) + 1)
        c = [p0[k] + (p1[k] - p0[k]) * t for k in range(3)]
        box(f"Cross_{nid}_{i}", (c[0], c[1] - 0.2, c[2]), (sx, 0.16, FRAME), "dark")
    if not n.get("rise"):
        y = n["position"][1]
        for z_end, inward in ((p0[2], 1), (p1[2], -1)):
            if 0.01 < z_end < L - 0.01 and not continues(n, nodes, z_end):
                box(f"Hazard_{nid}_{inward}", (p0[0], y + 0.012, z_end + inward * 0.2), (sx - 0.3, 0.02, 0.35), "yellow")


def truss(nodes):
    low = min(ends(n)[0][1] for n in nodes)
    y = low - SPINE_DROP
    prism("Spine", (0.0, y, 0.0), (0.0, y, L), 0.3, 0.3, "dark")
    for z in (0.0, L):
        box(f"Collar_{z:.0f}", (0.0, y, min(max(z, 0.2), L - 0.2)), (0.5, 0.5, 0.4), "yellow")
    for n in nodes:
        p0, p1 = ends(n)
        for i, p in enumerate((p0, p1)):
            zin = p[2] + (0.3 if i == 0 else -0.3)
            prism(f"Hanger_{n['id']}_{i}", (p[0], p[1] - 0.3, zin), (0.0, y, zin), 0.1, 0.1, "dark")


def blockers(c):
    for b in c["blockers"]:
        x, y, z = b["position"]
        sx, sy, sz = b["size"]
        if b["cuttable"]:
            box("Dyn_Bulkhead", (x, y, z), (sx, sy, sz), "dark")
            for s in (-1, 1):
                prism(f"Dyn_Brace_{s}", (x - s * sx / 2.2, y - sy / 2.2, z - sz), (x + s * sx / 2.2, y + sy / 2.2, z - sz),
                      0.1, 0.1, "yellow")
        else:
            box("GlooWall", (x, y, z), (sx, sy, sz), "light")
            for i in range(3):
                box(f"GlooAnchor_{i}", (x, sy * (i + 1) / 4.0, z - sz / 2.0 - 0.03), (0.9, 0.25, 0.06), "cyan")


def extras(c):
    nodes = {n["id"]: n for n in c["nodes"]}
    cid = c["id"]
    if cid == "scaffold_sprint_chute":
        for s in (-1, 1):
            box(f"Lane_{s}", (s * 0.85, 0.012, L / 2.0), (0.06, 0.02, L - 1.0), "cyan")
    elif cid == "scaffold_curved_bank":
        box("Kerb", (W / 2.0 - 0.1, 0.12, L / 2.0), (0.2, 0.24, L), "yellow")
        for i in range(5):
            box(f"Chevron_{i}", (-0.2, 0.012, 1.5 + i * 2.25), (W - 0.9, 0.02, 0.2), "yellow")
    elif cid == "scaffold_triple_cadence":
        for n in c["nodes"]:
            x, y, z = n["position"]
            box(f"Beat_{n['id']}", (x, y + 0.012, z), (0.5, 0.02, 0.5), "cyan")
    elif cid == "scaffold_catenary_span":
        za, zb, top, sag = 0.8, L - 0.8, 2.3, 0.9
        for i, z in enumerate((za, zb)):
            prism(f"Anchor_{i}", (0.0, 0.0, z), (0.0, top, z), 0.16, 0.16, "yellow")
        seg = 8
        pts = [(0.0, top - sag * math.sin(math.pi * i / seg), za + (zb - za) * i / seg) for i in range(seg + 1)]
        for i in range(seg):
            prism(f"Dyn_Cable_{i}", pts[i], pts[i + 1], 0.05, 0.05, "cable")
    elif cid == "diorama_mag_cart":
        x = nodes["rail"]["position"][0]
        for s in (-1, 1):
            prism(f"Track_{s}", (x + s * 0.5, 0.05, 0.0), (x + s * 0.5, 0.05, L), 0.08, 0.1, "cyan")
        for i in range(8):
            box(f"Sleeper_{i}", (x, -0.06, 0.75 + i * 1.5), (1.6, 0.12, 0.2), "dark")
        box("Dyn_CartChassis", (x, 0.45, 3.0), (1.4, 0.4, 2.2), "yellow")
        box("Dyn_CartLamp", (x, 0.7, 4.0), (0.5, 0.12, 0.12), "cyan")
        for sx in (-1, 1):
            for sz in (-1, 1):
                box(f"Dyn_CartWheel_{sx}_{sz}", (x + sx * 0.5, 0.2, 3.0 + sz * 0.8), (0.12, 0.3, 0.3), "dark")
    elif cid in ("diorama_counterweight_crane", "scaffold_splitter_hub"):
        sx, sy, sz = nodes["station"]["position"]
        if cid == "diorama_counterweight_crane":
            top = 5.0
            prism("Mast", (sx, sy, sz), (sx, sy + top, sz), 0.4, 0.4, "dark")
            prism("Boom", (sx + 2.0, sy + top, sz), (sx - 7.0, sy + top, sz), 0.25, 0.3, "yellow")
            prism("Dyn_HookLine", (sx - 6.5, sy + top, sz), (sx - 6.5, sy + 2.0, sz), 0.04, 0.04, "cable")
            box("Dyn_Hook", (sx - 6.5, sy + 1.85, sz), (0.3, 0.3, 0.3), "cyan")
            prism("Dyn_WeightLine", (sx + 1.8, sy + top, sz), (sx + 1.8, sy + 3.2, sz), 0.04, 0.04, "cable")
            box("Dyn_Counterweight", (sx + 1.8, sy + 2.6, sz), (1.0, 1.2, 1.0), "dark")
        else:
            box("Console", (sx, sy + 0.55, sz + 1.2), (1.2, 1.1, 0.5), "dark")
            box("ConsoleScreen", (sx, sy + 0.9, sz + 0.93), (0.9, 0.4, 0.04), "cyan")
            prism("SignPost", (W / 2.0, 0.0, L / 2.0), (W / 2.0, 2.2, L / 2.0), 0.1, 0.1, "dark")
            box("SignArrow", (W / 2.0 + 0.45, 2.0, L / 2.0), (0.9, 0.3, 0.05), "cyan")


def camera(nodes):
    xs = [n["position"][0] for n in nodes]
    ys = [ends(n)[1][1] for n in nodes]
    cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
    extent = max(L, max(xs) - min(xs) + W, max(ys) - min(ys))
    target = g2b((cx, cy, L / 2.0))
    eye = g2b((cx + extent * 0.8, cy + extent * 0.6, L / 2.0 - extent * 0.8))
    bpy.ops.object.camera_add(location=eye)
    cam = bpy.context.active_object
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 35
    bpy.context.scene.camera = cam


def build():
    M.update({"light": mat_brushed_steel_light(), "dark": mat_brushed_steel_dark(),
              "yellow": mat_warning_yellow(), "cyan": mat_interactable_cyan(),
              "cable": mat_matte_plastic("M_Cable", base=(0.08, 0.08, 0.09))})
    c = DATA["chunks"][CHUNK]
    for n in c["nodes"]:
        deck(n, c["nodes"])
    truss(c["nodes"])
    blockers(c)
    extras(c)
    camera(c["nodes"])
    # Fondo claro solo para la vista previa (el glTF no exporta el mundo): sin entorno el
    # acero pulido sale negro.
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    # Por tipo, no por nombre: el nombre del nodo se localiza con el idioma del host.
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.6, 0.66, 1.0)
    bpy.context.scene.world = world
