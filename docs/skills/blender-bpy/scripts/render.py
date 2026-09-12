#!/usr/bin/env python3
"""Runner headless para scene scripts de Odisea.

Uso:
  blender --background --python render.py -- --scene <scene.py> --out <dir> \
      [--res N] [--cam auto] [--light auto] [--no-glb] [--glb-name <nombre>]

Hace:
  1. read_factory_settings (escena limpia, sin datos previos).
  2. importa el scene script (debe definir build()).
  3. llama build().
  4. agrega cámara + sol si faltan.
  5. renderiza <nombre>.png (EEVEE Next, CPU).
  6. exporta <nombre>.glb (GLB con apply transforms).

El scene script debe exponer `build()` y opcionalmente `NAME`.
"""
import argparse
import importlib.util
import os
import sys

import bpy

# Exponer este directorio en sys.path para que los scene scripts hagan
# `from odisea_lib import ...` sin insertar rutas manualmente.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if _SCRIPT_DIR not in sys.path:
    sys.path.insert(0, _SCRIPT_DIR)


def parse_args():
    # separar args de Blender (todo tras "--")
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = []
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--cam", default="auto")
    ap.add_argument("--light", default="auto")
    ap.add_argument("--no-glb", action="store_true")
    ap.add_argument("--glb-name", default=None)
    return ap.parse_args(argv)


def clean_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_scene(path):
    spec = importlib.util.spec_from_file_location("odisea_scene", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not hasattr(mod, "build"):
        raise SystemExit(f"scene script {path} no define build()")
    return mod


def ensure_camera():
    if bpy.context.scene.camera is None:
        bpy.ops.object.camera_add(location=(0, -5, 3))
        cam = bpy.context.active_object
        cam.rotation_euler = (1.0, 0.0, 0.0)  # inclinada hacia la escena
        bpy.context.scene.camera = cam
    return bpy.context.scene.camera


def ensure_light():
    if not any(o.type == "LIGHT" for o in bpy.data.objects):
        bpy.ops.object.light_add(type="SUN", location=(5, 5, 10))
        bpy.context.active_object.data.energy = 3.0


def render_png(out_dir, name, res):
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    path = os.path.join(out_dir, name + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def export_glb(out_dir, name):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_apply=True,
    )
    return path


def main():
    args = parse_args()
    clean_scene()
    mod = load_scene(args.scene)
    name = getattr(mod, "NAME", None) or (args.glb_name or os.path.splitext(os.path.basename(args.scene))[0])

    # allow scene to skip default cam/light by naming itself
    if getattr(mod, "SELF_CAMERA", False):
        pass
    else:
        ensure_camera()
    if getattr(mod, "SELF_LIGHT", False):
        pass
    else:
        ensure_light()

    mod.build()

    png = render_png(args.out, name, args.res)
    print("RENDER_OK", png, os.path.getsize(png))

    if not args.no_glb:
        glb = export_glb(args.out, name)
        print("GLB_OK", glb, os.path.getsize(glb))


if __name__ == "__main__":
    main()
