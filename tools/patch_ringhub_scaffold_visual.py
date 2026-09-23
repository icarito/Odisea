#!/usr/bin/env python3
"""FD-314 follow-up - visual de scaffold por sector, no por grupo.

RingHub_Level.tscn ya tenia streaming de COLISION por sector (StreamedSceneChunkV2),
pero el visual seguia siendo UN MeshInstance por grupo con la malla del anillo
completo (`RingHub_<Grupo>_baked.mesh`): el frustum nunca puede descartarla.

tools/bake_scaffold_walkways.gd ahora hornea el visual de cada sector DENTRO de
su `_body.tscn` (mismo StaticBody que la colision), asi que StreamedSceneChunkV2
carga y libera ambos juntos. Este script:

  1. Borra el MeshInstance "Visual" de cada Group_<Grupo> (y su ext_resource al
     *_baked.mesh, que ya no lo referencia nadie).
  2. Agrega el Chunk que faltaba para SpiralWalkways sector 06 (tenia malla
     horneada pero ningun chunk la instanciaba: quedaba huerfana en disco).

No reserializa la escena (PackedScene.pack() sobre una instancia viva se lleva
puesto el estado); reescribe el TEXTO, mismo patron que assemble_ringhub_stream_shell.py.

Uso: python3 tools/patch_ringhub_scaffold_visual.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVEL = ROOT / "core_v2/levels/RingHub_Level.tscn"
MANIFEST = ROOT / "core_v2/levels/interiors/RingHub_scaffold_sectors.json"

GROUPS = ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
TRIGGER_RADIUS = 15.0
RELEASE_MARGIN = 6.0


def main():
    text = LEVEL.read_text()
    if 'name="Visual" type="MeshInstance" parent="ScaffoldStreamRoot' not in text:
        raise SystemExit("no encontre los MeshInstance de grupo; ya esta parchado?")

    # 1. Borra los 3 MeshInstance de grupo y junta los ids de *_baked.mesh que
    # quedan sin uso.
    visual_ids = []

    def strip_visual(m):
        visual_ids.append(int(m.group("id")))
        return ""

    text, n = re.subn(
        r'\n\[node name="Visual" type="MeshInstance" parent="ScaffoldStreamRoot/Group_\w+"\]\n'
        r'layers = 64\nmesh = ExtResource\( (?P<id>\d+) \)\n',
        strip_visual,
        text,
    )
    if n != len(GROUPS):
        raise SystemExit("esperaba %d MeshInstance de grupo, borre %d" % (len(GROUPS), n))

    for vid in visual_ids:
        text, n = re.subn(r'^\[ext_resource path="[^"]+" type="ArrayMesh" id=%d\]\n' % vid, "", text, flags=re.MULTILINE)
        if n != 1:
            raise SystemExit("no pude borrar el ext_resource id=%d de *_baked.mesh" % vid)

    # 2. Chunk_06 de SpiralWalkways: existe en el manifiesto (body ahora no
    # vacio tras el re-bake) pero nunca se emitio en el shell.
    entries = json.loads(MANIFEST.read_text())
    entry = next(e for e in entries if e["group"] == "SpiralWalkways" and e["sector"] == 6)
    if not entry["body"]:
        raise SystemExit("el manifiesto todavia no tiene body para SpiralWalkways sector 06; correr el bake primero")

    next_id = max(int(m) for m in re.findall(r'^\[ext_resource[^\n]*id=(\d+)\]', text, re.MULTILINE)) + 1
    ext_line = '[ext_resource path="%s" type="PackedScene" id=%d]\n' % (entry["body"], next_id)
    # Se agrega junto a los demas ext_resource de sub-escenas, antes del primer sub_resource.
    first_sub = re.search(r"^\[sub_resource ", text, re.MULTILINE)
    text = text[: first_sub.start()] + ext_line + text[first_sub.start():]

    chunk_block = (
        '\n[node name="Chunk_06" type="Spatial" parent="ScaffoldStreamRoot/Group_SpiralWalkways"]\n'
        "script = ExtResource( 15 )\n"
        "chunk_scene = ExtResource( %d )\n"
        "trigger_center = Vector3( %s, %s, %s )\n"
        "trigger_radius = %s\n"
        "release_margin = %s\n"
    ) % (next_id, repr(float(entry["anchor"][0])), repr(float(entry["anchor"][1])), repr(float(entry["anchor"][2])),
         repr(TRIGGER_RADIUS), repr(RELEASE_MARGIN))
    # Justo despues del ultimo Chunk_05 del grupo, antes de Criopods_Visual.
    marker = '\n[node name="Criopods_Visual" parent="ScaffoldStreamRoot" instance=ExtResource( 16 )]'
    idx = text.index(marker)
    text = text[:idx] + chunk_block + text[idx:]

    # Recalcula load_steps (ext_resource + sub_resource + 1), mismo criterio
    # que assemble_ringhub_stream_shell.py.
    total = len(re.findall(r"^\[ext_resource ", text, re.MULTILINE)) + len(
        re.findall(r"^\[sub_resource ", text, re.MULTILINE)
    )
    text = re.sub(r"^load_steps=\d+", "load_steps=%d" % (total + 1), text, count=1, flags=re.MULTILINE)

    LEVEL.write_text(text)
    print("MeshInstance de grupo borrados: %d" % n)
    print("ext_resource *_baked.mesh borrados: %s" % visual_ids)
    print("Chunk_06 de SpiralWalkways agregado (ext id %d)" % next_id)
    print("load_steps=%d" % (total + 1))


if __name__ == "__main__":
    main()
