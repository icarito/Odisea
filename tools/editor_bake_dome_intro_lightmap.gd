tool
extends EditorScript

# Ejecutar desde el editor Godot 3 con Dome_Intro.tscn como escena activa:
# abrir este script y usar File > Run (Ctrl+Shift+X).
#
# Godot 3 sólo soporta BakedLightmap dentro del proceso del editor. Cada bake
# reemplaza el recurso activo; Git conserva los estados anteriores.
const EXPECTED_SCENE := "Dome_Intro"
const BAKE_PATH := "res://core_v2/levels/interiors/Dome_Intro.lmbake"

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
	# Todas las luces del rig participan como All, aunque sean invisibles: en
	# Godot 3 la visibilidad no decide el bake. El estado se restaura al final.
	rig.set("bake_rig_enabled", true)
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_ALL
	lightmap.quality = BakedLightmap.BAKE_QUALITY_LOW
	lightmap.atlas_generate = false # Dome_Intro excede un atlas 4096; funciona en GLES2.
	lightmap.use_denoiser = true
	print("[dome_lightmap] bake LOW, 2 bounces, 107 static lights -> ", BAKE_PATH)
	var result: int = lightmap.bake(dome, BAKE_PATH)
	rig.set("bake_rig_enabled", false)
	for child in rig.get_children():
		if child is Light:
			(child as Light).light_bake_mode = Light.BAKE_DISABLED
	if result != BakedLightmap.BAKE_ERROR_OK:
		push_error("[dome_lightmap] bake falló: %d" % result)
		return
	get_editor_interface().get_resource_filesystem().scan()
	get_editor_interface().mark_scene_as_unsaved()
	print("[dome_lightmap] PASS. El bake activo se actualizó; valida y crea el siguiente commit.")
