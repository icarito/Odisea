tool
extends EditorScript

# Ejecutar desde el editor Godot 3 con Dome_Intro.tscn como escena activa:
# abrir este script y usar File > Run (Ctrl+Shift+X).
#
# Godot 3 sólo soporta BakedLightmap dentro del proceso del editor. Cada bake
# reemplaza el recurso activo; Git conserva los estados anteriores.
const EXPECTED_SCENE := "Dome_Intro"
const BAKE_PATH := "res://core_v2/levels/interiors/Dome_Intro.lmbake"
const POSTPROCESS_TARGET := "bake-lightmap-postprocess"

func _run() -> void:
	var dome: Node = get_scene()
	if dome == null or dome.name != EXPECTED_SCENE:
		push_error("[dome_lightmap] abre Dome_Intro.tscn y vuelve a ejecutar este script.")
		return
	var rig: Node = dome.get_node_or_null("DomeIntroBakeLights")
	var lightmap: BakedLightmap = dome.get_node_or_null("BakedLightmap") as BakedLightmap
	if rig == null or lightmap == null:
		push_error("[dome_lightmap] faltan DomeIntroBakeLights o BakedLightmap.")
		return
	# DomeIntro guarda este rig como InstancePlaceholder para no crear 107 luces
	# en runtime. Un placeholder no tiene hijos, asi que materializarlo solo para
	# el pase de bake es imprescindible; la instancia temporal se libera al final.
	var temporary_rig: Node = null
	if rig is InstancePlaceholder:
		temporary_rig = (rig as InstancePlaceholder).create_instance(false)
		if temporary_rig == null:
			push_error("[dome_lightmap] no pude materializar DomeIntroBakeLights para el bake.")
			return
		rig = temporary_rig
	var missing_uv2: Array = []
	_collect_missing_uv2(dome, missing_uv2)
	if not missing_uv2.empty():
		push_error("[dome_lightmap] bake cancelado: faltan UV2 en " + PoolStringArray(missing_uv2).join(", "))
		return
	var directional: DirectionalLight = dome.get_node_or_null("DirectionalLight") as DirectionalLight
	var directional_visible: bool = directional.visible if directional != null else false
	var directional_shadow_enabled: bool = directional.shadow_enabled if directional != null else false
	var directional_bake_mode: int = directional.light_bake_mode if directional != null else Light.BAKE_DISABLED
	# Todas las luces del rig participan como All, aunque sean invisibles: en
	# Godot 3 la visibilidad no decide el bake. El estado se restaura al final.
	rig.set("bake_rig_enabled", true)
	var bake_light_count: int = 0
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_ALL
			bake_light_count += 1
	if bake_light_count == 0:
		if temporary_rig != null:
			temporary_rig.free()
		push_error("[dome_lightmap] el rig de bake no contiene luces materializadas.")
		return
	# El usuario puede desactivar las sombras en runtime para inspeccionar solo
	# el resultado horneado. Durante el bake se fuerzan, sin persistir ese cambio.
	if directional != null:
		directional.visible = true
		directional.light_bake_mode = Light.BAKE_ALL
		directional.shadow_enabled = true
	# Las barras y plataformas de ScaffoldHubTower proyectan sombras estrechas.
	# LOW + denoiser las suaviza hasta borrarlas sobre la terraza; MEDIUM conserva
	# esa penumbra sin afectar el coste de render en runtime.
	lightmap.quality = BakedLightmap.BAKE_QUALITY_MEDIUM
	lightmap.atlas_generate = false # Dome_Intro excede un atlas 4096; funciona en GLES2.
	lightmap.use_denoiser = true
	# Dome_Intro no necesita rango HDR para sus fixtures industriales. LDR reduce
	# el tamaño del producto de bake sin perder las luces de color; no comprimir
	# el .lmbake externamente, porque debe seguir siendo un Resource de Godot.
	lightmap.use_hdr = false
	lightmap.use_color = true
	print("[dome_lightmap] bake MEDIUM LDR/color, 2 bounces, %d static lights + DirectionalLight -> %s" % [bake_light_count, BAKE_PATH])
	var result: int = lightmap.bake(dome, BAKE_PATH)
	rig.set("bake_rig_enabled", false)
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_DISABLED
	if directional != null:
		directional.visible = directional_visible
		directional.light_bake_mode = directional_bake_mode
		directional.shadow_enabled = directional_shadow_enabled
	if temporary_rig != null:
		temporary_rig.free()
	if result != BakedLightmap.BAKE_ERROR_OK:
		push_error("[dome_lightmap] bake falló: %d" % result)
		return
	var output := []
	var project_path: String = ProjectSettings.globalize_path("res://")
	var postprocess_result: int = OS.execute("make", ["--no-print-directory", "-C", project_path, POSTPROCESS_TARGET, "DOME_LIGHTMAP_FORCE=1"], true, output, true)
	if postprocess_result != 0:
		push_error("[dome_lightmap] bake listo, pero fallo el postproceso ImageMagick: %s" % PoolStringArray(output).join("\n"))
		return
	get_editor_interface().get_resource_filesystem().scan_sources()
	get_editor_interface().get_resource_filesystem().scan()
	get_editor_interface().mark_scene_as_unsaved()
	print("[dome_lightmap] PASS. El bake activo se actualizó; valida y crea el siguiente commit.")


func _collect_missing_uv2(node: Node, missing_uv2: Array) -> void:
	if node is MeshInstance and node.use_in_baked_light and node.mesh != null:
		# Todas las surfaces necesitan UV2: una malla con UV2 solo en una surface
		# (ej. la tira hazard del hub) se hornea incompleta y no proyecta sombra.
		var missing_surfaces := 0
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			if not (arrays.size() > Mesh.ARRAY_TEX_UV2 and arrays[Mesh.ARRAY_TEX_UV2] != null and arrays[Mesh.ARRAY_TEX_UV2].size() > 0):
				missing_surfaces += 1
		if missing_surfaces > 0:
			missing_uv2.append("%s (%d/%d surfaces sin UV2)" % [node.name, missing_surfaces, node.mesh.get_surface_count()])
	for child in node.get_children():
		_collect_missing_uv2(child, missing_uv2)
