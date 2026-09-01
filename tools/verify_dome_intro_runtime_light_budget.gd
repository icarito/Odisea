extends SceneTree

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
# Los pools viven en Dome_Base, la escena base que Dome_Intro y Dome_Prologue
# instancian. Este verificador los buscaba en la raíz y fallaba desde que
# Dome_Base se extrajo; la ruta vieja no existe hace varios commits.
const POOL_PARENT := "Dome_Base"
const POOLS := ["HubExitLights", "RampLightPath", "SpokeLightPath", "WallLights"]
# Una luz por pool: el presupuesto móvil de FD-273. FD-284 lo reusa como estado
# BAJO CONSUMO y lo lleva a 0 en PLENO, pero eso pasa en runtime y no cambia
# lo que la escena trae horneado.
const EXPECTED_POOL_TOTAL := 4

func _init() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("[verify_runtime_lights] missing %s" % SCENE_PATH)
		quit(1)
		return
	var dome := scene.instance()
	var total := 0
	for path in POOLS:
		var pool := dome.get_node_or_null("%s/%s" % [POOL_PARENT, path])
		if pool == null:
			push_error("[verify_runtime_lights] missing pool %s/%s" % [POOL_PARENT, path])
			quit(1)
			return
		total += int(pool.get("light_pool_size"))
	if total != EXPECTED_POOL_TOTAL:
		push_error("[verify_runtime_lights] expected %d dynamic lights, got %d" % [EXPECTED_POOL_TOTAL, total])
		quit(1)
		return
	print("[verify_runtime_lights] PASS %d pooled dynamic lights" % total)
	quit(0)
