#!/usr/bin/env python3
"""FD-314 follow-up - visual de scaffold por sector, no por grupo.

RingHub_Level.tscn ya tenia streaming de COLISION por sector
(StreamedSceneChunkV2), pero el visual seguia siendo UN MeshInstance por grupo
con la malla del anillo completo (`RingHub_<Grupo>_baked.mesh`): una sola malla
que abarca los 360 grados, asi que el frustum no la puede descartar nunca y se
dibuja entera se mire donde se mire.

Este script la reemplaza por un MeshInstance por sector, apuntando a las mallas
`RingHub_<Grupo>_sector_NN.mesh` que el baker ya emitia y que nadie referenciaba.

Los visuales quedan SIEMPRE en el shell, no adentro del chunk de colision. El
descarte que se busca es el del FRUSTUM (gratis, por AABB), no uno por
distancia: el chunk usa trigger_radius=15 con release_margin=6, y en un domo
donde se ve hasta 35 m atar el visual a esa esfera borra el andamiaje del otro
lado del anillo. Ademas StreamedSceneChunkV2 documenta el invariante inverso:
el visual vive en el shell para que un chunk jamas produzca un frame con
colision sin malla debajo.

No reserializa la escena (PackedScene.pack() sobre una instancia viva se lleva
puesto el estado); reescribe el TEXTO, mismo patron que
assemble_ringhub_stream_shell.py.

Uso: python3 tools/patch_ringhub_scaffold_visual.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVEL = ROOT / "core_v2/levels/RingHub_Level.tscn"
MANIFEST = ROOT / "core_v2/levels/interiors/RingHub_scaffold_sectors.json"


def main():
    text = LEVEL.read_text()
    if 'name="Visual" type="MeshInstance" parent="ScaffoldStreamRoot' not in text:
        raise SystemExit("no encontre los MeshInstance de grupo; ya esta parchado?")

    entries = json.loads(MANIFEST.read_text())
    by_group = {}
    for e in entries:
        by_group.setdefault(e["group"], []).append(e)
    for sectors in by_group.values():
        sectors.sort(key=lambda e: e["sector"])

    next_id = max(int(m) for m in re.findall(r"^\[ext_resource[^\n]*id=(\d+)\]", text, re.MULTILINE)) + 1
    new_ext = []
    dropped = []

    def replace_visual(m):
        nonlocal next_id
        group = m.group("group")
        dropped.append(int(m.group("id")))
        blocks = []
        for entry in by_group[group]:
            mesh_path = entry["mesh"]
            if not (ROOT / mesh_path.replace("res://", "")).exists():
                raise SystemExit("falta la malla de sector %s" % mesh_path)
            new_ext.append('[ext_resource path="%s" type="ArrayMesh" id=%d]\n' % (mesh_path, next_id))
            blocks.append(
                '\n[node name="Visual_%02d" type="MeshInstance" parent="ScaffoldStreamRoot/Group_%s"]\n'
                "layers = 64\nmesh = ExtResource( %d )\n" % (entry["sector"], group, next_id)
            )
            next_id += 1
        return "".join(blocks)

    text, n = re.subn(
        r'\n\[node name="Visual" type="MeshInstance" parent="ScaffoldStreamRoot/Group_(?P<group>\w+)"\]\n'
        r"layers = 64\nmesh = ExtResource\( (?P<id>\d+) \)\n",
        replace_visual,
        text,
    )
    if n != len(by_group):
        raise SystemExit("esperaba %d MeshInstance de grupo, reemplace %d" % (len(by_group), n))

    # Las mallas *_baked.mesh del anillo completo ya no las referencia nadie.
    for vid in dropped:
        text, k = re.subn(r'^\[ext_resource path="[^"]+" type="ArrayMesh" id=%d\]\n' % vid, "", text, flags=re.MULTILINE)
        if k != 1:
            raise SystemExit("no pude borrar el ext_resource id=%d de *_baked.mesh" % vid)

    first_sub = re.search(r"^\[sub_resource ", text, re.MULTILINE)
    text = text[: first_sub.start()] + "".join(new_ext) + text[first_sub.start():]

    total = len(re.findall(r"^\[ext_resource ", text, re.MULTILINE)) + len(
        re.findall(r"^\[sub_resource ", text, re.MULTILINE)
    )
    text = re.sub(r"^load_steps=\d+", "load_steps=%d" % (total + 1), text, count=1, flags=re.MULTILINE)

    LEVEL.write_text(text)
    print("MeshInstance de grupo reemplazados: %d" % n)
    print("MeshInstance de sector agregados: %d" % len(new_ext))
    print("load_steps=%d" % (total + 1))


if __name__ == "__main__":
    main()
