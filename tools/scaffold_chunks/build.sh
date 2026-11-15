#!/bin/sh
# Regenera los chunks de andamio en todos los escalones de gravedad y el kit del entrecasco:
# registro -> JSON -> Blender (GLB + preview) -> bake (.mesh + .tscn).
# Uso (desde la raiz del repo): tools/scaffold_chunks/build.sh [id ...]
#   BLENDER=/ruta/a/blender   (default: blender del PATH)
set -e
BLENDER="${BLENDER:-blender}"
GODOT="$(sh tools/godot_bin.sh)"
HERE=tools/scaffold_chunks
RUN="docs/skills/blender-bpy/scripts/render.py"

"$GODOT" --path . --no-window -s $HERE/export_registry.gd >/dev/null 2>&1
for json in $HERE/chunks.json $HERE/chunks_g*.json; do
	tier=$(basename "$json" .json | sed 's/^chunks_\{0,1\}//')
	IDS="$*"
	[ -n "$IDS" ] || IDS=$(python3 -c "import json;print(' '.join(json.load(open('$json'))['chunks']))")
	for id in $IDS; do
		python3 -c "import json,sys;sys.exit(0 if '$id' in json.load(open('$json'))['chunks'] else 1)" || continue
		CHUNK=$id TIER=$tier "$BLENDER" --background --python $RUN -- \
			--scene $HERE/scene_chunks.py --out $HERE/glb --res "${RES:-900}" 2>&1 | grep -E "GLB_OK|Error|Traceback" || true
	done
done
# Kit de fondo del entrecasco (solo si no se pidieron chunks puntuales).
if [ -z "$*" ]; then
	for piece in hull_bay terrace_underside hull_pylon; do
		PIECE=$piece "$BLENDER" --background --python $RUN -- \
			--scene $HERE/scene_hull.py --out $HERE/glb --res "${RES:-900}" 2>&1 | grep -E "GLB_OK|Error|Traceback" || true
	done
fi
"$GODOT" --path . --no-window -s tools/bake_scaffold_chunks.gd 2>&1 | grep -E "\[bake_chunks\]|ERROR|SCRIPT" || true
