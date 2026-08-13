extends SceneTree

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const POOLS := ["HubExitLights", "RampLightPath", "SpokeLightPath", "WallLights"]
const EXPECTED_POOL_TOTAL := 5

func _init() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[verify_runtime_lights] missing %s" % SCENE_PATH)
		quit(1)
		return
	var dome := scene.instance()
	var total := 0
	for path in POOLS:
		var pool := dome.get_node_or_null(path)
		if pool == null:
			push_error("[verify_runtime_lights] missing pool %s" % path)
			quit(1)
			return
		total += int(pool.get("light_pool_size"))
	if total != EXPECTED_POOL_TOTAL:
		push_error("[verify_runtime_lights] expected %d dynamic lights, got %d" % [EXPECTED_POOL_TOTAL, total])
		quit(1)
		return
	print("[verify_runtime_lights] PASS %d pooled dynamic lights" % total)
	quit(0)
