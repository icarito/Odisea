"""Dome_TerraceV2 — domo low-poly paramétrico para Odisea (iteración 2).

Reemplaza el QodotMap DomeTerrace: tambor + casquete esférico, 4 bores
cilíndricos concéntricos con la carcasa de los airlocks (sin gap) y agujero
circular en el piso para la bajada al hangar.

Iteración 2 — calibrada contra maps/DomeTerrace.obj (fuente original):
  - Perfil medido del OBJ: tambor a radio pleno (r_int 30.75 / r_ext 31.35)
    hasta ~10.1 m; casquete = esfera R=33.15 con centro en z=-0.58
    (apex exterior 32.57 m), construido por la cara interior para quedar
    tangente al tambor. La iteración 1 tamboreaba solo 5 m y apex 22 m ->
    pasarelas, escaleras, piso 5, risers y criopods atravesaban la pared.
  - Bore airlock calzado a la carcasa real (airlock_baked/CylindricalShell.mesh,
    tubo facetado que Dome_Base/Dome_Default instancian con eje en Y=3.4): el
    agujero va a r=3.10, dentro de la chapa (2.80 interior .. 3.34/3.50 exterior),
    asi el borde del muro queda enterrado en el metal y no se ve ranura. El OBJ V1
    traia un arco r~4.5 porque ahi el tunel era geometria propia; el cutter
    booleano no agrega collarín, y un agujero mayor que la chapa deja anillo de
    cielo visible desde adentro.

Env vars:
  DOME_CAM=ext   -> vista exterior 3/4 alta (render + GLB)
  DOME_CAM=hero  -> vista exterior 3/4 a nivel de ojo, con airlock visible
  DOME_CAM=floor -> vista cenital con el casquete oculto (solo render)

Regenerar (desde la raíz del repo Odisea):
  blender --background --python docs/skills/blender-bpy/scripts/render.py -- \
    --scene tools/dome_v2/scene_dome.py --out /tmp/dome_v2 --glb-name DomeTerraceV2
  (repetir con DOME_CAM=hero y DOME_CAM=floor para previews)
Luego hornear con tools/bake_dome_terrace_v2.gd.
"""
import bpy
import bmesh
import math
import os

MODE = os.environ.get("DOME_CAM", "ext")
NAME = f"DomeTerraceV2_{MODE}"
SELF_CAMERA = True
SELF_LIGHT = True

# --- Dimensiones (metros, Z-up Blender -> glTF Y-up al exportar) ---
# Perfil fiteado contra los vértices del OBJ original (ver docstring).
# El casquete se construye por la cara INTERIOR (esfera R=CAP_RI) y el
# modificador Solidify empuja el espesor hacia afuera: así la cara interior
# es tangente al tambor (sin escalón en z=DRUM_H) y la exterior reproduce
# la esfera medida (R=33.15, apex 32.57).
R_IN = 30.75      # radio interior de pared (cara interior medida en el piso)
WALL_T = 0.6      # espesor de pared (cara exterior medida ~31.35)
CAP_RS = 33.15    # radio de la esfera EXTERIOR del casquete (fit del OBJ)
CAP_CY = -0.58    # centro Z de la esfera (apex exterior = CY + RS = 32.57)
CAP_RI = CAP_RS - WALL_T  # esfera interior (32.55): tangente al tambor
DRUM_H = -CAP_CY + math.sqrt(CAP_RI**2 - R_IN**2)  # take-off tangente
SEG = 48          # segmentos de revolución (low-poly: ~4 m por faceta)

# --- Airlocks (N/S/E/O) ---
# Dome_Base/Dome_Default instancian la carcasa con origen en (±32, 3.4)/(∓32, 3.4)
# y su eje radial hacia adentro. Perfil medido en airlock_baked/CylindricalShell.mesh
# cortando el plano medio del muro: la chapa (tubo facetado de 20 caras) va de
# r=2.80 (circunradio interior) a r=3.34..3.50 (exterior). El agujero se corta a
# r=3.10, DENTRO de esa chapa: asi el borde del muro queda enterrado en el metal
# del airlock y no se ve ranura desde ningun lado. Un agujero mayor que la chapa
# (r=3.6, antes r=4.6) deja un anillo de cielo visible.
BORE_R = 3.1      # radio del arco del túnel (enterrado en la chapa 2.80..3.34)
BORE_CY = 3.4     # centro en altura = centro del airlock
BORE_IN = 30.3    # inicio del cutter en el eje (boca ~0.45 dentro de R_IN)
BORE_OUT = 36.3   # fin del cutter (cubre la OuterSeal del shell en 32+3.2)

# --- Agujero de hangar en el piso ---
# Centro de la ScaffoldHubTower (Ringhubs): la torre instancia en Dome_Base.tscn
# está en el origen (transform identidad), apertura interna r=6.0, exterior r=13.0.
HOLE_R = 4.5
HOLE_XY = (0.0, 0.0)

FLOOR_T = 1.625   # espesor del piso (igual al reborde original)


def profile_points():
    """Perfil (r, z) de la cara INTERIOR: tambor + casquete hasta el ápex.

    DRUM_H se elige para que la esfera interior pase exactamente por
    (R_IN, DRUM_H): transición tangente, sin escalón.
    """
    pts = [(R_IN, 0.0), (R_IN, DRUM_H)]
    n = 12
    apex_z = CAP_CY + CAP_RI
    for i in range(1, n + 1):
        z = DRUM_H + (apex_z - DRUM_H) * i / n
        r = math.sqrt(max(CAP_RI * CAP_RI - (z - CAP_CY) ** 2, 0.0))
        pts.append((r, z))
    return pts


def build_shell():
    pts = profile_points()
    bm = bmesh.new()
    angles = [2.0 * math.pi * j / SEG for j in range(SEG)]
    rings = []
    for (r, z) in pts:
        if r < 1e-4:
            rings.append(None)  # ápex
        else:
            rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z))
                          for a in angles])
    prev = rings[0]
    for i in range(1, len(rings)):
        cur = rings[i]
        if cur is None:
            apex = bm.verts.new((0.0, 0.0, pts[i][1]))
            for j in range(SEG):
                j2 = (j + 1) % SEG
                bm.faces.new((prev[j], prev[j2], apex))
            break
        for j in range(SEG):
            j2 = (j + 1) % SEG
            bm.faces.new((prev[j], prev[j2], cur[j2], cur[j]))
        prev = cur
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new("DomeShell")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("DomeShell", me)
    bpy.context.collection.objects.link(obj)
    md = obj.modifiers.new("shell", 'SOLIDIFY')
    md.thickness = WALL_T
    md.offset = 1.0  # espesor hacia afuera: la cara interior queda en R_IN
    return obj


def box(name, center, size):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def cyl(name, radius, depth, loc, rot=(0.0, 0.0, 0.0), seg=48):
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=radius,
                                        depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return o


def boolean_cut(target, cutter):
    md = target.modifiers.new("bool", 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.solver = 'EXACT'
    md.object = cutter
    apply_mods(target)
    bpy.data.objects.remove(cutter, do_unlink=True)


def apply_mods(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for md in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)


def build():
    from odisea_lib import (mat_brushed_steel_light, mat_brushed_steel_dark,
                            mat_interactable_cyan, mat_warning_yellow)

    mat_shell = mat_brushed_steel_light()
    mat_cyan = mat_interactable_cyan()

    shell = build_shell()
    shell.data.materials.append(mat_shell)

    # 4 bores horizontales para airlocks (concéntricos con la carcasa).
    # Cutter: cilindro del arco + caja que aplana el piso del túnel en z=0
    # (el cilindro solo llegaría a -0.4 y picaría un plato en la losa).
    dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    for (dx, dy) in dirs:
        if dx != 0:
            rot = (0.0, math.pi / 2, 0.0)
        else:
            rot = (math.pi / 2, 0.0, 0.0)
        mid = (BORE_IN + BORE_OUT) / 2.0
        length = BORE_OUT - BORE_IN
        cutter = cyl(f"Bore_{dx}_{dy}", BORE_R, length,
                     (dx * mid, dy * mid, BORE_CY), rot=rot, seg=48)
        boolean_cut(shell, cutter)
        # Piso plano del túnel en z=0. Con BORE_R=3.1 el arco ya topa en z=0.3
        # (nunca baja del piso), así que este corte no toca la cascara; se deja
        # como red de seguridad para radios mayores.
        flat = box(f"BoreFlat_{dx}_{dy}",
                   (dx * mid, dy * mid, -0.6),
                   ((length, BORE_R * 2 + 0.2, 1.2) if dx != 0
                    else (BORE_R * 2 + 0.2, length, 1.2)))
        boolean_cut(shell, flat)

    # Separa las paredes de los bores en su propio objeto: viajan con acero
    # oscuro plano en el bake. El shader cilíndrico de la carcasa reconstruye
    # UVs desde la posición angular mundial y smearingaría la textura a lo
    # largo del túnel radial. Criterio: distancia al eje del bore < BORE_R Y
    # normal perpendicular al eje (asi solo entra el túnel, no el tambor).
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.mode_set(mode='OBJECT')
    for f in shell.data.polygons:
        c = f.center
        n = f.normal
        sel = False
        for (dx, dy) in dirs:
            if dx != 0:
                perp = math.hypot(c.y, c.z - BORE_CY)
                along = c.x * dx  # distancia firmada en el eje
                axial = abs(n.x)
            else:
                perp = math.hypot(c.x, c.z - BORE_CY)
                along = c.y * dy
                axial = abs(n.y)
            # La pared del tunel tiene la normal PERPENDICULAR al eje del bore.
            # Sin este filtro el tambor entero alrededor de cada abertura (cuyas
            # caras del meridiano tienen la normal paralela al eje) viajaba con
            # acero oscuro y se veia como un panel liso arriba/abajo del airlock.
            if perp < BORE_R + 0.05 and BORE_IN - 0.1 < along < BORE_OUT + 0.1 \
                    and axial < 0.3:
                sel = True
                break
        f.select = sel
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='SELECTED')
    bpy.ops.object.mode_set(mode='OBJECT')
    bores_obj = [o for o in bpy.data.objects if o.name.startswith(shell.name + ".")]
    if bores_obj:
        bores_obj[0].name = "BoreWalls"
        bores_obj[0].data.materials.clear()
        bores_obj[0].data.materials.append(mat_brushed_steel_dark())

    # Piso con agujero para el hangar
    hx, hy = HOLE_XY
    floor = cyl("DomeFloor", R_IN, FLOOR_T, (0, 0, -FLOOR_T / 2))
    hole = cyl("HoleCutter", HOLE_R, FLOOR_T + 2.0, (hx, hy, -FLOOR_T / 2), seg=48)
    boolean_cut(floor, hole)

    # Reborde amarillo de seguridad alrededor del agujero
    bpy.ops.mesh.primitive_torus_add(major_radius=HOLE_R + 0.55,
                                     minor_radius=0.14, location=(hx, hy, 0.03))
    rim = bpy.context.active_object
    rim.name = "HangarHoleRim"
    rim.scale = (1.0, 1.0, 0.35)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Barras cian flanqueando cada abertura de airlock (fuera del arco BORE_R)
    for (dx, dy) in dirs:
        for s in (1, -1):
            if dx != 0:
                loc = (dx * (R_IN - 0.1), s * (BORE_R + 0.7), BORE_CY)
                size = (0.5, 0.35, 3.4)
            else:
                loc = (s * (BORE_R + 0.7), dy * (R_IN - 0.1), BORE_CY)
                size = (0.35, 0.5, 3.4)
            strip = box(f"Strip_{dx}_{dy}_{s}", loc, size)
            strip.data.materials.append(mat_cyan)

    # Referencias de la torre de andamios (solo vista en planta, no van al GLB):
    # anillo interior r=6 (apertura de la torre) y exterior r=13.
    if MODE == "floor":
        for rr in (6.0, 13.0):
            bpy.ops.mesh.primitive_torus_add(major_radius=rr, minor_radius=0.08,
                                             location=(0, 0, 0.02))
            ring = bpy.context.active_object
            ring.name = f"RefRing_{rr:.0f}"
            ring.scale = (1.0, 1.0, 0.3)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            ring.data.materials.append(mat_brushed_steel_light())
    floor.data.materials.append(mat_brushed_steel_dark())
    rim.data.materials.append(mat_warning_yellow())

    # cámara + luz
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    target = bpy.data.objects.new("CamTarget", None)
    bpy.context.collection.objects.link(target)
    if MODE == "floor":
        shell.hide_render = True
        cam.location = (hx + 0.5, hy - 0.5, 55.0)
        target.location = (hx, hy, 0.0)
    elif MODE == "hero":
        cam.location = (46.0, -56.0, 7.0)
        target.location = (0.0, 0.0, 12.0)
    else:
        cam.location = (76.0, -76.0, 44.0)
        target.location = (0.0, 0.0, 10.0)
    c = cam.constraints.new('TRACK_TO')
    c.target = target
    c.track_axis = 'TRACK_NEGATIVE_Z'
    c.up_axis = 'UP_Y'
    bpy.context.scene.camera = cam

    sun = bpy.data.lights.new("Sun", 'SUN')
    sun.energy = 4.0
    sun_obj = bpy.data.objects.new("Sun", sun)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(40), 0.0, math.radians(-40))
    sun_obj.location = (60, -60, 80)

    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("World")
        bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.04, 0.05, 0.08, 1.0)
        bg.inputs[1].default_value = 0.6

    total = sum(len(o.data.polygons) for o in bpy.data.objects
                if o.type == 'MESH')
    print(f"POLYCOUNT total: {total} caras")


# NOTA: no llamar build() aqui — render.py lo invoca al importar el modulo;
# llamarlo en el modulo duplica toda la geomeria (sufijos .001).
