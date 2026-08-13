extends SceneTree

# Activa o desactiva las luces exclusivas del BakedLightmap sin alterar los
# pools de runtime. Ejecutar antes y después del bake en el editor:
#   ODISEA_BAKE_LIGHTS=1 godot3-bin --no-window -s tools/set_dome_intro_bake_lights.gd
#   # Bake Lightmaps en el editor
#   ODISEA_BAKE_LIGHTS=0 godot3-bin --no-window -s tools/set_dome_intro_bake_lights.gd

const RIG_PATH := "res://core_v2/levels/interiors/DomeIntro_BakeLights.tscn"

func _init() -> void:
	var requested := OS.get_environment("ODISEA_BAKE_LIGHTS")
	if requested != "0" and requested != "1":
		push_error("[bake_lights] ODISEA_BAKE_LIGHTS must be 0 or 1")
		quit(1)
		return
	var packed := load(RIG_PATH) as PackedScene
	if packed == null:
		push_error("[bake_lights] missing %s" % RIG_PATH)
		quit(1)
		return
	var rig := packed.instance()
	var enabled := requested == "1"
	rig.set("bake_rig_enabled", enabled)
	for child in rig.get_children():
		if child is Light:
			var light := child as Light
			light.light_bake_mode = 2 if enabled else 0
			light.visible = false
	var output := PackedScene.new()
	if output.pack(rig) != OK or ResourceSaver.save(RIG_PATH, output) != OK:
		push_error("[bake_lights] could not save %s" % RIG_PATH)
		quit(1)
		return
	print("[bake_lights] %s: %d lights" % ["enabled for bake" if enabled else "disabled for runtime", rig.get_child_count()])
	quit(0)
