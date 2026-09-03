#!/usr/bin/env python3
"""Extrae a disco las texturas embebidas de los .glb de props.

    python3 tools/extract_glb_textures.py

Los .glb de Sketchfab traen las texturas dentro del binario. El importador de Godot las
embebe entonces en CADA artefacto que las use: el .material, la .scn importada y
cualquier .mesh horneado que referencie ese material. Un solo prop terminaba costando
decenas de MB de repo con la misma textura repetida.

Sacadas a .png, Godot las importa una vez (un .stex por textura) y todo lo demas las
referencia por path. Despues de correr esto va
`tools/relink_prop_materials.gd`, que repunta los slots de cada .material.

Los .png se nombran <material>_<slot>.png porque ese es el nombre que espera el relink.
"""
from __future__ import annotations

import json
import os
import struct
import sys

# (.glb de origen, carpeta destino, lado maximo para albedo/normal)
#
# El lado maximo va por prop: la compuerta mide 12 m y se mira de cerca, asi que se
# queda con el 1024 original; el pedestal y la palanca industrial son props chicos
# (0.6-1.4 m) y a 512 no se les nota. Cada textura cuesta ~4 MB de artefactos .stex a
# 1024 (cinco variantes VRAM) contra ~1 MB a 512, y el juego es GLES2/movil.
JOBS = [
    ("assets/models/free_airlock_door/free_airlock_door.glb", "assets/models/free_airlock_door/textures", 1024),
    ("assets/models/palanca_pedestal/palanca_pedestal.glb", "assets/models/palanca_pedestal/textures", 512),
    ("assets/models/industrial_lever/industrial_electricitys_lever.glb", "assets/models/industrial_lever/textures", 512),
]

# Los mapas ORM y de emision de estos modelos son casi planos (el .png de origen pesa
# unos pocos KB): no necesitan mas que esto.
DATA_MAP_SIZE = 256
DATA_SLOTS = ("orm", "emission")

# Slot glTF -> sufijo del archivo. metallicRoughness sale como "orm" porque Godot lo
# usa para metallic (B), roughness (G) y a veces AO (R).
SLOTS = {
    "baseColorTexture": "albedo",
    "normalTexture": "normal",
    "emissiveTexture": "emission",
    "metallicRoughnessTexture": "orm",
}


def _chunks(data: bytes):
    off = 12  # header glb: magic + version + length
    while off < len(data):
        length, kind = struct.unpack_from("<I4s", data, off)
        off += 8
        yield kind.rstrip(b"\x00 "), off, length
        off += length


def _resize(path: str, max_side: int) -> None:
    """Baja la textura a max_side si hace falta. Sin Pillow se deja como vino."""
    try:
        from PIL import Image
    except ImportError:
        print("  (sin Pillow: %s queda en su tamano original)" % path, file=sys.stderr)
        return
    with Image.open(path) as img:
        if max(img.size) <= max_side:
            return
        ratio = max_side / float(max(img.size))
        size = (max(1, int(round(img.width * ratio))), max(1, int(round(img.height * ratio))))
        img.resize(size, Image.LANCZOS).save(path, optimize=True)


def extract(src: str, out_dir: str, max_side: int) -> int:
    with open(src, "rb") as fh:
        data = fh.read()

    gltf = None
    bin_off = None
    for kind, off, length in _chunks(data):
        if kind == b"JSON":
            gltf = json.loads(data[off:off + length])
        elif kind == b"BIN":
            bin_off = off
    if gltf is None or bin_off is None:
        print("  no es un .glb con chunks JSON+BIN: %s" % src, file=sys.stderr)
        return 0

    # Un mismo image puede usarse en varios slots; el primero que lo reclame le da nombre.
    names: dict[int, str] = {}
    for material in gltf.get("materials", []):
        base = material["name"].replace(".", "_")
        pbr = material.get("pbrMetallicRoughness", {})
        for key, slot in SLOTS.items():
            ref = pbr.get(key) or material.get(key)
            if not ref:
                continue
            image = gltf["textures"][ref["index"]]["source"]
            names.setdefault(image, "%s_%s" % (base, slot))

    os.makedirs(out_dir, exist_ok=True)
    written = 0
    for image_idx, name in sorted(names.items()):
        image = gltf["images"][image_idx]
        if "bufferView" not in image:
            continue  # ya es un archivo externo
        view = gltf["bufferViews"][image["bufferView"]]
        start = bin_off + view.get("byteOffset", 0)
        blob = data[start:start + view["byteLength"]]
        ext = ".jpg" if image.get("mimeType") == "image/jpeg" else ".png"
        path = os.path.join(out_dir, name + ext)
        with open(path, "wb") as fh:
            fh.write(blob)
        slot = name.rsplit("_", 1)[-1]
        _resize(path, DATA_MAP_SIZE if slot in DATA_SLOTS else max_side)
        print("  %-58s %7.1f KB" % (path, os.path.getsize(path) / 1024.0))
        written += 1
    return written


def main() -> int:
    total = 0
    for src, out_dir, max_side in JOBS:
        if not os.path.exists(src):
            print("falta %s" % src, file=sys.stderr)
            continue
        print("==", src)
        total += extract(src, out_dir, max_side)
    print("%d textura(s) extraida(s)" % total)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
