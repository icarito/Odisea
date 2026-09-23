#!/usr/bin/env python3
"""FD-314 - Ensambla el shell de streaming de RingHub_Level.tscn.

No reserializa la escena (PackedScene.pack() sobre una instancia viva se lleva
puesto el estado de runtime): reescribe el texto de RingHub_Level.tscn.

Hace tres cosas:
  1. Convierte los Item_N de Hub/Criopods (instancias de CriopodParallax con su
     StaticBody) en Spatial vacios con solo el transform. Siguen siendo los
     slots que lee RingHubWakeup y evitan que RadialScatter regenere el anillo;
     la geometria decorativa pasa al MultiMesh horneado.
  2. Agrega ScaffoldStreamRoot con un StreamedSceneChunkV2 por sector de scaffold
     (colision + su propio MeshInstance visual, ambos dentro de la misma
     sub-escena `_body.tscn` horneada — ver tools/bake_scaffold_walkways.gd) mas
     el visual MultiMesh de criopods.
  3. Cada chunk apunta a la sub-escena de sector que trae colision y visual
     juntos, mas el del anillo de criopods.

Los sectores viven en el espacio del grupo (el baker aplica group_xform_inv), asi
que cada grupo cuelga de un nodo con el transform del grupo y las anclas del
manifiesto son locales a ese nodo.

Uso: python3 tools/assemble_ringhub_stream_shell.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVEL = ROOT / "core_v2/levels/RingHub_Level.tscn"
MANIFEST = ROOT / "core_v2/levels/interiors/RingHub_scaffold_sectors.json"

CHUNK_SCRIPT = "res://core_v2/levels/chunks/StreamedSceneChunkV2.gd"
CRIO_VISUAL = "res://core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn"
CRIO_BODY = "res://core_v2/levels/chunks/ringhub/RingHub_Criopods_body.tscn"
GROUPS = ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
TRIGGER_RADIUS = 15.0
RELEASE_MARGIN = 6.0
CRIO_TRIGGER_RADIUS = 16.0
# Slot de despertar fijo: con el slot aleatorio (run_seed) el replay determinista del
# OYS flakeaba (el snapshot restaura el slot pero la colocacion inicial ya habia movido
# el pod). Fijo => mismo estado en vivo y en replay.
FORCED_WAKEUP_SLOT = 37

# Anillos de criopods de los pisos 2-5. El piso 1 (despertar) usa el anillo
# MultiMesh de Hub/Criopods; estos reutilizan la autoria de Dome
# (Criopods3..6 en DomeIntro_CriopodsSource.tscn), horneada con prefijo RingHub.
UPPER_CRIO_RINGS = [
    {"ring": "Criopods3", "y": 9},
    {"ring": "Criopods4", "y": 13.5},
    {"ring": "Criopods5", "y": 18},
    {"ring": "Criopods6", "y": 22.5},
]

# Pisos 2-5 del hub. RingHub ya trae Floor_1 como Hub/RingFloor; estos replican su
# estilo (sin hazard strip ni rail naranja) y toman de la torre de Dome las mismas
# aperturas por piso, que son las que reciben la escalera en espiral.
HUB_FLOORS = [
    {"n": 2, "y": 9, "openings": "[ Vector2( 284.945, 293.743 ), Vector2( 106.048, 123.196 ) ]", "docks": "[ 0.0, 0.45 ]"},
    {"n": 3, "y": 13.5, "openings": "[ Vector2( 338.772, 347.57 ), Vector2( 106.048, 123.196 ) ]", "docks": "[ 0.0, 0.45 ]"},
    {"n": 4, "y": 18, "openings": "[ Vector2( 32.5033, 41.3007 ), Vector2( 106.048, 123.196 ) ]", "docks": "[ 0.0, 0.45 ]"},
    {"n": 5, "y": 22.5, "openings": "[ Vector2( 90, 123 ) ]", "docks": "[ 0.0 ]"},
]


def transform_line(floats):
    vals = ", ".join(repr(float(v)) for v in floats)
    return "transform = Transform( %s )" % vals


def normalize_pilot_scale(text):
    """RingHub tenia al Pilot a 0.667 mientras el hub esta a 1:1 (igual que el de
    Dome). Con el pod funcional ya normalizado a 1.5, el personaje vuelve a escala
    1 conservando el origen autorado."""
    pattern = re.compile(
        r'(\[node name="Pilot" parent="\." instance=ExtResource\( 1 \)\]\ntransform = Transform\()([^)]*)(\))'
    )
    match = pattern.search(text)
    if match is None:
        return text
    nums = [n.strip() for n in match.group(2).split(",")]
    origin = ", ".join(nums[9:12])
    replacement = match.group(1) + "1, 0, 0, 0, 1, 0, 0, 0, 1, " + origin + match.group(3)
    return text[: match.start()] + replacement + text[match.end():]


def demote_criopod_items(text):
    lines = text.splitlines()
    out = []
    demoted = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^\[node name="(Item_\d+)" parent="Hub/Criopods" instance=ExtResource\( 9 \)\]$', line)
        if not m:
            out.append(line)
            i += 1
            continue
        demoted += 1
        out.append('[node name="%s" type="Spatial" parent="Hub/Criopods"]' % m.group(1))
        i += 1
        while i < len(lines) and lines[i].strip() != "":
            if lines[i].startswith("transform ="):
                out.append(lines[i])
            i += 1
        out.append("")
    return "\n".join(out), demoted


def main():
    text = LEVEL.read_text()
    if "ScaffoldStreamRoot" in text:
        sys.exit("RingHub_Level.tscn ya tiene ScaffoldStreamRoot; nada que hacer")
    entries = json.loads(MANIFEST.read_text())

    text, demoted = demote_criopod_items(text)
    text = normalize_pilot_scale(text)
    existing_ids = {
        m.group(1): int(m.group(2))
        for m in re.finditer(r'^\[ext_resource path="([^"]+)" type="[^"]*" id=(\d+)\]', text, re.MULTILINE)
    }
    hub_ring_id = existing_ids["res://core_v2/props/scaffold/ScaffoldHubRing.tscn"]

    ext = []  # (path, type)

    def add_ext(path, res_type):
        for idx, (existing, _t) in enumerate(ext):
            if existing == path:
                return idx
        ext.append((path, res_type))
        return len(ext) - 1

    # El id real arranca despues de los ext_resource que ya tiene la escena
    # (los ids existentes son 1..N, no 0..N-1).
    existing_ext = len(re.findall(r"^\[ext_resource ", text, re.MULTILINE))
    base = existing_ext + 1

    def ext_id(path, res_type):
        return base + add_ext(path, res_type)

    chunk_script_id = ext_id(CHUNK_SCRIPT, "Script")
    cri_visual_id = ext_id(CRIO_VISUAL, "PackedScene")
    cri_body_id = ext_id(CRIO_BODY, "PackedScene")
    upper_visual_ids = {
        r["ring"]: ext_id("res://core_v2/levels/chunks/ringhub/RingHub_%s_visual.tscn" % r["ring"], "PackedScene")
        for r in UPPER_CRIO_RINGS
    }
    upper_body_ids = {
        r["ring"]: ext_id("res://core_v2/levels/chunks/ringhub/RingHub_%s_body.tscn" % r["ring"], "PackedScene")
        for r in UPPER_CRIO_RINGS
    }
    body_ids = {}
    for e in entries:
        if e["body"]:
            body_ids[(e["group"], e["sector"])] = ext_id(e["body"], "PackedScene")

    lines = ["", '[node name="ScaffoldStreamRoot" type="Spatial" parent="."]', ""]
    for group in GROUPS:
        gx = next(e["group_transform"] for e in entries if e["group"] == group)
        lines.append('[node name="Group_%s" type="Spatial" parent="ScaffoldStreamRoot"]' % group)
        if gx != [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]:
            lines.append(transform_line(gx))
        lines.append("")
        # FD-314 follow-up: el visual del sector viaja DENTRO de `e["body"]` (el
        # baker ahora agrega un MeshInstance "Visual" junto a la colision, ver
        # tools/bake_scaffold_walkways.gd _write_sector_body). Ya no hay un
        # MeshInstance de grupo con la malla del anillo completo: esa malla unica
        # es justo lo que el frustum nunca podia descartar.
        for e in sorted([x for x in entries if x["group"] == group], key=lambda x: x["sector"]):
            if not e["body"]:
                continue
            lines.append('[node name="Chunk_%02d" type="Spatial" parent="ScaffoldStreamRoot/Group_%s"]' % (e["sector"], group))
            lines.append("script = ExtResource( %d )" % chunk_script_id)
            lines.append("chunk_scene = ExtResource( %d )" % body_ids[(group, e["sector"])])
            ax = e["anchor"]
            lines.append("trigger_center = Vector3( %s, %s, %s )" % tuple(repr(float(v)) for v in ax))
            lines.append("trigger_radius = %s" % repr(TRIGGER_RADIUS))
            lines.append("release_margin = %s" % repr(RELEASE_MARGIN))
            lines.append("")

    lines.append('[node name="Criopods_Visual" parent="ScaffoldStreamRoot" instance=ExtResource( %d )]' % cri_visual_id)
    lines.append("")
    lines.append('[node name="Chunk_Criopods" type="Spatial" parent="ScaffoldStreamRoot"]')
    lines.append("script = ExtResource( %d )" % chunk_script_id)
    lines.append("chunk_scene = ExtResource( %d )" % cri_body_id)
    lines.append("trigger_center = Vector3( 0, 4.5, 0 )")
    lines.append("trigger_radius = %s" % repr(CRIO_TRIGGER_RADIUS))
    lines.append("release_margin = %s" % repr(RELEASE_MARGIN))
    lines.append("")

    # Anillos de criopods de los pisos 2-5 (visual siempre presente, colision por
    # chunk). El nodo del anillo ya trae su propio transform (y=9/13.5/18/22.5).
    for entry in UPPER_CRIO_RINGS:
        lines.append('[node name="Criopods_Visual_%s" parent="ScaffoldStreamRoot" instance=ExtResource( %d )]'
                     % (entry["ring"], upper_visual_ids[entry["ring"]]))
        lines.append("")
        lines.append('[node name="Chunk_%s" type="Spatial" parent="ScaffoldStreamRoot"]' % entry["ring"])
        lines.append("script = ExtResource( %d )" % chunk_script_id)
        lines.append("chunk_scene = ExtResource( %d )" % upper_body_ids[entry["ring"]])
        lines.append("trigger_center = Vector3( 0, %s, 0 )" % repr(entry["y"]))
        lines.append("trigger_radius = %s" % repr(CRIO_TRIGGER_RADIUS))
        lines.append("release_margin = %s" % repr(RELEASE_MARGIN))
        lines.append("")

    # Pisos 2-5 del hub. Se cuelgan de Hub, junto a RingFloor (Floor_1), para que
    # la escalera en espiral tenga destino en cada nivel.
    for floor in HUB_FLOORS:
        lines.append('[node name="Floor_%d" parent="Hub" instance=ExtResource( %d )]' % (floor["n"], hub_ring_id))
        lines.append("transform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0 )" % repr(floor["y"]))
        lines.append("outer_radius = 13.0")
        lines.append("inner_radius = 6.0")
        lines.append("support_base_local_y = -4.5")
        lines.append("outer_openings_deg = %s" % floor["openings"])
        lines.append("outer_opening_docks = %s" % floor["docks"])
        lines.append("rebuild_baked_items = true")
        lines.append("")

    # Fija el slot de despertar en la raiz (script RingHubWakeup).
    text = re.sub(r'(\[node name="RingHub_Level" type="Spatial"\]\nscript = ExtResource\( \d+ \)\n)',
                  r'\1forced_slot = %d\n' % FORCED_WAKEUP_SLOT, text, count=1)

    # Inserta los ext_resource nuevos justo antes del primer sub_resource.
    first_sub = re.search(r"^\[sub_resource ", text, re.MULTILINE)
    if first_sub is None:
        sys.exit("no encontre sub_resource en la escena")
    ext_block = "".join(
        '[ext_resource path="%s" type="%s" id=%d]\n' % (p, t, base + i) for i, (p, t) in enumerate(ext)
    )
    text = text[: first_sub.start()] + ext_block + text[first_sub.start():]

    text = text.rstrip("\n") + "\n" + "\n".join(lines)

    total = len(re.findall(r"^\[ext_resource ", text, re.MULTILINE)) + len(
        re.findall(r"^\[sub_resource ", text, re.MULTILINE)
    )
    text = re.sub(r"^load_steps=\d+", "load_steps=%d" % (total + 1), text, count=1, flags=re.MULTILINE)

    LEVEL.write_text(text)
    print("items demovidos: %d" % demoted)
    print("ext_resource nuevos: %d" % len(ext))
    print("chunks de sector: %d" % len(body_ids))
    print("load_steps=%d" % (total + 1))


if __name__ == "__main__":
    main()
