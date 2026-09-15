#!/usr/bin/env python3
# Genera rungs de la escalera de complejidad para el bisect del Anbernic (FD-299).
# Uso: python3 tools/gen_anbernic_ladder.py <s1a|s1b|s1c|s1d> <salida.tscn>
#   s1a: 80 esferas (~165k vtx), 1 material compartido texturado PBR  -> medido: 100% cobertura
#   s1b: 80 esferas, 80 materiales distintos SIN textura (albedo color)
#   s1c: 80 esferas, 80 materiales distintos + LA MISMA textura albedo
#   s1d: 80 esferas, 80 materiales distintos + 80 TEXTURAS distintas del pack
import sys, glob

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
OPTS = [a for a in sys.argv[1:] if a.startswith("--")]
rung, out = ARGS[0], ARGS[1]
ENV_PATH = "res://scenes/common/space_environment/Environment_ExteriorSpace.tres"
NO_DIR_LIGHT = False
for o in OPTS:
    if o.startswith("--env="):
        ENV_PATH = o.split("=", 1)[1]
    if o == "--no-dir-light":
        NO_DIR_LIGHT = True

N = 80
GRID = 9
SPACING = 3.0
RINGS, SEGMENTS = 64, 32

TEX_SHARED = "res://textures/kenney_prototype_textures/light/texture_03.png"
tex_pool = sorted(
    p for p in glob.glob("assets/textures/*/*/textures/*_diff_1k.png")
    + glob.glob("textures/kenney_prototype_textures/*/*.png")
    if "_unused" not in p and "RoadLines" not in p
    and "/green/" not in p and "/red/" not in p  # excluidos del pack por export_presets
)

ext = [
    '[ext_resource path="res://core_v2/actors/Pilot_v2.tscn" type="PackedScene" id=1]',
    '[ext_resource path="%s" type="Environment" id=2]' % ENV_PATH,
    '[ext_resource path="%s" type="Texture" id=3]' % TEX_SHARED,
]
subs = ['[sub_resource type="SphereMesh" id=1]\nradial_segments = %d\nrings = %d\n' % (SEGMENTS, RINGS)]

for i in range(N):
    if rung == "s1a":
        continue
    r = 0.2 + (i % 8) / 10.0
    g = 0.2 + ((i // 8) % 10) / 12.0
    if rung == "s3":
        # camino de render del domo: ShaderMaterial del lightmap manual,
        # albedo + lightmap (muestreo por UV2) por mesh, texturas del pool.
        tex = tex_pool[i % len(tex_pool)]
        ext.append('[ext_resource path="res://%s" type="Texture" id=%d]' % (tex, 400 + i))
        subs.append(
            '[sub_resource type="ShaderMaterial" id=%d]\n'
            'shader = ExtResource( 4 )\n'
            'shader_param/albedo_color = Color( %.2f, %.2f, %.2f, 1 )\n'
            'shader_param/texture_albedo = ExtResource( 3 )\n'
            'shader_param/has_albedo_map = true\n'
            'shader_param/lightmap_tex = ExtResource( %d )\n'
            'shader_param/lightmap_energy = 1.0\n' % (200 + i, r, g, 0.4, 400 + i)
        )
        continue
    mat = '[sub_resource type="SpatialMaterial" id=%d]\nalbedo_color = Color( %.2f, %.2f, %.2f, 1 )\n' % (200 + i, r, g, 0.4)
    if rung == "s1c":
        mat += "albedo_texture = ExtResource( 3 )\n"
    elif rung == "s1d":
        tex = tex_pool[i % len(tex_pool)]
        mat += 'albedo_texture = ExtResource( %d )\n' % (400 + i)
        ext.append('[ext_resource path="res://%s" type="Texture" id=%d]' % (tex, 400 + i))
    subs.append(mat)

if rung == "s1a":
    ext.append('[ext_resource path="res://materials/interior/FloorDark.tres" type="Material" id=10]')
if rung == "s3":
    ext.append('[ext_resource path="res://core_v2/visual/lightmap_manual.shader" type="Shader" id=4]')

load_steps = len(ext) + len(subs) + 1
txt = "[gd_scene load_steps=%d format=2]\n\n" % load_steps + "\n".join(ext) + "\n" + "\n".join(subs) + "\n"

body = """
[node name="Ladder" type="Spatial"]

[node name="Camera" type="Camera" parent="."]
transform = Transform( 1, 0, 0, 0, 0.866025, 0.5, 0, -0.5, 0.866025, 0, 14, 16 )
current = true

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = ExtResource( 2 )
"""
if not NO_DIR_LIGHT:
    body += """
[node name="DirectionalLight" type="DirectionalLight" parent="WorldEnvironment"]
transform = Transform( 0.996195, 3.82452e-09, 0.0871557, -0.0841859, 0.258819, 0.96225, -0.0225575, -0.965926, 0.257834, 0, 10, 5 )
light_energy = 0.8
shadow_enabled = true
"""
body += """
[node name="Floor" type="CSGBox" parent="."]
transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.5, 0 )
use_collision = true
width = 40.0
height = 0.2
depth = 40.0

[node name="Pilot" parent="." instance=ExtResource( 1 )]
transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.1, -5 )
"""

for i in range(N):
    x = (i % GRID - GRID // 2) * SPACING
    z = (i // GRID - GRID // 2) * SPACING
    s = 1.0 + (i % 3) * 0.4
    body += '\n[node name="Sphere%03d" type="MeshInstance" parent="."]\ntransform = Transform( %.2f, 0, 0, 0, %.2f, 0, 0, 0, %.2f, %.2f, %.2f, %.2f )\nmesh = SubResource( 1 )\n' % (i, s, s, s, x, s * 0.8, z)
    if rung == "s1a":
        body += "material_override = ExtResource( 10 )\n"
    else:
        body += "material_override = SubResource( %d )\n" % (200 + i)

open(out, "w").write(txt + body)
print("rung %s -> %s (materiales: %s, texturas: %s)" % (rung, out, 1 if rung == "s1a" else N, 1 if rung in ("s1a", "s1c") else (len(tex_pool) if rung == "s1d" else 0)))
