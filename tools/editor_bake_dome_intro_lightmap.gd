tool
extends EditorScript

# Ejecutar desde el editor Godot 3 con la escena de domo como escena activa:
# abrir este script y usar File > Run (Ctrl+Shift+X).
#
# Godot 3 sólo soporta BakedLightmap dentro del proceso del editor.
#
# FD-284: el destino ya no está hardcodeado. El modo sale de la variable de
# entorno DOME_BAKE_MODE (full|dark, default full) y el nombre de la escena del
# nodo raíz, así que Dome_Prologue —u otra escena de domo que gane un
# BakedLightmap— hornea a su propio archivo sin tocar este script.
#
#   full  Rig completo (107 fixtures) + DirectionalLight. Estado PLENO.
#   dark  Sin rig y sin DirectionalLight: solo el ambiente de la escena, a menor
#         resolución. Estado OSCURAS, y la base sobre la que BAJO CONSUMO pone
#         su pool runtime de luces cercanas.
#
# Cada modo hornea a su propia carpeta porque BakedLightmap con atlas apagado
# escribe un PNG por MeshInstance junto al .lmbake: compartir carpeta haría que
# el dark pisara las texturas del full.
#
#   res://core_v2/levels/interiors/lightmaps/<modo>/<Escena>.lmbake
#
# El bake histórico res://core_v2/levels/interiors/Dome_Intro.lmbake NO se toca:
# queda como respaldo y sigue siendo el que la escena referencia por defecto.

const BAKE_DIR := "res://core_v2/levels/interiors/lightmaps"
const MODE_ENV := "DOME_BAKE_MODE"
const POSTPROCESS_TARGET := "bake-lightmap-postprocess"
# Resolución del bake oscuro. Sin fixtures no hay detalle que preservar, así que
# 4 texels/unidad contra los 16 del full recorta el producto sin pérdida visible.
const DARK_TEXELS_PER_UNIT := 4
const DARK_BOUNCES := 1

func _run() -> void:
	var mode: String = OS.get_environment(MODE_ENV).strip_edges().to_lower()
	if mode == "":
		mode = "full"
	if not mode in ["full", "dark"]:
		push_error("[dome_lightmap] %s inválido: '%s' (full|dark)" % [MODE_ENV, mode])
		return

	var dome: Node = get_scene()
	if dome == null:
		push_error("[dome_lightmap] no hay escena activa.")
		return
	var lightmap: BakedLightmap = dome.get_node_or_null("BakedLightmap") as BakedLightmap
	if lightmap == null:
		push_error("[dome_lightmap] %s no tiene un nodo BakedLightmap." % dome.name)
		return

	var bake_path: String = "%s/%s/%s.lmbake" % [BAKE_DIR, mode, dome.name]
	var directory := Directory.new()
	if directory.make_dir_recursive(bake_path.get_base_dir()) != OK:
		push_error("[dome_lightmap] no pude crear %s" % bake_path.get_base_dir())
		return

	var missing_uv2: Array = []
	_collect_missing_uv2(dome, missing_uv2)
	if not missing_uv2.empty():
		push_error("[dome_lightmap] bake cancelado: faltan UV2 en " + PoolStringArray(missing_uv2).join(", "))
		return

	var directional: DirectionalLight = dome.get_node_or_null("DirectionalLight") as DirectionalLight
	var directional_state := {}
	if directional != null:
		directional_state = {
			"visible": directional.visible,
			"shadow_enabled": directional.shadow_enabled,
			"light_bake_mode": directional.light_bake_mode,
		}

	var rig: Node = null
	var temporary_rig: Node = null
	var bake_light_count := 0
	if mode == "full":
		rig = dome.get_node_or_null("DomeIntroBakeLights")
		if rig == null:
			push_error("[dome_lightmap] falta DomeIntroBakeLights.")
			return
		# El rig se guarda como InstancePlaceholder para no crear 107 luces en
		# runtime. Un placeholder no tiene hijos, así que materializarlo solo para
		# el pase de bake es imprescindible; la instancia temporal se libera al final.
		if rig is InstancePlaceholder:
			temporary_rig = (rig as InstancePlaceholder).create_instance(false)
			if temporary_rig == null:
				push_error("[dome_lightmap] no pude materializar DomeIntroBakeLights para el bake.")
				return
			rig = temporary_rig
		# Todas las luces del rig participan como All, aunque sean invisibles: en
		# Godot 3 la visibilidad no decide el bake. El estado se restaura al final.
		rig.set("bake_rig_enabled", true)
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
	elif directional != null:
		# Modo dark: ni fixtures ni sol. Queda el ambiente de environment_mode.
		directional.light_bake_mode = Light.BAKE_DISABLED

	var lightmap_state := {
		"quality": lightmap.quality,
		"atlas_generate": lightmap.get("atlas_generate"),
		"use_denoiser": lightmap.use_denoiser,
		"use_hdr": lightmap.use_hdr,
		"use_color": lightmap.use_color,
		"bounces": lightmap.bounces,
		"default_texels_per_unit": lightmap.default_texels_per_unit,
		"light_data": lightmap.light_data,
	}
	# Las barras y plataformas de ScaffoldHubTower proyectan sombras estrechas.
	# LOW + denoiser las suaviza hasta borrarlas sobre la terraza; MEDIUM conserva
	# esa penumbra sin afectar el coste de render en runtime.
	lightmap.quality = BakedLightmap.BAKE_QUALITY_MEDIUM
	lightmap.set("atlas_generate", false) # Dome_Intro excede un atlas 4096; funciona en GLES2.
	lightmap.use_denoiser = true
	# Dome_Intro no necesita rango HDR para sus fixtures industriales. LDR reduce
	# el tamaño del producto de bake sin perder las luces de color; no comprimir
	# el .lmbake externamente, porque debe seguir siendo un Resource de Godot.
	lightmap.use_hdr = false
	lightmap.use_color = true
	if mode == "dark":
		lightmap.quality = BakedLightmap.BAKE_QUALITY_LOW
		lightmap.bounces = DARK_BOUNCES
		lightmap.default_texels_per_unit = DARK_TEXELS_PER_UNIT

	print("[dome_lightmap] bake mode=%s, %d static lights -> %s" % [mode, bake_light_count, bake_path])
	var result: int = lightmap.bake(dome, bake_path)

	if rig != null:
		rig.set("bake_rig_enabled", false)
		for child in rig.get_children():
			if child is Light:
				(child as Light).light_bake_mode = Light.BAKE_DISABLED
	if directional != null:
		directional.visible = directional_state["visible"]
		directional.light_bake_mode = directional_state["light_bake_mode"]
		directional.shadow_enabled = directional_state["shadow_enabled"]
	if temporary_rig != null:
		temporary_rig.free()
	# bake() deja su producto en light_data. La escena tiene que seguir enviando
	# el bake que ya referencia: DomeLightState hace el swap en runtime, y dejar
	# el .lmbake oscuro pegado a la escena la enviaría a oscuras siempre.
	for key in lightmap_state:
		lightmap.set(key, lightmap_state[key])

	if result != BakedLightmap.BAKE_ERROR_OK:
		push_error("[dome_lightmap] bake falló: %d" % result)
		return

	var output := []
	var project_path: String = ProjectSettings.globalize_path("res://")
	var relative_bake: String = bake_path.replace("res://", "")
	var postprocess_result: int = OS.execute("make", [
		"--no-print-directory", "-C", project_path, POSTPROCESS_TARGET,
		"DOME_LIGHTMAP_FORCE=1",
		"DOME_LIGHTMAP_DATA_PATH=%s" % relative_bake,
		"DOME_LIGHTMAP_STAMP_DIR=build/lightmap-postprocess/%s" % mode,
		"DOME_LIGHTMAP_RAW_DIR=build/lightmap-raw/%s" % mode,
	], true, output, true)
	if postprocess_result != 0:
		push_error("[dome_lightmap] bake listo, pero falló el postproceso ImageMagick: %s" % PoolStringArray(output).join("\n"))
		return
	get_editor_interface().get_resource_filesystem().scan_sources()
	get_editor_interface().get_resource_filesystem().scan()
	print("[dome_lightmap] PASS. %s actualizado; valida y crea el siguiente commit." % bake_path)


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
