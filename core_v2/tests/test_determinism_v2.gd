# /core_v2/tests/test_determinism_v2.gd
# Runner de replays universal: escanea res://core_v2/tests/ para archivos replay_test_*.json
extends GdUnitTestSuite

const TESTS_ROOT = "res://core_v2/tests"
const DRIFT_THRESHOLD = 0.01
const DRIFT_WARNING = 0.005
var _drift_threshold_cache := {}

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

func _extract_drift_threshold_from_data(data: Dictionary) -> float:
	var fallback = DRIFT_THRESHOLD
	if typeof(data) != TYPE_DICTIONARY:
		return fallback
	
	if data.has("drift_threshold"):
		var top_val = float(data.get("drift_threshold", fallback))
		if top_val > 0.0:
			return top_val
	
	var meta = data.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY and meta.has("drift_threshold"):
		var meta_val = float(meta.get("drift_threshold", fallback))
		if meta_val > 0.0:
			return meta_val
	
	var vars = data.get("oys_variables", {})
	if typeof(vars) == TYPE_DICTIONARY:
		if vars.has("$drift_threshold"):
			var v = float(vars.get("$drift_threshold", fallback))
			if v > 0.0:
				return v
		if vars.has("$sys_drift_threshold"):
			var sv = float(vars.get("$sys_drift_threshold", fallback))
			if sv > 0.0:
				return sv
	
	return fallback

func _get_drift_threshold_for_path(path: String) -> float:
	if _drift_threshold_cache.has(path):
		return _drift_threshold_cache[path]
	
	var replay_path = path
	if path.ends_with(".oys"):
		replay_path = path.get_basename() + ".json"
	
	var f = File.new()
	if not f.file_exists(replay_path):
		_drift_threshold_cache[path] = DRIFT_THRESHOLD
		return DRIFT_THRESHOLD
	
	if f.open(replay_path, File.READ) != OK:
		_drift_threshold_cache[path] = DRIFT_THRESHOLD
		return DRIFT_THRESHOLD
	
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	
	if typeof(parsed.result) != TYPE_DICTIONARY:
		_drift_threshold_cache[path] = DRIFT_THRESHOLD
		return DRIFT_THRESHOLD
	
	var threshold = _extract_drift_threshold_from_data(parsed.result)
	_drift_threshold_cache[path] = threshold
	return threshold

func _get_drift_warning_for_path(path: String) -> float:
	var threshold = _get_drift_threshold_for_path(path)
	return max(DRIFT_WARNING, threshold * 0.5)

func before():
	# Optimización para tests: desactivar vsync para velocidad máxima
	OS.set_use_vsync(false)
	Engine.target_fps = 0 # Sin límite de FPS
	SessionManager.is_manual_mode = true
	_drift_threshold_cache.clear()

# Data provider: devuelve un Array de parameter sets.

# Solo buscamos .oys para el ciclo de determinismo completo (OYS -> JSON -> Verify)
# Si OYS_FILTER está definido, solo retorna ese archivo
static func _get_replay_paths() -> Array:
	var filter = OS.get_environment("OYS_FILTER")
	var skip_json = OS.get_environment("OYS_NODET") != "" # Check for OYS_NODET environment variable
	var raw_files = []
	
	if filter != "":
		var filtered_path = TESTS_ROOT.plus_file(filter)
		if not filtered_path.ends_with(".oys"):
			filtered_path += ".oys"
		var f = File.new()
		if f.file_exists(filtered_path):
			raw_files = [[filtered_path]]
		else:
			printerr("OYS_FILTER: archivo no encontrado: ", filtered_path)
			return []
	else:
		if skip_json:
			raw_files = _scan_for_files([".oys"])
		else:
			raw_files = _scan_for_files([".oys", ".json"])
	
	# Filtrar redundancia: si existe un .oys, ignorar el .json
	var oys_files = {}
	for pair in raw_files:
		var path = pair[0]
		if path.ends_with(".oys"):
			oys_files[path.get_basename()] = true
	
	var final_results = []
	for pair in raw_files:
		var path = pair[0]
		if path.ends_with(".json"):
			if oys_files.has(path.get_basename()):
				# Saltar JSON si existe OYS (ya se prueba en PASS 2 del OYS)
				continue
		final_results.append(pair)
		
	return final_results

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

func _get_scene_for_test(path: String) -> String:
	var scene_path = "res://core_v2/levels/TestScene_v2.tscn"
	if path.ends_with(".oys"):
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
	elif path.ends_with(".json"):
		var f = File.new()
		if f.open(path, File.READ) == OK:
			var parsed = JSON.parse(f.get_as_text())
			f.close()
			if typeof(parsed.result) == TYPE_DICTIONARY:
				var meta = parsed.result.get("meta", {})
				scene_path = meta.get("scene_path", scene_path)
	return scene_path

# Parametrized test for JSON replays


# Test único parametrizado para ambos formatos
func test_replay(path: String, test_parameters = _get_replay_paths()) -> void:
	var _unused = test_parameters
	var desc = path.get_file()

	# LIMPIEZA INICIAL DEL SINGLETON
	SessionManager.is_replaying = false
	SessionManager.player = null
	SessionManager.oys_assert_failed = false

	# Llamar tras encontrar player y antes de cada replay
	if path.ends_with(".json"):
		print("[TEST_RUNNER] Mode: JSON Direct Replay")
		var scene_path = _get_scene_for_test(path)
		print("[TEST_RUNNER] Using scene: ", scene_path)
		var runner := scene_runner(scene_path)
		runner.maximize_view()

		# Garantizar estado limpio inicial
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

			SessionManager.load_and_play(path)

		var timeout_setup = 100
		while not SessionManager.is_replaying and timeout_setup > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout_setup -= 1

		var timeout = 5000
		while SessionManager.is_replaying and timeout > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout -= 1

		if timeout <= 0:
			fail("Replay timed out: %s" % path)

		# Limpieza final para cerrar ventana
		if is_instance_valid(runner.scene()):
			runner.scene().queue_free()
		
		# Verificar aserciones lógicas grabadas
		if SessionManager.oys_assert_failed:
			fail("OYS ASSERT FAILED durante replay JSON.")
			return

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		var drift_threshold = _get_drift_threshold_for_path(path)
		var drift_warning = _get_drift_warning_for_path(path)
		if drift_info.drift > drift_threshold:
			fail("Drift demasiado alto: %s (umbral: %s)" % [drift_info.drift, drift_threshold])
		elif drift_info.drift > drift_warning:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [drift_info.drift, drift_warning])

	if path.ends_with(".oys"):
		var scene_path = _get_scene_for_test(path)
		
		print("[TEST_RUNNER] Using scene: ", scene_path)
		var runner := scene_runner(scene_path)
		runner.maximize_view()

		# PASS 1: Simular OYS y grabar resultado físico exacto a JSON
		print("[TEST_RUNNER] --- PASS 1: RECORDING OYS ---")

		# Garantizar estado limpio inicial
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()
			
		SessionManager._should_snapshot = true
		SessionManager.load_and_play(path)

		var timeout_setup1 = 100
		while not SessionManager.is_replaying and timeout_setup1 > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout_setup1 -= 1

		var timeout1 = 5000
		while SessionManager.is_replaying and timeout1 > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout1 -= 1

		# Verificar si algún ASSERT de OYS falló
		if SessionManager.oys_assert_failed:
			fail("OYS ASSERT FAILED: El test OYS falló en una aserción.")
			return

		# LIMPIEZA EXPLÍCITA PARA CERRAR VENTANA Y REINSTANCIAR
		if is_instance_valid(runner.scene()):
			runner.scene().queue_free()
		runner = null
		yield (get_tree(), "idle_frame")

		# PASS 2: Verificar que el JSON grabado sea reproducible
		var skip_json = OS.get_environment("OYS_NODET") != ""
		if skip_json:
			print("[TEST_RUNNER] Skipping --- PASS 2: VERIFYING JSON --- (OYS_NODET detected)")
			return

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

		SessionManager._should_snapshot = false
		SessionManager.load_and_play(json_path)

		var timeout_setup = 100
		while not SessionManager.is_replaying and timeout_setup > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout_setup -= 1
		
		var timeout = 5000
		while SessionManager.is_replaying and timeout > 0:
			yield (runner.simulate_frames(1), "completed")
			timeout -= 1
		
		if timeout <= 0:
			fail("Replay timed out en PASS 2: %s" % json_path)
			return
		
		# Verificar aserciones lógicas grabadas también en PASS 2 (JSON replay)
		if SessionManager.oys_assert_failed:
			fail("OYS ASSERT FAILED durante replay JSON (PASS 2).")
			return
			
			# LIMPIEZA EXPLÍCITA PARA CERRAR VENTANA
			if is_instance_valid(runner.scene()):
				runner.scene().queue_free()

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		var drift_threshold = _get_drift_threshold_for_path(path)
		var drift_warning = _get_drift_warning_for_path(path)
		if drift_info.drift > drift_threshold:
			fail("Drift demasiado alto: %s (umbral: %s)" % [drift_info.drift, drift_threshold])
		elif drift_info.drift > drift_warning:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [drift_info.drift, drift_warning])

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
	for _i in range(root.get_child_count() - 1, -1, -1):
		var child = root.get_child(_i)
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
	for _i in range(5):
		yield (get_tree(), "idle_frame")

func after():
	# Restablecer estado del SessionManager para evitar interferencias entre tests
	SessionManager.is_replaying = false
	SessionManager.is_manual_mode = false
	Engine.time_scale = 1.0
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
