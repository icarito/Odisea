#!/usr/bin/env python3
"""FD-314 - Convierte el fragmento `.nodes` del baker de criopods de Dome en
escenas runtime por anillo para los pisos 2-5 de RingHub.

El anillo del piso 1 (despertar) usa el camino MultiMesh de
tools/bake_ringhub_criopods.gd, porque necesita ocultar una instancia. Los pisos
de arriba no: ahi alcanza con la malla fusionada por capa (3 draw calls) y una
caja por pod, streameada por chunk.

Salida (core_v2/levels/chunks/ringhub/):
  RingHub_Criopods{3,4,5,6}_visual.tscn
  RingHub_Criopods{3,4,5,6}_body.tscn

Correr DESPUES de:
  ODISEA_BAKE_SOURCE=res://core_v2/levels/interiors/DomeIntro_CriopodsSource.tscn \
  ODISEA_BAKE_PREFIX=RingHub tools/godot --path . --no-window \
    -s tools/bake_dome_intro_criopods.gd
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FRAGMENT = ROOT / "core_v2/levels/interiors/RingHub_Criopods.nodes"
OUT_DIR = ROOT / "core_v2/levels/chunks/ringhub"
RINGS = ["Criopods3", "Criopods4", "Criopods5", "Criopods6"]
LAYER_NODES = ["Shell", "Glass", "PersonCards"]
# El horneado (ODISEA_BAKE_ITEM_SCALE=1.5) ya deja cada pod a 1.5 en SU radio:
# el anillo NO se escala.
RING_SCALE = 1.0


def parse_fragment(text):
    ext = {}
    for line in text.splitlines():
        m = re.match(r"^#ext (\d+) (\S+)$", line)
        if m:
            ext[int(m.group(1))] = m.group(2)
    body = text.split("#endext\n", 1)[1] if "#endext\n" in text else text
    blocks = []
    for chunk in body.split("\n\n"):
        chunk = chunk.strip("\n")
        if not chunk.strip():
            continue
        header = chunk.splitlines()[0]
        m = re.match(r'^\[node name="([^"]+)" type="([^"]+)" parent="([^"]+)"\]$', header)
        if not m:
            continue
        blocks.append({
            "name": m.group(1),
            "type": m.group(2),
            "parent": m.group(3),
            "props": [ln for ln in chunk.splitlines()[1:] if ln.strip()],
        })
    return ext, blocks


def node_block(name, ntype, parent, props):
    return ['[node name="%s" type="%s" parent="%s"]' % (name, ntype, parent)] + list(props) + [""]


def main():
    if not FRAGMENT.exists():
        sys.exit("falta %s; corre el baker de criopods primero" % FRAGMENT)
    ext, blocks = parse_fragment(FRAGMENT.read_text())
    by_parent_name = {(b["parent"], b["name"]): b for b in blocks}

    for ring in RINGS:
        ring_block = by_parent_name.get(("Spatial", ring))
        if ring_block is None:
            sys.exit("no encontre el anillo %s en el fragmento" % ring)
        ring_transform = next((p for p in ring_block["props"] if p.startswith("transform")), None)
        if ring_transform is None:
            sys.exit("%s sin transform" % ring)
        # Escala 1.5 sobre la base original (que solo lleva la traslacion en Y).
        origin = re.search(r"Transform\(([^)]*)\)", ring_transform).group(1).split(",")[9:12]
        ring_transform = "transform = Transform( %s, 0, 0, 0, %s, 0, 0, 0, %s,%s )" % (
            RING_SCALE, RING_SCALE, RING_SCALE, ",".join(origin))

        def layer(name):
            b = by_parent_name.get(("Spatial/%s" % ring, name))
            if b is None:
                sys.exit("no encontre %s/%s" % (ring, name))
            return b

        # Visual: 3 MeshInstance con la malla fusionada de la capa.
        lines = ["[gd_scene load_steps=%d format=2]" % (len(LAYER_NODES) + 2), ""]
        ids = {}
        for i, name in enumerate(LAYER_NODES, start=1):
            mesh_prop = next(p for p in layer(name)["props"] if p.startswith("mesh ="))
            mesh_id = int(re.search(r"ExtResource\( (\d+) \)", mesh_prop).group(1))
            path = ext[mesh_id]
            ids[name] = i
            lines.append('[ext_resource path="%s" type="ArrayMesh" id=%d]' % (path, i))
        lines.append("")
        lines.append('[node name="CriopodRingVisual" type="Spatial"]')
        lines.append("")
        lines += node_block(ring, "Spatial", ".", [ring_transform])
        for name in LAYER_NODES:
            props = [p for p in layer(name)["props"] if not p.startswith("mesh =")]
            lines += node_block(name, "MeshInstance", ring, props + ["mesh = ExtResource( %d )" % ids[name]])
        (OUT_DIR / ("RingHub_%s_visual.tscn" % ring)).write_text("\n".join(lines))

        # Colision: StaticBody con una caja por pod, en el mismo espacio del anillo.
        shape_path = ext[[k for k, v in ext.items() if v.endswith("_box.shape")][0]]
        coll = ["[gd_scene load_steps=3 format=2]", "",
                '[ext_resource path="%s" type="Shape" id=1]' % shape_path, ""]
        coll.append('[node name="CriopodRingCollision" type="Spatial"]')
        coll.append("")
        coll += node_block(ring, "Spatial", ".", [ring_transform])
        body_block = by_parent_name.get(("Spatial/%s" % ring, "StaticBody"))
        body_props = [p for p in body_block["props"] if not p.startswith("transform")] if body_block else []
        coll += node_block("StaticBody", "StaticBody", ring, body_props)
        pods = 0
        for b in blocks:
            if b["type"] != "CollisionShape" or b["parent"] != "Spatial/%s/StaticBody" % ring:
                continue
            pods += 1
            props = ["shape = ExtResource( 1 )" if p.startswith("shape =") else p for p in b["props"]]
            coll += node_block(b["name"], "CollisionShape", "%s/StaticBody" % ring, props)
        (OUT_DIR / ("RingHub_%s_body.tscn" % ring)).write_text("\n".join(coll))
        print("%s: visual + colision (%d cajas)" % (ring, pods))


if __name__ == "__main__":
    main()
