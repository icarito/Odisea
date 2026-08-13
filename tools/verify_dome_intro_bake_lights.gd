extends SceneTree

const RIG_PATH := "res://core_v2/levels/interiors/DomeIntro_BakeLights.tscn"
const EXPECTED_LIGHTS := 107

func _init() -> void:
	var scene := load(RIG_PATH) as PackedScene
	if scene == null:
		push_error("[verify_bake_lights] missing %s" % RIG_PATH)
		quit(1)
		return
	var rig := scene.instance()
	var count := 0
	for child in rig.get_children():
		if not (child is OmniLight):
			continue
		var light := child as OmniLight
		if light.visible or light.light_bake_mode != 0:
			push_error("[verify_bake_lights] runtime-active bake light: %s" % light.name)
			quit(1)
			return
		count += 1
	if count != EXPECTED_LIGHTS:
		push_error("[verify_bake_lights] expected %d lights, found %d" % [EXPECTED_LIGHTS, count])
		quit(1)
		return
	print("[verify_bake_lights] PASS %d disabled runtime lights" % count)
	quit(0)
