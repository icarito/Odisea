#!/bin/sh
# Regenera los 10 chunks de andamio: registro -> JSON -> Blender (GLB + preview) -> bake (.mesh + .tscn).
# Uso (desde la raiz del repo): tools/scaffold_chunks/build.sh [id ...]
#   BLENDER=/ruta/a/blender   (default: blender del PATH)
set -e
BLENDER="${BLENDER:-blender}"
GODOT="$(sh tools/godot_bin.sh)"
HERE=tools/scaffold_chunks

"$GODOT" --path . --no-window -s $HERE/export_registry.gd >/dev/null 2>&1
IDS="$*"
[ -n "$IDS" ] || IDS=$(python3 -c "import json;print(' '.join(json.load(open('$HERE/chunks.json'))['chunks']))")
for id in $IDS; do
	CHUNK=$id "$BLENDER" --background --python docs/skills/blender-bpy/scripts/render.py -- \
		--scene $HERE/scene_chunks.py --out $HERE/glb --res "${RES:-900}" 2>&1 | grep -E "RENDER_OK|GLB_OK|Error|Traceback" || true
done
# Kit de fondo del entrecasco (solo si no se pidieron chunks puntuales).
if [ -z "$*" ]; then
	for piece in hull_bay terrace_underside hull_pylon; do
		PIECE=$piece "$BLENDER" --background --python docs/skills/blender-bpy/scripts/render.py -- \
			--scene $HERE/scene_hull.py --out $HERE/glb --res "${RES:-900}" 2>&1 | grep -E "RENDER_OK|GLB_OK|Error|Traceback" || true
	done
fi
"$GODOT" --path . --no-window -s tools/bake_scaffold_chunks.gd 2>&1 | grep -E "\[bake_chunks\]|ERROR|SCRIPT" || true
