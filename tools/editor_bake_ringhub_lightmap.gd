tool
extends EditorScript

# editor_bake_ringhub_lightmap.gd — O28: hornea el BakedLightmap de RingHub_Level.
#
# Ejecutar desde el editor Godot 3 con RingHub_Level.tscn como escena activa:
# abrir este script y usar File > Run (Ctrl+Shift+X). Godot 3 solo puede hornear
# BakedLightmap dentro del proceso del editor.
#
# Es el analogo de editor_bake_dome_intro_lightmap.gd para RingHub. Diferencias:
#   - El rig de luces es RingHubBakeLights (RingHub_BakeLights.tscn), generado por
#     tools/generate_ringhub_bake_lights.gd. A diferencia de Dome_Intro no hay
#     modos full/dark: RingHub tiene UN solo bake y el estado DARK/LIT lo hace
#     RingHubLightState moviendo BakedLightmapData.energy (LIT=1, DARK=0).
#   - El light_data destino es el que la escena ya referencia
#     (res://core_v2/levels/RingHub.lmbake). El script lo crea vacio si falta,
#     para que el primer bake no requiera un paso manual previo.
#   - El DirectionalLight no esta en la raiz: se busca el primero del arbol
#     (RingHub tiene WorldEnvironment/Sun).
#   - El postproceso ImageMagick corre con las mismas perillas que Dome_Intro pero
#     con sus propias carpetas de sello/crudo (build/lightmap-*/ringhub), porque
#     los PNG por malla se llaman distinto pero se reusan entre corridas.
#
# Al terminar OK deja RingHub.lmbake actualizado + sus PNG tintados. Despues:
#   tools/godot --path . --no-window -s tools/verify_ringhub_lightmap_ready.gd

const BAKE_POSTPROCESS_TARGET := "bake-lightmap-postprocess"
const FALLBACK_BAKE_PATH := "res://core_v2/levels/RingHub.lmbake"
const RIG_NAME := "RingHubBakeLights"
# Mismo criterio que Dome_Intro: MEDIUM conserva la penumbra de las plataformas
# sin coste de render en runtime; denoiser suaviza el escalonado.
const BAKE_QUALITY := BakedLightmap.BAKE_QUALITY_MEDIUM


func _run() -> void:
	var level: Node = get_scene()
	if level == null:
		push_error("[ringhub_lightmap] no hay escena activa.")
		return
	var lightmap: BakedLightmap = _find_baked(level)
	if lightmap == null:
		push_error("[ringhub_lightmap] %s no tiene un nodo BakedLightmap." % level.name)
		return

	# El bake in situ necesita un light_data con ruta. Si la escena todavia no lo
	# trae (primer bake), se crea vacio en la ruta fallback.
	if lightmap.light_data == null or lightmap.light_data.resource_path == "":
		var fresh := BakedLightmapData.new()
		if ResourceSaver.save(FALLBACK_BAKE_PATH, fresh) != OK:
			push_error("[ringhub_lightmap] no pude crear %s" % FALLBACK_BAKE_PATH)
			return
		lightmap.light_data = load(FALLBACK_BAKE_PATH)
	var bake_path: String = lightmap.light_data.resource_path

	var missing_uv2: Array = []
	_collect_missing_uv2(level, missing_uv2)
	if not missing_uv2.empty():
		push_error("[ringhub_lightmap] bake cancelado: faltan UV2 en " + PoolStringArray(missing_uv2).join(", "))
		return

	var directional: DirectionalLight = _find_directional(level)
	var directional_state := {}
	if directional != null:
		directional_state = {
			"visible": directional.visible,
			"shadow_enabled": directional.shadow_enabled,
			"light_bake_mode": directional.light_bake_mode,
		}

	var rig: Node = level.get_node_or_null(RIG_NAME)
	if rig == null:
		push_error("[ringhub_lightmap] falta %s." % RIG_NAME)
		return

	# El rig se guarda como InstancePlaceholder. Un placeholder no tiene hijos; hay
	# que materializarlo solo para el pase de bake y liberar la instancia temporal.
	var temporary_rig: Node = null
	if rig is InstancePlaceholder:
		temporary_rig = (rig as InstancePlaceholder).create_instance(false)
		if temporary_rig == null:
			push_error("[ringhub_lightmap] no pude materializar %s para el bake." % RIG_NAME)
			return
		rig = temporary_rig
	if rig.get_script() != null and "bake_rig_enabled" in rig:
		rig.set("bake_rig_enabled", true)
	var bake_light_count := 0
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_ALL
			bake_light_count += 1
	if bake_light_count == 0:
		if temporary_rig != null:
			temporary_rig.free()
		push_error("[ringhub_lightmap] el rig de bake no contiene luces materializadas.")
		return
	if directional != null:
		directional.visible = true
		directional.light_bake_mode = Light.BAKE_ALL
		directional.shadow_enabled = true

	var lightmap_state := {
		"quality": lightmap.quality,
		"atlas_generate": lightmap.get("atlas_generate"),
		"use_denoiser": lightmap.use_denoiser,
		"use_hdr": lightmap.use_hdr,
		"use_color": lightmap.use_color,
		"bounces": lightmap.bounces,
		"default_texels_per_unit": lightmap.default_texels_per_unit,
		"capture_enabled": lightmap.capture_enabled,
		"light_data": lightmap.light_data,
	}
	# La capture (octree) es el 99.99% del .lmbake y no aporta en GLES3/GLES2 aca.
	lightmap.capture_enabled = false
	lightmap.quality = BAKE_QUALITY
	# RingHub supera un atlas 4096 si se activa: atlas off, un PNG por malla.
	lightmap.set("atlas_generate", false)
	lightmap.use_denoiser = true
	# LDR: sin rango HDR no se pierde nada en fixtures industriales y baja el peso.
	lightmap.use_hdr = false
	lightmap.use_color = true

	print("[ringhub_lightmap] bake: %d static lights -> %s" % [bake_light_count, bake_path])
	var result: int = lightmap.bake(level, bake_path)

	if temporary_rig != null:
		temporary_rig.free()
	elif rig.get_script() != null and "bake_rig_enabled" in rig:
		rig.set("bake_rig_enabled", false)
	if directional != null:
		directional.visible = directional_state["visible"]
		directional.light_bake_mode = directional_state["light_bake_mode"]
		directional.shadow_enabled = directional_state["shadow_enabled"]
	# El bake horneo in situ: se conserva el light_data nuevo; se restauran el resto
	# de las perillas para no ensuciar la escena con los valores del bake.
	for key in lightmap_state:
		if key == "light_data":
			continue
		lightmap.set(key, lightmap_state[key])

	if result != BakedLightmap.BAKE_ERROR_OK:
		push_error("[ringhub_lightmap] bake fallo: %d" % result)
		return

	_run_postprocess(bake_path)
	get_editor_interface().get_resource_filesystem().scan_sources()
	get_editor_interface().get_resource_filesystem().scan()
	print("[ringhub_lightmap] PASS. %s actualizado; valida y crea el siguiente commit." % bake_path)


func _run_postprocess(bake_path: String) -> void:
	var output := []
	var project_path: String = ProjectSettings.globalize_path("res://")
	var relative_bake: String = bake_path.replace("res://", "")
	# El dump del .lmbake comprimido lo hace Godot: fijar GODOT_BIN al propio editor
	# evita depender de que `godot3-bin` este en el PATH.
	OS.set_environment("GODOT_BIN", OS.get_executable_path())
	var postprocess_result: int = OS.execute("make", [
		"--no-print-directory", "-C", project_path, BAKE_POSTPROCESS_TARGET,
		"DOME_LIGHTMAP_FORCE=1",
		"DOME_LIGHTMAP_DATA_PATH=%s" % relative_bake,
		"DOME_LIGHTMAP_STAMP_DIR=build/lightmap-postprocess/ringhub",
		"DOME_LIGHTMAP_RAW_DIR=build/lightmap-raw/ringhub",
	], true, output, true)
	if postprocess_result != 0:
		push_error("[ringhub_lightmap] bake listo, pero fallo el postproceso ImageMagick: %s" % PoolStringArray(output).join("\n"))


func _find_baked(node: Node) -> BakedLightmap:
	if node is BakedLightmap:
		return node as BakedLightmap
	for child in node.get_children():
		var found := _find_baked(child)
		if found != null:
			return found
	return null


func _find_directional(node: Node) -> DirectionalLight:
	if node is DirectionalLight:
		return node as DirectionalLight
	for child in node.get_children():
		var found := _find_directional(child)
		if found != null:
			return found
	return null


func _collect_missing_uv2(node: Node, missing_uv2: Array) -> void:
	if node is MeshInstance and node.use_in_baked_light and node.mesh != null:
		var missing_surfaces := 0
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			if not (arrays.size() > Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() > 0):
				missing_surfaces += 1
		if missing_surfaces > 0:
			missing_uv2.append("%s (%d/%d surfaces sin UV2)" % [node.name, missing_surfaces, node.mesh.get_surface_count()])
	for child in node.get_children():
		_collect_missing_uv2(child, missing_uv2)
