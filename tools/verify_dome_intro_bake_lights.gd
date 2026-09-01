extends SceneTree

const RIG_PATH := "res://core_v2/levels/interiors/DomeIntro_BakeLights.tscn"
const DARK_RIG_PATH := "res://core_v2/levels/interiors/DomeIntro_BakeLights_dark.tscn"
const EXPECTED_LIGHTS := 107

func _init() -> void:
	if not _check(RIG_PATH, EXPECTED_LIGHTS):
		quit(1)
		return
	# FD-284: el rig oscuro existe y está vacío a propósito — el estado OSCURAS es
	# el ambiente del Environment, sin ningún fixture horneado.
	if not _check(DARK_RIG_PATH, 0):
		quit(1)
		return
	quit(0)

func _check(path: String, expected: int) -> bool:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("[verify_bake_lights] missing %s" % path)
		return false
	var rig := scene.instance()
	var count := 0
	for child in rig.get_children():
		if not (child is OmniLight):
			continue
		var light := child as OmniLight
		if light.visible or light.light_bake_mode != 0:
			push_error("[verify_bake_lights] runtime-active bake light: %s" % light.name)
			return false
		count += 1
	if count != expected:
		push_error("[verify_bake_lights] %s: expected %d lights, found %d" % [path, expected, count])
		return false
	print("[verify_bake_lights] PASS %s: %d disabled runtime lights" % [path, count])
	return true
