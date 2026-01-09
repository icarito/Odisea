# /core_v2/tests/test_determinism_v2.gd
# Runner de replays universal: escanea res://core_v2/tests/ para archivos replay_test_*.json
extends GdUnitTestSuite

const TESTS_ROOT = "res://core_v2/tests"
const DRIFT_THRESHOLD = 0.0001

# Helpers
static func _describe_replay_path(path: String) -> String:
	var fname = path.get_file()
	# Eliminar prefijos comunes y extensión para legibilidad
	return fname.replace("replay_test_", "").replace("test_replay_", "").replace(".json", "")

static func _compute_drift(player, expected: Dictionary) -> Dictionary:
	var ret = {"drift": - 1.0, "yaw_diff": 0.0, "pitch_diff": 0.0}
	if expected == null:
		return ret
	var exp_pos_arr = expected.get("position", null)
	if exp_pos_arr == null or typeof(exp_pos_arr) != TYPE_ARRAY:
		return ret
	if player:
		var _expected_pos = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
		var final_pos = player.global_transform.origin
		ret["drift"] = final_pos.distance_to(_expected_pos)
		ret["yaw_diff"] = abs(player.yaw - expected.get("yaw", 0.0))
		ret["pitch_diff"] = abs(player.pitch - expected.get("pitch", 0.0))
	return ret

func before():
	# Optimización para tests: desactivar vsync para velocidad máxima
	OS.set_use_vsync(false)
	Engine.target_fps = 0 # Sin límite de FPS

# Data provider: devuelve un Array de parameter sets. Cada parameter set es un Array de argumentos para la prueba.
static func _get_replay_paths() -> Array:
	var results := []
	var dir := Directory.new()
	if dir.open(TESTS_ROOT) != OK:
		printerr("No se pudo abrir TESTS_ROOT: ", TESTS_ROOT)
		return results
	_scan_dir(dir, TESTS_ROOT, results)
	print("Replays encontrados: ", results)
	return results

static func _scan_dir(dir: Directory, current_path: String, results: Array) -> void:
	# Usar list_dir_begin(true, true) para saltar "." y ".."
	if dir.list_dir_begin(true, true) != OK:
		return
	var name = dir.get_next()
	while name != "":
		var full_path = current_path.plus_file(name)
		if dir.current_is_dir():
			var subdir := Directory.new()
			if subdir.open(full_path) == OK:
				_scan_dir(subdir, full_path, results)
		else:
			if (name.begins_with("replay_test_") or name.begins_with("test_replay_")) and name.ends_with(".json"):
				# GDUnit3 espera un Array de Arrays. Cada subarray son los argumentos para el test.
				results.append([full_path])
		name = dir.get_next()
	dir.list_dir_end()

# Parametrized test: cada parameter set es [path]
func test_replay(path: String, test_parameters=_get_replay_paths()) -> void:
	var desc = _describe_replay_path(path)

	# 1. Cargar la escena de test desde el JSON
	var f = File.new()
	var open_err = f.open(path, File.READ)
	assert_int(open_err).is_equal(OK)
	var parsed = JSON.parse(f.get_as_text())
	assert_int(parsed.error).is_equal(OK)
	var data = parsed.result
	f.close()

	var meta = data.get("meta", {})
	var scene_path = meta.get("scene", "res://core_v2/scenes/TestScene_v2.tscn")
	
	var err = get_tree().change_scene(scene_path)
	assert_int(err).is_equal(OK)
	
	# 2. Esperar estabilización (importante para física y registro de grupos)
	# Necesitamos que los nodos en 'replay_sync' estén listos.
	for _i in range(10):
		yield (get_tree(), "idle_frame")
	yield (get_tree(), "physics_frame")

	# 3. Iniciar replay via SessionManager
	assert_object(SessionManager).is_not_null()
	SessionManager.load_and_play(path)
	
	# 4. Esperar la señal replay_finished y validar resultado
	var res = yield (SessionManager, "replay_finished")
	var success = res[0]
	var drift = res[1]
	var frames = res[2]

	if not success:
		fail("Replay '%s' FAILED: drift=%.8f, frames=%d. Ver logs para detalles." % [desc, drift, frames])
	
	# 5. Limpieza post-test
	var cs = get_tree().current_scene
	if cs:
		cs.free()

func after():
	# Restablecer estado del SessionManager para evitar interferencias entre tests
	SessionManager.is_replaying = false
	SessionManager.buffer = []
	SessionManager.final_expected_state = null
	SessionManager.player = null
