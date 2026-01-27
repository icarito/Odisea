# /core_v2/tests/test_determinism_v2.gd
# Runner de replays universal: escanea res://core_v2/tests/ para archivos replay_test_*.json
extends GdUnitTestSuite


const TESTS_ROOT = "res://core_v2/tests"
const DRIFT_THRESHOLD = 0.0005

## Helpers

# Minimal assert_true helper for boolean assertions
func assert_true(cond: bool, msg: String = ""):
	if not cond:
		push_error("Assertion failed: " + msg)
		fail(msg)
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

# Data provider: devuelve un Array de parameter sets.

# Unifica búsqueda de archivos .json y .oys
static func _get_replay_and_oys_paths() -> Array:
	return _scan_for_files([".json", ".oys"])

static func _scan_for_files(extensions: Array) -> Array:
	var results := []
	var dir := Directory.new()
	if dir.open(TESTS_ROOT) != OK:
		printerr("No se pudo abrir TESTS_ROOT: ", TESTS_ROOT)
		return results
	_scan_dir(dir, TESTS_ROOT, results, extensions)
	print("Test files encontrados: ", results)
	return results

static func _scan_dir(dir: Directory, current_path: String, results: Array, extensions: Array) -> void:
	if dir.list_dir_begin(true, true) != OK:
		return
	var name = dir.get_next()
	while name != "":
		var full_path = current_path.plus_file(name)
		if dir.current_is_dir():
			var subdir := Directory.new()
			if subdir.open(full_path) == OK:
				_scan_dir(subdir, full_path, results, extensions)
		else:
			for ext in extensions:
				if name.ends_with(ext):
					results.append([full_path])
					break
		name = dir.get_next()
	dir.list_dir_end()

var _current_test_scene: Node = null

# Parametrized test for JSON replays

# Test único parametrizado para ambos formatos
func test_replay_or_oys(path: String, test_parameters=_get_replay_and_oys_paths()) -> void:
	var _unused = test_parameters
	var desc = path.get_file()
	var ext = path.get_extension().to_lower()
	if ext == "json":
		_setup_scene_from_replay_file(path)
		SessionManager.load_and_play(path)
		var res = yield (SessionManager, "replay_finished")
		var success = res[0]
		var drift = res[1]
		var frames = res[2]
		if not success:
			fail("Replay '%s' FAILED: drift=%.8f, frames=%d." % [desc, drift, frames])
		print("[test_replay] Finalizado: ", desc)
	elif ext == "oys":
		var f = File.new()
		assert_int(f.open(path, File.READ)).is_equal(OK)
		var script_content = f.get_as_text()
		f.close()
		var resolver = load("res://core_v2/utils/OYS_Resolver.gd")
		var result = resolver.parse_script(script_content)
		_setup_scene_from_oys_result(result)
		for setter in result.get("setters", []):
			_apply_setter(SessionManager.player, setter)
		SessionManager.play_buffer(result.buffer, {})
		var res = yield (SessionManager, "replay_finished")
		for assertion in result.get("asserts", []):
			_validate_assertion(SessionManager.player, assertion)
		print("[test_oys_script] Finalizado: ", desc)
	else:
		fail("Archivo no soportado: %s" % path)

func _apply_setter(player, setter):
	if not is_instance_valid(player):
		return

	match setter.property:
		"pos":
			var pos_str = setter.value.trim_prefix("(").trim_suffix(")").split(",")
			var new_pos = Vector3(
				pos_str[0].strip_edges().to_float(),
				pos_str[1].strip_edges().to_float(),
				pos_str[2].strip_edges().to_float()
			)
			var t = player.global_transform
			t.origin = new_pos
			player.global_transform = t
		"rot":
			player.rotation_degrees.y = setter.value.to_float()

func _validate_assertion(player, assertion):
	if not is_instance_valid(player):
		fail("Player instance is not valid for assertion.")
		return

	var condition = assertion.condition

	# Split condition from optional message
	var parts = condition.split("\"", 2)
	var expression = parts[0].strip_edges()
	var msg = parts[1] if parts.size() > 1 else "Assertion failed"

	# Simple expression parsing
	var expr_parts = expression.split(" ", false)
	var prop_path = expr_parts[0]
	var op = expr_parts[1]
	var value_str = expr_parts[2]

	var actual_value = _get_property(player, prop_path)
	var expected_value = value_str.to_float() if value_str.is_valid_float() else value_str

	if value_str == "true": expected_value = true
	if value_str == "false": expected_value = false

	match op:
		">":
			assert_true(actual_value > expected_value, "%s: %s not > %s" % [msg, actual_value, expected_value])
		"<":
			assert_true(actual_value < expected_value, "%s: %s not < %s" % [msg, actual_value, expected_value])
		"==":
			assert_object(actual_value).is_equal(expected_value)

func _get_property(obj, prop_path):
	var parts = prop_path.split(".")
	var current = obj
	for part in parts:
		if current.has_method("get") and current.get(part) != null:
			current = current.get(part)
		else:
			return null
	return current


func _setup_scene_from_replay_file(path: String):
	# Limpieza de escena anterior
	_cleanup_scene()

	var f = File.new()
	assert_int(f.open(path, File.READ)).is_equal(OK)
	var parsed = JSON.parse(f.get_as_text())
	assert_int(parsed.error).is_equal(OK)
	var data = parsed.result
	f.close()

	var meta = data.get("meta", {})
	var scene_path = meta.get("scene", "res://core_v2/scenes/TestScene_v2.tscn")
	
	_instance_and_prepare_scene(scene_path)
	
func _setup_scene_from_oys_result(result: Dictionary):
	# Limpieza de escena anterior
	_cleanup_scene()
	# TODO: Use scene from OYS metadata if available
	var scene_path = "res://core_v2/scenes/TestScene_v2.tscn"
	_instance_and_prepare_scene(scene_path)

func _cleanup_scene():
	if is_instance_valid(_current_test_scene):
		_current_test_scene.queue_free()
		_current_test_scene = null
	for child in get_tree().root.get_children():
		if child.name == "TestScene" or child.filename == "res://core_v2/scenes/TestScene_v2.tscn":
			child.free()

func _instance_and_prepare_scene(scene_path: String):
	var packed = load(scene_path)
	assert_object(packed).is_not_null()
	_current_test_scene = packed.instance()
	get_tree().root.add_child(_current_test_scene)
	get_tree().current_scene = _current_test_scene
	
	# Esperar estabilización con timers para estabilidad en headless
	for i in range(5):
		yield(get_tree().create_timer(0.02), "timeout")
	yield(get_tree().create_timer(0.02), "timeout") # Simular espera de physics_frame

func after():
	# Restablecer estado del SessionManager para evitar interferencias entre tests
	SessionManager.is_replaying = false
	SessionManager.buffer = []
	SessionManager.final_expected_state = null
	SessionManager.player = null
	
	# Limpieza manual de la escena
	if is_instance_valid(_current_test_scene):
		print("[test_replay] Freeing manual scene...")
		_current_test_scene.queue_free()
		_current_test_scene = null
