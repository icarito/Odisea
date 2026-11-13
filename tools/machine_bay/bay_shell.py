"""Cascaron decorativo low-poly de una bahia de mantenimiento (Odisea).

Genera por codigo un hangar industrial retrofuturista que ENVUELVE el nivel
jugable sin tocarlo. Todas las medidas se expresan en coordenadas de motor
(Y arriba, -Z adelante): la conversion a Blender Z-up se hace en E() y la
exportacion glTF (export_yup=True) devuelve X/Y/Z de motor. Verificado al
final leyendo los accessors POSITION del GLB.

El nivel jugable ocupa x[-8,8], y[-2,36], z[-8,80]; el cascaron mantiene
1 m de holgura minima (assert sobre todos los vertices) y por eso sus caras
interiores viven en x=+-10, techo y=38..40, fondo z=84 y entrada z=-10.

Geometria: pozo sin piso, costillas/porticos cada 8 m, pasarelas enrejadas,
paneles hundidos, tuberias y tiras emisivas. 4 materiales, 4 objetos.

Uso (desde la raiz del repo):
  blender --background --python tools/machine_bay/bay_shell.py
Salida: <repo>/build/machine_bay/bay_shell.glb
"""
import bpy
import bmesh
import json
import math
import os
import struct
from mathutils import Vector

# ---------------------------------------------------------------- parametros
# Caja jugable existente (metros, Y arriba).
PLAY_X = (-19.5, 19.5)
PLAY_Y = (-2.0, 38.5)
PLAY_Z = (-8.0, 150.0)
CLEARANCE = 1.0            # holgura minima exigida alrededor de la caja

WALL_X = 22.0              # cara interior de las paredes laterales
WALL_T = 0.4               # espesor de paredes/techo/fondo
Z0 = -12.0                 # cara interior de la pared de entrada
Z1 = 154.0                 # cara interior de la pared de fondo
PIT_Y = -30.0              # boca del pozo (las paredes bajan hasta aca)
PIT_T = 0.4                # losa de fondo del pozo
EAVE_Y = 41.0              # alero del techo a dos aguas
APEX_Y = 44.5              # cumbrera
ROOF_T = 0.30              # espesor de las faldas del techo

RIB_STEP = 10.0            # separacion de porticos a lo largo de Z
RIB_W = 0.5                # ancho de costilla (Z)
RIB_DEPTH = 0.9            # cuanto entra la costilla desde la pared (X)
RIB_TOP = 40.8             # tope de costillas / viga superior

DOOR_W = 3.0               # vano de puerta (X)
DOOR_H = 3.0               # vano de puerta (Y), base en y=0

WALKWAY_Y = (8.0, 28.0)    # altura de las dos pasarelas por pared
WALKWAY_W = 0.9            # ancho de pasarela (pegada a la pared)
WALKWAY_T = 0.08
RAIL_H = 1.0

PANEL_ROWS = ((10.0, 15.0), (20.0, 26.0))  # (y0, y1) de paneles hundidos
PANEL_W = 7.5              # ancho de panel en Z

PIPE_Y = (17.0, 34.0)      # alturas de tuberias horizontales
PIPE_R = 0.28
PIPE_X = 21.70             # centro de tuberia respecto de la pared
STRIP_Y = 39.0             # altura de la tira emisiva lateral
STRIP_SEG = 12             # segmentos de tuberias

MAT_DARK = "BayMetalDark"
MAT_MID = "BayMetalMid"
MAT_ORANGE = "BayAccentOrange"
MAT_CYAN = "BayEmissiveCyan"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
OUT_PATH = os.path.join(REPO_ROOT, "build", "machine_bay", "bay_shell.glb")


def E(p):
    """Motor (X, Y arriba, Z) -> Blender (X, Y, Z arriba)."""
    x, y, z = p
    return (x, -z, y)


def rib_positions():
    zs = []
    z = Z0
    while z <= Z1 + 1e-6:
        zs.append(z)
        z += RIB_STEP
    if Z1 - zs[-1] > 0.5:
        zs.append(Z1)
    return zs


class Builder:
    """Acumula cascaras cerradas en un bmesh por material (pocos draw calls)."""

    def __init__(self):
        self.bms = {}

    def bm(self, mat):
        if mat not in self.bms:
            self.bms[mat] = bmesh.new()
        return self.bms[mat]

    def box(self, mat, x0, x1, y0, y1, z0, z1):
        bm = self.bm(mat)
        corners = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]
        v = [bm.verts.new(E(c)) for c in corners]
        for face in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                     (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            bm.faces.new([v[i] for i in face])

    def tri_prism(self, mat, tri_xy, z0, z1):
        bm = self.bm(mat)
        a = [bm.verts.new(E((x, y, z0))) for (x, y) in tri_xy]
        b = [bm.verts.new(E((x, y, z1))) for (x, y) in tri_xy]
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((a[i], a[j], b[j], b[i]))

    def slab(self, mat, quad, normal, thickness):
        bm = self.bm(mat)
        n = Vector(normal).normalized() * thickness
        inner = [Vector(p) for p in quad]
        outer = [p + n for p in inner]
        v = [bm.verts.new(E(p)) for p in inner + outer]
        bm.faces.new(v[0:4])
        bm.faces.new(list(reversed(v[4:8])))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((v[i], v[j], v[4 + j], v[4 + i]))

    def pipe_z(self, mat, cx, cy, z0, z1, radius, seg=STRIP_SEG):
        bm = self.bm(mat)
        rings = []
        for z in (z0, z1):
            ring = []
            for i in range(seg):
                a = 2.0 * math.pi * i / seg
                ring.append(bm.verts.new(
                    E((cx + radius * math.cos(a),
                       cy + radius * math.sin(a), z))))
            rings.append(ring)
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((rings[0][i], rings[0][j],
                          rings[1][j], rings[1][i]))
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[1])))

    def beam(self, mat, a, b, width, depth, wall_sign):
        """Viga de seccion rectangular entre dos puntos del plano de pared."""
        bm = self.bm(mat)
        pa, pb = Vector(a), Vector(b)
        axis = (pb - pa).normalized()
        normal = Vector((wall_sign, 0.0, 0.0))
        perp = axis.cross(normal).normalized()
        ow = normal * (width * 0.5)
        od = perp * (depth * 0.5)
        v = []
        for p in (pa, pb):
            for sw, sd in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                v.append(bm.verts.new(E(p + ow * sw + od * sd)))
        for face in ((0, 1, 2, 3), (4, 7, 6, 5), (0, 1, 5, 4),
                     (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            bm.faces.new([v[i] for i in face])


def make_material(name, base, metallic, rough, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    # El nombre del nodo esta localizado ("BSDF Principista" en es); se busca
    # por tipo para no depender del idioma de la interfaz.
    bsdf = next((n for n in mat.node_tree.nodes
                 if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        raise RuntimeError(f"{name}: material sin nodo Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (base[0], base[1], base[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    if emission is not None:
        key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
        bsdf.inputs[key].default_value = (emission[0], emission[1],
                                          emission[2], 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = (base[0], base[1], base[2], 1.0)
    return mat


def build_walls(b):
    # Pozo: paredes laterales, fondo y paredes de extremo (entrada partida
    # en 4 cajas alrededor del vano: evita booleanos y es mas predecible).
    for s in (-1.0, 1.0):
        x_in = s * WALL_X
        x_out = s * (WALL_X + WALL_T)
        x0, x1 = sorted((x_in, x_out))
        b.box(MAT_MID, x0, x1, PIT_Y, EAVE_Y, Z0 - WALL_T, Z1 + WALL_T)

    # Fondo del pozo.
    b.box(MAT_DARK, -(WALL_X + WALL_T), WALL_X + WALL_T,
          PIT_Y - PIT_T, PIT_Y, Z0 - WALL_T, Z1 + WALL_T)

    # Pared de fondo.
    b.box(MAT_MID, -(WALL_X + WALL_T), WALL_X + WALL_T,
          PIT_Y, EAVE_Y, Z1, Z1 + WALL_T)

    # Pared de entrada con vano de 3 x 3 centrado en x=0, base en y=0.
    z0, z1 = Z0 - WALL_T, Z0
    hx = DOOR_W * 0.5
    b.box(MAT_MID, -(WALL_X + WALL_T), -hx, PIT_Y, EAVE_Y, z0, z1)
    b.box(MAT_MID, hx, WALL_X + WALL_T, PIT_Y, EAVE_Y, z0, z1)
    b.box(MAT_MID, -hx, hx, DOOR_H, EAVE_Y, z0, z1)
    b.box(MAT_MID, -hx, hx, PIT_Y, 0.0, z0, z1)

    # Techo a dos aguas (dos losas inclinadas + viga de cumbrera).
    b.slab(MAT_MID, [(-WALL_X, EAVE_Y, Z0 - WALL_T),
                     (0.0, APEX_Y, Z0 - WALL_T),
                     (0.0, APEX_Y, Z1 + WALL_T),
                     (-WALL_X, EAVE_Y, Z1 + WALL_T)],
           (-2.0, WALL_X, 0.0), ROOF_T)
    b.slab(MAT_MID, [(0.0, APEX_Y, Z0 - WALL_T),
                     (WALL_X, EAVE_Y, Z0 - WALL_T),
                     (WALL_X, EAVE_Y, Z1 + WALL_T),
                     (0.0, APEX_Y, Z1 + WALL_T)],
           (2.0, WALL_X, 0.0), ROOF_T)
    b.box(MAT_DARK, -0.25, 0.25, APEX_Y - 0.1, APEX_Y + ROOF_T + 0.05,
          Z0 - WALL_T, Z1 + WALL_T)

    # Frontones triangulares (cierran el hastial sobre las paredes).
    b.tri_prism(MAT_MID, [(-WALL_X, EAVE_Y), (WALL_X, EAVE_Y),
                          (0.0, APEX_Y)], Z0 - WALL_T, Z0)
    b.tri_prism(MAT_MID, [(-WALL_X, EAVE_Y), (WALL_X, EAVE_Y),
                          (0.0, APEX_Y)], Z1, Z1 + WALL_T)


def build_portals(b):
    ribs = rib_positions()
    for i, z in enumerate(ribs):
        accent = (i % 4 == 0)
        beam_mat = MAT_ORANGE if accent else MAT_DARK
        for s in (-1.0, 1.0):
            x_in = s * (WALL_X - RIB_DEPTH)
            x0, x1 = sorted((x_in, s * WALL_X))
            b.box(MAT_DARK, x0, x1, PIT_Y, RIB_TOP, z - RIB_W / 2.0,
                  z + RIB_W / 2.0)
        b.box(beam_mat, -(WALL_X - RIB_DEPTH), WALL_X - RIB_DEPTH,
              RIB_TOP - 0.4, RIB_TOP, z - RIB_W / 2.0, z + RIB_W / 2.0)
        # Tira emisiva bajo la viga del portico.
        b.box(MAT_CYAN, -(WALL_X - RIB_DEPTH) + 0.1,
              WALL_X - RIB_DEPTH - 0.1, RIB_TOP - 0.56, RIB_TOP - 0.44,
              z - 0.10, z + 0.10)
    return ribs


def build_walkways(b, ribs):
    inner = WALL_X - WALKWAY_W
    strip_w = 0.2
    gap = (WALKWAY_W - 3.0 * strip_w) / 2.0
    for s in (-1.0, 1.0):
        for wy in WALKWAY_Y:
            for k in range(3):
                if s > 0:
                    x0 = inner + k * (strip_w + gap)
                else:
                    x0 = -inner - (k + 1) * strip_w - k * gap
                b.box(MAT_DARK, x0, x0 + strip_w, wy,
                      wy + WALKWAY_T, Z0, Z1)
            # Baranda y postes en el borde interior de la pasarela.
            xr0, xr1 = sorted((s * inner, s * (inner + 0.06)))
            b.box(MAT_ORANGE, xr0, xr1, wy + RAIL_H,
                  wy + RAIL_H + 0.06, Z0, Z1)
            for z in ribs:
                b.box(MAT_ORANGE, xr0, xr1, wy, wy + RAIL_H,
                      z - 0.03, z + 0.03)


def build_panels(b):
    ribs = rib_positions()
    centers = [(a + c) / 2.0 for a, c in zip(ribs, ribs[1:])
               if abs((c - a) - RIB_STEP) < 1e-6]
    for s in (-1.0, 1.0):
        for (py0, py1) in PANEL_ROWS:
            for zc in centers:
                panel_x(b, s, py0, py1, zc)
    # Paneles del fondo, visibles al final del pasillo.
    for xc in (-6.0, 0.0, 6.0):
        panel_z(b, xc, 8.0, 18.0)


def panel_x(b, sign, y0, y1, zc):
    wall = sign * WALL_X
    xs_dark = sorted((wall, wall - sign * 0.04))
    xs_frame = sorted((wall, wall - sign * 0.12))
    z0, z1 = zc - PANEL_W / 2.0, zc + PANEL_W / 2.0
    b.box(MAT_DARK, xs_dark[0], xs_dark[1], y0, y1, z0, z1)
    fx0, fx1 = xs_frame
    b.box(MAT_MID, fx0, fx1, y0 - 0.12, y0, z0 - 0.12, z1 + 0.12)
    b.box(MAT_MID, fx0, fx1, y1, y1 + 0.12, z0 - 0.12, z1 + 0.12)
    b.box(MAT_MID, fx0, fx1, y0 - 0.12, y1 + 0.12, z0 - 0.12, z0)
    b.box(MAT_MID, fx0, fx1, y0 - 0.12, y1 + 0.12, z1, z1 + 0.12)


def panel_z(b, xc, y0, y1):
    zs_dark = sorted((Z1, Z1 - 0.04))
    zs_frame = sorted((Z1, Z1 - 0.12))
    x0, x1 = xc - PANEL_W / 2.0, xc + PANEL_W / 2.0
    b.box(MAT_DARK, x0, x1, y0, y1, zs_dark[0], zs_dark[1])
    fz0, fz1 = zs_frame
    b.box(MAT_MID, x0 - 0.12, x1 + 0.12, y0 - 0.12, y0, fz0, fz1)
    b.box(MAT_MID, x0 - 0.12, x1 + 0.12, y1, y1 + 0.12, fz0, fz1)
    b.box(MAT_MID, x0 - 0.12, x0, y0 - 0.12, y1 + 0.12, fz0, fz1)
    b.box(MAT_MID, x1, x1 + 0.12, y0 - 0.12, y1 + 0.12, fz0, fz1)


def build_pipes(b, ribs):
    for s in (-1.0, 1.0):
        for hy in PIPE_Y:
            b.pipe_z(MAT_DARK, s * PIPE_X, hy, Z0, Z1, PIPE_R)
            for z in ribs:
                bx0, bx1 = sorted((s * (PIPE_X + PIPE_R - 0.05),
                                   s * WALL_X))
                b.box(MAT_DARK, bx0, bx1, hy - 0.12, hy + 0.12,
                      z - 0.12, z + 0.12)
        # Tira de luz continua junto al alero.
        sx0, sx1 = sorted((s * (WALL_X - 0.14), s * (WALL_X - 0.04)))
        b.box(MAT_CYAN, sx0, sx1, STRIP_Y - 0.1, STRIP_Y + 0.1, Z0, Z1)


def build_braces(b, ribs):
    # Cruces de arriostramiento en el pozo (dan escala y profundidad).
    for s in (-1.0, 1.0):
        x = s * (WALL_X - 0.6)
        for a, c in zip(ribs, ribs[1:]):
            if abs((c - a) - RIB_STEP) > 1e-6:
                continue
            b.beam(MAT_DARK, (x, -28.0, a), (x, -4.0, c),
                   0.18, 0.18, s)
            b.beam(MAT_DARK, (x, -4.0, a), (x, -28.0, c),
                   0.18, 0.18, s)


def build_door(b):
    z0, z1 = Z0, Z0 + 0.18
    hx = DOOR_W / 2.0
    for s in (-1.0, 1.0):
        x0, x1 = sorted((s * hx, s * (hx + 0.25)))
        b.box(MAT_ORANGE, x0, x1, 0.0, DOOR_H + 0.25, z0, z1)
    b.box(MAT_ORANGE, -hx - 0.25, hx + 0.25, DOOR_H, DOOR_H + 0.25,
          z0, z1)
    b.box(MAT_ORANGE, -hx - 0.25, hx + 0.25, -0.2, 0.0, z0, z1)
    b.box(MAT_CYAN, -hx, hx, DOOR_H - 0.08, DOOR_H - 0.02, z0, z0 + 0.06)


def create_objects(b, materials):
    objs = []
    for mat_name, bm in b.bms.items():
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(mat_name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(materials[mat_name])
        obj = bpy.data.objects.new(mat_name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        objs.append(obj)
    return objs


def engine_bbox(objs):
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for obj in objs:
        for v in obj.data.vertices:
            ex, ey, ez = v.co.x, v.co.z, -v.co.y
            for i, c in enumerate((ex, ey, ez)):
                lo[i] = min(lo[i], c)
                hi[i] = max(hi[i], c)
    return lo, hi


def check_clearance(objs):
    fx0, fx1 = PLAY_X[0] - CLEARANCE, PLAY_X[1] + CLEARANCE
    fy0, fy1 = PLAY_Y[0] - CLEARANCE, PLAY_Y[1] + CLEARANCE
    fz0, fz1 = PLAY_Z[0] - CLEARANCE, PLAY_Z[1] + CLEARANCE
    for obj in objs:
        for v in obj.data.vertices:
            x, y, z = v.co.x, v.co.z, -v.co.y
            if fx0 <= x <= fx1 and fy0 <= y <= fy1 and fz0 <= z <= fz1:
                raise AssertionError(
                    f"{obj.name}: vertice invade la caja jugable con 1 m de "
                    f"holgura: ({x:.3f}, {y:.3f}, {z:.3f})")


def glb_position_bbox(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise AssertionError("el archivo exportado no es un GLB valido")
    offset = 12
    doc = None
    while offset < length:
        clen, ctype = struct.unpack_from("<II", data, offset)
        offset += 8
        if ctype == 0x4E4F534A:
            doc = json.loads(data[offset:offset + clen].decode("utf-8"))
        offset += clen
    if doc is None:
        raise AssertionError("GLB sin chunk JSON")
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for mesh in doc.get("meshes", []):
        for prim in mesh.get("primitives", []):
            idx = prim.get("attributes", {}).get("POSITION")
            if idx is None:
                continue
            acc = doc["accessors"][idx]
            for i in range(3):
                lo[i] = min(lo[i], acc["min"][i])
                hi[i] = max(hi[i], acc["max"][i])
    return lo, hi


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    materials = {
        MAT_DARK: make_material(MAT_DARK, (0.085, 0.095, 0.105),
                                0.55, 0.78),
        MAT_MID: make_material(MAT_MID, (0.20, 0.22, 0.235),
                               0.45, 0.62),
        MAT_ORANGE: make_material(MAT_ORANGE, (0.85, 0.28, 0.03),
                                  0.20, 0.50),
        MAT_CYAN: make_material(MAT_CYAN, (0.02, 0.22, 0.26),
                                0.0, 0.35, (0.05, 0.85, 1.0), 2.5),
    }

    b = Builder()
    build_walls(b)
    ribs = build_portals(b)
    build_walkways(b, ribs)
    build_panels(b)
    build_pipes(b, ribs)
    build_braces(b, ribs)
    build_door(b)
    objs = create_objects(b, materials)

    check_clearance(objs)

    tris = 0
    for obj in objs:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
    if tris >= 15000:
        raise AssertionError(f"presupuesto de triangulos excedido: {tris}")
    if len(objs) != 4:
        raise AssertionError(f"se esperaban 4 objetos, hay {len(objs)}")

    lo, hi = engine_bbox(objs)
    if not (lo[0] <= -WALL_X and hi[0] >= WALL_X):
        raise AssertionError("bbox X incoherente con las paredes")
    if not (lo[1] <= PIT_Y and hi[1] >= APEX_Y):
        raise AssertionError("bbox Y incoherente con pozo/techo")
    if not (lo[2] <= Z0 and hi[2] >= Z1):
        raise AssertionError("bbox Z incoherente con entrada/fondo")

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        use_selection=False,
        export_cameras=False,
        export_lights=False,
    )

    glo, ghi = glb_position_bbox(OUT_PATH)
    if not (ghi[1] >= EAVE_Y and ghi[2] >= Z1 and glo[2] <= Z0):
        raise AssertionError(f"GLB con ejes inesperados: {glo} .. {ghi}")

    print(f"BAY SHELL triangulos: {tris}")
    print("BAY SHELL bbox motor (Y arriba, m): "
          f"x [{lo[0]:.2f}, {hi[0]:.2f}] "
          f"y [{lo[1]:.2f}, {hi[1]:.2f}] "
          f"z [{lo[2]:.2f}, {hi[2]:.2f}]")
    print("BAY SHELL bbox GLB glTF Y-up (m): "
          f"x [{glo[0]:.2f}, {ghi[0]:.2f}] "
          f"y [{glo[1]:.2f}, {ghi[1]:.2f}] "
          f"z [{glo[2]:.2f}, {ghi[2]:.2f}]")
    print(f"BAY SHELL exportado: {OUT_PATH}")


if __name__ == "__main__":
    main()
