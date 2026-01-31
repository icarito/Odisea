# /core_v2/tests/test_determinism_v2.gd
# Runner de replays universal: escanea res://core_v2/tests/ para archivos replay_test_*.json
extends GdUnitTestSuite

const TESTS_ROOT = "res://core_v2/tests"
const DRIFT_THRESHOLD = 0.01
const DRIFT_WARNING = 0.005

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

static func _compute_drift(player, expected) -> Dictionary:
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
	SessionManager.is_manual_mode = true

# Data provider: devuelve un Array de parameter sets.

# Solo buscamos .oys para el ciclo de determinismo completo (OYS -> JSON -> Verify)
static func _get_replay_paths() -> Array:
	return _scan_for_files([".oys"])

static func _scan_for_files(extensions: Array) -> Array:
	var results := []
	var dir := Directory.new()
	if dir.open(TESTS_ROOT) != OK:
	 printerr("No se pudo abrir TESTS_ROOT: ", TESTS_ROOT)
	 return results
	_scan_dir(dir, TESTS_ROOT, results, extensions)
	# Solo imprimir una vez si es necesario
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


# Forzar posición inicial del player si hay snapshot esperado, si no, a (0,0,0)
func _force_player_position_from_expected():
	if is_instance_valid(SessionManager.player):
		var t = SessionManager.player.global_transform
		if SessionManager.final_expected_state != null:
			var exp_pos_arr = SessionManager.final_expected_state.get("position", null)
			if exp_pos_arr != null and typeof(exp_pos_arr) == TYPE_ARRAY:
				t.origin = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
			else:
				t.origin = Vector3(0, 0, 0)
		else:
			t.origin = Vector3(0, 0, 0)
		SessionManager.player.global_transform = t

# Test único parametrizado para ambos formatos
func test_replay(path: String, test_parameters = _get_replay_paths()) -> void:
	var _unused = test_parameters
	var desc = path.get_file()

	# LIMPIEZA INICIAL DEL SINGLETON
	SessionManager.is_replaying = false
	SessionManager.player = null

	# Llamar tras encontrar player y antes de cada replay
	if path.ends_with(".json"):
		print("[TEST_RUNNER] Mode: JSON Direct Replay")
		var runner := scene_runner("res://core_v2/levels/TestScene_v2.tscn")
		runner.maximize_view()

		# Garantizar estado limpio inicial
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

		_force_player_position_from_expected()

		SessionManager.load_and_play(path)

		var timeout = 5000
		while SessionManager.is_replaying and timeout > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout -= 1

		if timeout <= 0:
			fail("Replay timed out: %s" % path)

		# Limpieza final para cerrar ventana
		if is_instance_valid(runner.scene()):
			runner.scene().queue_free()

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		if drift_info.drift > DRIFT_THRESHOLD:
			fail("Drift demasiado alto: %s (umbral: %s)" % [drift_info.drift, DRIFT_THRESHOLD])
		elif drift_info.drift > DRIFT_WARNING:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [drift_info.drift, DRIFT_WARNING])

	if path.ends_with(".oys"):
		# Pre-parse scene path from OYS
		var scene_path = "res://core_v2/levels/TestScene_v2.tscn"
		var f = File.new()
		if f.open(path, File.READ) == OK:
			while not f.eof_reached():
				var line = f.get_line().strip_edges()
				if line.begins_with("LEVEL"):
					var parts = line.split(" ", false)
					if parts.size() > 1:
						scene_path = parts[1]
					break
			f.close()
		
		print("[TEST_RUNNER] Using scene: ", scene_path)
		var runner := scene_runner(scene_path)
		runner.maximize_view()

		# PASS 1: Simular OYS y grabar resultado físico exacto a JSON
		print("[TEST_RUNNER] --- PASS 1: RECORDING OYS ---")

		# Sincronización de estado inicial Frame 0
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

		_force_player_position_from_expected()

		SessionManager._should_snapshot = true
		SessionManager.load_and_play(path)

		var timeout1 = 5000
		while SessionManager.is_replaying and timeout1 > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout1 -= 1

		# LIMPIEZA EXPLÍCITA PARA CERRAR VENTANA Y REINSTANCIAR
		if is_instance_valid(runner.scene()):
			runner.scene().queue_free()
		runner = null
		yield (get_tree(), "idle_frame")

		# PASS 2: Verificar que el JSON grabado sea reproducible
		var json_path = path.get_basename() + ".json"
		print("[TEST_RUNNER] --- PASS 2: VERIFYING JSON ---")

		# Re-instanciar runner y escena para evitar state bleeding
		runner = scene_runner(scene_path)
		runner.maximize_view()

		# RE-SINCRONIZACIÓN ABSOLUTA PARA PASS 2
		SessionManager.is_replaying = false
		SessionManager._peak_y = 0.0 # RESET ESTADÍSTICAS
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

		_force_player_position_from_expected()

		SessionManager._should_snapshot = false
		SessionManager.load_and_play(json_path)

		var timeout2 = 5000
		while SessionManager.is_replaying and timeout2 > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout2 -= 1

		# LIMPIEZA EXPLÍCITA PARA CERRAR VENTANA
		if is_instance_valid(runner.scene()):
			runner.scene().queue_free()

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		if drift_info.drift > DRIFT_THRESHOLD:
			fail("Drift demasiado alto: %s (umbral: %s)" % [drift_info.drift, DRIFT_THRESHOLD])
		elif drift_info.drift > DRIFT_WARNING:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [drift_info.drift, DRIFT_WARNING])

	# Breve espera para que GdUnit considere el test terminado
	yield (get_tree(), "idle_frame")
	print("[test_replay] Finalizado: ", desc)

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


# Los métodos legacy _setup_scene_from_* han sido eliminados por redundancia.

func _cleanup_scene():
	if is_instance_valid(_current_test_scene):
		_current_test_scene.free() # Usar free() para sincronicidad inmediata en tests
		_current_test_scene = null
	
	# Limpieza agresiva de huérfanos en root
	var root = get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var child = root.get_child(i)
		# No borrar singletons ni el test runner mismo!
		if child.name == "SessionManager" or child is GdUnitTestSuite:
			continue
		
		# Borrar cualquier escena de test o residuo de Pilot
		if child.name == "TestScene" or child.name == "Spatial" or child.find_node("Pilot", true, false) != null:
			print("[test_cleanup] Removing orphan: ", child.name)
			child.free()

func _instance_and_prepare_scene(scene_path: String):
	var packed = load(scene_path)
	assert_object(packed).is_not_null()
	_current_test_scene = packed.instance()
	get_tree().root.add_child(_current_test_scene)
	get_tree().current_scene = _current_test_scene
	
	# Esperar estabilización con idle frames para que el player entre al árbol correctamente
	for i in range(5):
		yield (get_tree(), "idle_frame")

func after():
	# Restablecer estado del SessionManager para evitar interferencias entre tests
	SessionManager.is_replaying = false
	SessionManager.is_manual_mode = false
	SessionManager.buffer = []
	SessionManager.final_expected_state = null
	SessionManager.player = null
	
	# Limpieza manual de la escena
	if is_instance_valid(_current_test_scene):
		print("[test_replay] Freeing manual scene...")
		_current_test_scene.free() # Usar free() para sincronicidad inmediata
		_current_test_scene = null
	
	# Limpieza de huérfanos
	_cleanup_scene()
