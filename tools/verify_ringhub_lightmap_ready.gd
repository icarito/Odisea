extends SceneTree

# verify_ringhub_lightmap_ready.gd — O28: valida que RingHub_Level quede listo
# para hornear su BakedLightmap, sin hornearlo (el bake real necesita el editor).
#
# Chequea, en este orden:
#   1. La escena carga headless y trae un nodo BakedLightmap en modo interior
#      (environment_mode != DISABLED) con un light_data (RingHub.lmbake propio).
#   2. Todo MeshInstance con use_in_baked_light=true tiene UV2 en TODAS sus
#      surfaces (una malla con UV2 solo en algunas surfaces se hornea incompleta).
#   3. RingHub_BakeLights.tscn existe, trae luces y ninguna ilumina en runtime
#      (visible=false y light_bake_mode=DISABLED).
#
# Uso: tools/godot --path . --no-window -s tools/verify_ringhub_lightmap_ready.gd
# Exit code != 0 si algo falta.

const LEVEL_PATH := "res://core_v2/levels/RingHub_Level.tscn"
const RIG_PATH := "res://core_v2/levels/RingHub_BakeLights.tscn"

var _failures := []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_level()
	_check_rig()
	if _failures.empty():
		print("[ringhub_lightmap_ready] PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[ringhub_lightmap_ready] %s" % failure)
	quit(1)


func _check_level() -> void:
	var packed: PackedScene = load(LEVEL_PATH)
	if packed == null:
		_fail("no pude cargar %s" % LEVEL_PATH)
		return
	var level: Node = packed.instance()
	var baked: BakedLightmap = null
	for node in _walk(level):
		if node is BakedLightmap:
			baked = node as BakedLightmap
			break
	if baked == null:
		_fail("falta el nodo BakedLightmap")
		return
	if baked.environment_mode == BakedLightmap.ENVIRONMENT_MODE_DISABLED:
		_fail("BakedLightmap.environment_mode esta DISABLED (el domo no aportaria ambiente)")
	if baked.light_data == null:
		_fail("BakedLightmap.light_data es null; falta res://core_v2/levels/RingHub.lmbake")
	var baked_count := 0
	var missing := []
	for node in _walk(level):
		if not (node is MeshInstance and node.use_in_baked_light and node.mesh != null):
			continue
		baked_count += 1
		var missing_surfaces := 0
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			var has_uv2: bool = arrays.size() > Mesh.ARRAY_TEX_UV2 \
				and arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() > 0
			if not has_uv2:
				missing_surfaces += 1
		if missing_surfaces > 0:
			missing.append("%s (%d/%d surfaces sin UV2)" % [
				node.name, missing_surfaces, node.mesh.get_surface_count()])
	if not missing.empty():
		_fail("mallas use_in_baked_light sin UV2: " + PoolStringArray(missing).join(", "))
	else:
		print("[ringhub_lightmap_ready] %d mallas horneables con UV2 completo" % baked_count)


func _check_rig() -> void:
	if not ResourceLoader.exists(RIG_PATH):
		_fail("falta %s" % RIG_PATH)
		return
	var packed: PackedScene = load(RIG_PATH)
	if packed == null:
		_fail("no pude cargar %s" % RIG_PATH)
		return
	var rig: Node = packed.instance()
	var total := 0
	for node in _walk(rig):
		if not (node is Light):
			continue
		var light := node as Light
		total += 1
		if light.visible:
			_fail("luz de bake visible en runtime: %s" % light.name)
		if light.light_bake_mode != Light.BAKE_DISABLED:
			_fail("luz de bake con bake_mode distinto de DISABLED: %s" % light.name)
	if total == 0:
		_fail("el rig de bake no tiene luces")
	else:
		print("[ringhub_lightmap_ready] rig: %d luces, todas apagadas en runtime" % total)


func _walk(root: Node) -> Array:
	var out := []
	var stack: Array = [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.push_back(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
