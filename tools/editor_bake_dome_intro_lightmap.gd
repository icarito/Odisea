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
	var directional: DirectionalLight = dome.get_node_or_null("DirectionalLight") as DirectionalLight
	var directional_shadow_enabled: bool = directional.shadow_enabled if directional != null else false
	var directional_bake_mode: int = directional.light_bake_mode if directional != null else Light.BAKE_DISABLED
	# Todas las luces del rig participan como All, aunque sean invisibles: en
	# Godot 3 la visibilidad no decide el bake. El estado se restaura al final.
	rig.set("bake_rig_enabled", true)
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_ALL
	# El usuario puede desactivar las sombras en runtime para inspeccionar solo
	# el resultado horneado. Durante el bake se fuerzan, sin persistir ese cambio.
	if directional != null:
		directional.light_bake_mode = Light.BAKE_ALL
		directional.shadow_enabled = true
	lightmap.quality = BakedLightmap.BAKE_QUALITY_LOW
	lightmap.atlas_generate = false # Dome_Intro excede un atlas 4096; funciona en GLES2.
	lightmap.use_denoiser = true
	# Dome_Intro no necesita rango HDR para sus fixtures industriales. LDR reduce
	# el tamaño del producto de bake sin perder las luces de color; no comprimir
	# el .lmbake externamente, porque debe seguir siendo un Resource de Godot.
	lightmap.use_hdr = false
	lightmap.use_color = true
	print("[dome_lightmap] bake LOW LDR/color, 2 bounces, 107 static lights -> ", BAKE_PATH)
	var result: int = lightmap.bake(dome, BAKE_PATH)
	rig.set("bake_rig_enabled", false)
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_DISABLED
	if directional != null:
		directional.light_bake_mode = directional_bake_mode
		directional.shadow_enabled = directional_shadow_enabled
	if result != BakedLightmap.BAKE_ERROR_OK:
		push_error("[dome_lightmap] bake falló: %d" % result)
		return
	var output := []
	var project_path: String = ProjectSettings.globalize_path("res://")
	var postprocess_result: int = OS.execute("make", ["--no-print-directory", "-C", project_path, POSTPROCESS_TARGET], true, output, true)
	if postprocess_result != 0:
		push_error("[dome_lightmap] bake listo, pero fallo el postproceso ImageMagick: %s" % PoolStringArray(output).join("\n"))
		return
	get_editor_interface().get_resource_filesystem().scan_sources()
	get_editor_interface().get_resource_filesystem().scan()
	get_editor_interface().mark_scene_as_unsaved()
	print("[dome_lightmap] PASS. El bake activo se actualizó; valida y crea el siguiente commit.")
