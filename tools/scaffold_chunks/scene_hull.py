"""Entrecasco — kit de fondo para el espacio entre la espiral de terrazas y el casco.

Piezas de 12 m de arco (un vano por chunk de andamio) que el nivel coloca bajo y sobre el
tramo; no llevan medidas de juego (la ruta sigue saliendo de ScaffoldChunkRegistry).

Env: PIECE = hull_bay | terrace_underside | hull_pylon

  hull_bay           piso: forro interior del casco, cuaderna, largueros, tuberias, tanques
  terrace_underside  techo: enves de una terraza, vigas maestras, luminarias, bandejas
  hull_pylon         pilon de 1 m de alto (el nivel lo estira hasta la cercha del andamio)

Marco Godot: x = eje de la nave (ancho del vano), z = arco (avance), y = radial (arriba = eje).
Regenerar: tools/scaffold_chunks/build.sh
"""
import math
import os

import bpy
from mathutils import Vector

from odisea_lib import _principled, apply_mat, mat_interactable_cyan, mat_matte_plastic, mat_warning_yellow

PIECE = os.environ.get("PIECE", "hull_bay")
NAME = PIECE
SELF_CAMERA = True

L = 12.0      # arco de un vano
WIDTH = 48.0  # ancho axial del vano
M = {}


def g2b(p):
    return Vector((p[0], -p[2], p[1]))


def box(name, center, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=g2b(center))
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[2], size[1])
    apply_mat(o, M[mat])
    return o


def tube(name, p0, p1, radius, mat, sides=8):
    a, b = g2b(p0), g2b(p1)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=d.length, location=(a + b) / 2.0)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    apply_mat(o, M[mat])
    return o


def hull_bay():
    # Forro: chapa con juntas cada 6 m; y = 0 es la cara que se pisa.
    box("Plating", (0.0, -0.2, L / 2.0), (WIDTH, 0.4, L), "hull")
    for i in range(-4, 5):
        box(f"SeamX_{i}", (i * 6.0, 0.01, L / 2.0), (0.08, 0.02, L), "frame")
    # Cuaderna en la junta de entrada: ala, alma calada y cartelas.
    box("RibFlange", (0.0, 0.9, 0.3), (WIDTH, 0.18, 0.7), "frame")
    box("RibWeb", (0.0, 0.45, 0.3), (WIDTH, 0.9, 0.12), "frame")
    for i in range(-7, 8):
        box(f"RibGusset_{i}", (i * 3.0, 0.45, 0.3), (0.12, 0.9, 0.6), "frame")
    box("RibLight", (0.0, 1.02, 0.3), (WIDTH * 0.9, 0.04, 0.12), "lamp")
    # Largueros a lo largo del arco.
    for i, x in enumerate((-21.0, -15.0, -9.0, -3.0, 3.0, 9.0, 15.0, 21.0)):
        box(f"Stringer_{i}", (x, 0.25, L / 2.0), (0.3, 0.5, L), "frame")
    # Haz de tuberias sobre silletas, con una marcada.
    for i, x in enumerate((-11.2, -10.4, -9.6)):
        tube(f"Pipe_{i}", (x, 0.95, 0.0), (x, 0.95, L), 0.28, "cyan" if i == 1 else "panel")
    for z in (3.0, 9.0):
        box(f"Saddle_{z:.0f}", (-10.4, 0.45, z), (2.6, 0.5, 0.25), "frame")
    # Conducto de ventilacion y bandeja de cables.
    box("Duct", (12.5, 1.1, L / 2.0), (2.2, 1.6, L), "panel")
    for z in (2.0, 6.0, 10.0):
        box(f"DuctBand_{z:.0f}", (12.5, 1.1, z), (2.3, 1.7, 0.12), "frame")
    box("CableTray", (6.0, 0.7, L / 2.0), (1.0, 0.12, L), "frame")
    # Tanques y un armario tecnico: lectura de escala humana.
    for i, x in enumerate((-18.5, 19.0)):
        tube(f"Tank_{i}", (x, 0.5, 6.0), (x, 3.4, 6.0), 1.3, "panel", 12)
        box(f"TankBand_{i}", (x, 2.0, 6.0), (2.7, 0.2, 2.7), "yellow")
    box("Cabinet", (-4.5, 1.0, 9.5), (1.4, 2.0, 0.8), "panel")
    box("CabinetScreen", (-4.5, 1.4, 9.08), (0.8, 0.4, 0.04), "cyan")
    # Pasillo de inspeccion pintado junto al pilon central.
    for s in (-1, 1):
        box(f"WalkLine_{s}", (s * 1.6, 0.012, L / 2.0), (0.12, 0.02, L), "yellow")


def terrace_underside():
    # y = 0 es la cara inferior de la losa; todo cuelga hacia -y.
    box("Slab", (0.0, 0.5, L / 2.0), (WIDTH, 1.0, L), "hull")
    for z in (0.3, 6.0):
        box(f"Girder_{z:.0f}", (0.0, -0.75, z), (WIDTH, 1.5, 0.5), "frame")
        box(f"GirderFlange_{z:.0f}", (0.0, -1.5, z), (WIDTH, 0.14, 0.9), "frame")
    for i, x in enumerate((-18.0, -6.0, 6.0, 18.0)):
        box(f"Beam_{i}", (x, -0.45, L / 2.0), (0.4, 0.9, L), "frame")
        box(f"Lamp_{i}", (x + 3.0, -0.95, 3.0), (2.4, 0.1, 0.5), "lamp")
        box(f"LampHanger_{i}", (x + 3.0, -0.5, 3.0), (0.08, 0.9, 0.08), "frame")
    for i, x in enumerate((-13.0, -12.2)):
        tube(f"CeilPipe_{i}", (x, -1.1, 0.0), (x, -1.1, L), 0.22, "panel")
    box("CeilTray", (10.0, -1.0, L / 2.0), (1.4, 0.1, L), "frame")
    box("Hatch", (0.0, -0.03, 9.0), (3.0, 0.06, 3.0), "yellow")


def hull_pylon():
    # Fuste de 1 m (y 0..1) que el nivel estira; zapata y capitel los pone el nivel aparte.
    box("Shaft", (0.0, 0.5, 0.0), (0.6, 1.0, 0.6), "frame")
    for s in (-1, 1):
        box(f"Fin_{s}", (s * 0.36, 0.5, 0.0), (0.12, 1.0, 0.9), "frame")


def camera(extent, look):
    eye = g2b((look[0] + extent * 0.9, look[1] + extent * 0.55, look[2] - extent * 0.9))
    target = g2b(look)
    bpy.ops.object.camera_add(location=eye)
    cam = bpy.context.active_object
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 35
    bpy.context.scene.camera = cam


def build():
    M.update({"hull": mat_matte_plastic("M_Hull", base=(0.20, 0.22, 0.25), roughness=0.8),
              "frame": mat_matte_plastic("M_Frame", base=(0.18, 0.19, 0.21), roughness=0.55),
              "panel": mat_matte_plastic("M_Panel", base=(0.42, 0.46, 0.50), roughness=0.5),
              "yellow": mat_warning_yellow(), "cyan": mat_interactable_cyan(),
              "lamp": _principled("M_Lamp", base=(1.0, 0.86, 0.62), emission=(1.0, 0.82, 0.55), emission_strength=3.0)})
    if PIECE == "hull_bay":
        hull_bay()
        camera(30.0, (0.0, 1.0, L / 2.0))
    elif PIECE == "terrace_underside":
        terrace_underside()
        camera(30.0, (0.0, -6.0, L / 2.0))
    else:
        hull_pylon()
        camera(3.0, (0.0, 0.5, 0.0))
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.6, 0.66, 1.0)
    bpy.context.scene.world = world
