# /core_v2/tests/test_determinism_v2.gd
# Runner de replays universal: escanea res://core_v2/tests/ para archivos replay_test_*.json
extends GdUnitTestSuite

const TESTS_ROOT = "res://core_v2/tests"
const DRIFT_THRESHOLD = 0.01
const DRIFT_WARNING = 0.005
const DETERMINISM_ENV_FLAG = "ODISEA_RUN_DETERMINISM"
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

# "measured" dice si el drift se pudo calcular. Sin ese dato, un drift de -1 (el valor
# cuando no hay con que medir) no supera ningun umbral y el test pasaba en silencio —
# la misma clase de agujero que el timeout mudo de PASS 1.
# SessionManager mide el drift al terminar el replay, con el player TODAVIA vivo, y lo
# emite en replay_finished(success, drift, frames). Recalcularlo despues leia una instancia
# ya liberada (airlock que reinstancia al player): el chequeo devolvia Nil, no fallaba nada,
# y la corrida terminaba verde con "DRIFT ERROR" impreso en el log. Se usa el valor emitido;
# _compute_drift queda de respaldo para los replays que no emiten.
var _last_replay_result := {}


func _on_replay_finished(success: bool, drift: float, frames: int) -> void:
	_last_replay_result = {"success": success, "drift": drift, "frames": frames}


func _arm_replay_result_capture() -> void:
	_last_replay_result = {}
	if not SessionManager.is_connected("replay_finished", self, "_on_replay_finished"):
		SessionManager.connect("replay_finished", self, "_on_replay_finished")


# Drift efectivo: el que midio SessionManager si lo emitio, si no el recalculado.
# Devuelve < 0 cuando no hubo forma de medirlo, que es una falla, no un pase.
func _effective_drift(drift_info: Dictionary) -> float:
	if _last_replay_result.has("drift") and float(_last_replay_result["drift"]) >= 0.0:
		return float(_last_replay_result["drift"])
	if drift_info.get("measured", false):
		return float(drift_info["drift"])
	return -1.0


static func _compute_drift(player, expected) -> Dictionary:
	var ret = {"drift": - 1.0, "yaw_diff": 0.0, "pitch_diff": 0.0, "measured": false, "reason": "", "not_applicable": false}
	# Sin estado esperado no hay con que comparar: son scripts que no mueven al player
	# (SET/SCREENSHOT sobre una escena). Eso NO es una falla, es un chequeo que no aplica —
	# distinto de tener expectativa y no poder medirla, que si lo es.
	if expected == null:
		ret["reason"] = "no hay estado esperado"
		ret["not_applicable"] = true
		return ret
	var exp_pos_arr = expected.get("position", null)
	if exp_pos_arr == null or typeof(exp_pos_arr) != TYPE_ARRAY:
		ret["reason"] = "el estado esperado no trae posicion"
		ret["not_applicable"] = true
		return ret
	# is_instance_valid, no "if player": en Godot 3 una instancia liberada sigue siendo
	# truthy, asi que se entraba igual y reventaba al leer global_transform con
	# "previously freed instance". Pasa de verdad: el airlock reinstancia al player a mitad
	# del replay y SessionManager.player puede quedar apuntando al viejo.
	if not is_instance_valid(player):
		ret["reason"] = "el player fue liberado antes del chequeo (swap de escena?)"
		return ret
	var _expected_pos = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
	var final_pos = player.global_transform.origin
	ret["drift"] = final_pos.distance_to(_expected_pos)
	ret["yaw_diff"] = abs(player.yaw - expected.get("yaw", 0.0))
	ret["pitch_diff"] = abs(player.pitch - expected.get("pitch", 0.0))
	ret["measured"] = true
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

# En CI headless el render por software de las escenas 3D pesadas baja a ~1 FPS y
# dispara timeouts (cada test pasa de segundos a >60s). La determinación física no
# depende del render, así que lo desactivamos cuando no hay ventana visible.
# Algunos tests sí dependen del render/shader (p.ej. proyección cilíndrica SGC,
# triggers por visibilidad): esos declaran la directiva OYS_REQUIRE_RENDER y se
# corren con render activo aunque sea más lento.
const REQUIRE_RENDER_DIRECTIVE := "OYS_REQUIRE_RENDER"

func _apply_render_mode_for(path: String) -> void:
	var disable := _should_disable_render()
	if disable and _oys_has_directive(path, REQUIRE_RENDER_DIRECTIVE):
		disable = false
		print("[TEST_RUNNER] Directive %s detected: keeping render enabled for %s" % [REQUIRE_RENDER_DIRECTIVE, path.get_file()])
	var mode := Viewport.UPDATE_DISABLED if disable else Viewport.UPDATE_ALWAYS
	get_tree().get_root().render_target_update_mode = mode

# Render solo es necesario para depuración visual / tests render-dependientes; en
# headless/CI lo desactivamos por defecto para evitar el costo de software-rendering.
static func _should_disable_render() -> bool:
	# Permitir forzar render en una corrida headless si se quiere depurar visualmente.
	if OS.get_environment("OYS_FORCE_RENDER") != "":
		return false
	# El binario headless de export expone la feature "Server".
	if OS.has_feature("Server"):
		return true
	# runtest.sh exporta OYS_RENDER_DISABLED=1 cuando lanza sin ventana (--no-window).
	# Es la señal fiable: el engine consume --no-window antes de get_cmdline_args().
	return OS.get_environment("OYS_RENDER_DISABLED") != ""

# Data provider: devuelve un Array de parameter sets.

# Solo buscamos .oys para el ciclo de determinismo completo (OYS -> JSON -> Verify)
# Si OYS_FILTER está definido, solo retorna ese archivo
static func _get_replay_paths() -> Array:
	var filter = OS.get_environment("OYS_FILTER")
	var skip_json = OS.get_environment("OYS_NODET") != "" # Check for OYS_NODET environment variable
	var run_determinism = OS.get_environment(DETERMINISM_ENV_FLAG).to_lower() in ["1", "true", "yes", "on"]
	var raw_files = []

	# Core test profile: determinism should not block by default.
	# Keep explicit single-case runs (--oys sets OYS_FILTER) working as-is.
	if filter == "" and not run_determinism:
		print("[test_determinism_v2] Skipping full determinism suite (set %s=1 to enable)." % DETERMINISM_ENV_FLAG)
		return [["__odisea_skip__"]]
	
	if filter != "":
		var requested = filter
		if not requested.ends_with(".oys"):
			requested += ".oys"
		var direct_path = TESTS_ROOT.plus_file(requested)
		var f = File.new()
		if f.file_exists(direct_path):
			raw_files = [[direct_path]]
		else:
			var all_oys = _scan_for_files([".oys"], true)
			var by_basename = requested.get_file()
			var matched_path = ""
			for pair in all_oys:
				var candidate = pair[0]
				if candidate.get_file() == by_basename:
					matched_path = candidate
					break
				if candidate.ends_with("/" + requested):
					matched_path = candidate
					break
			if matched_path != "":
				raw_files = [[matched_path]]
			else:
				printerr("OYS_FILTER: archivo no encontrado: ", TESTS_ROOT.plus_file(requested))
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

static func _scan_for_files(extensions: Array, include_stress := false) -> Array:
	var results := []
	var dir := Directory.new()
	if dir.open(TESTS_ROOT) != OK:
	 printerr("No se pudo abrir TESTS_ROOT: ", TESTS_ROOT)
	 return results
	_scan_dir(dir, TESTS_ROOT, results, extensions, include_stress)
	# Solo imprimir una vez si es necesario
	return results

static func _scan_dir(dir: Directory, current_path: String, results: Array, extensions: Array, include_stress: bool) -> void:
	if dir.list_dir_begin(true, true) != OK:
		return
	var name = dir.get_next()
	while name != "":
		var full_path = current_path.plus_file(name)
		if dir.current_is_dir():
			# Performance benchmarks have their own runner and are not replay
			# determinism cases. Including them here makes the suite needlessly slow.
			if name == "perf" or (name == "stress" and not include_stress):
				name = dir.get_next()
				continue
			var subdir := Directory.new()
			if subdir.open(full_path) == OK:
				_scan_dir(subdir, full_path, results, extensions, include_stress)
		else:
			if name.get_basename() in ["perf_test", "perf_ab_test", "debug_perf"]:
				name = dir.get_next()
				continue
			for ext in extensions:
				if name.ends_with(ext):
					results.append([full_path])
					break
		name = dir.get_next()
	dir.list_dir_end()

static func _oys_has_directive(path: String, directive: String) -> bool:
	if not path.ends_with(".oys"):
		return false
	var f := File.new()
	if not f.file_exists(path):
		return false
	if f.open(path, File.READ) != OK:
		return false
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line == "":
			continue
		if (line.begins_with("#") or line.begins_with("//")) and line.findn(directive) != -1:
			f.close()
			return true
	f.close()
	return false

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
	if path == "__odisea_skip__":
		print("[test_replay] Skipped deterministic pass in core profile.")
		return

	# Render off en headless salvo que el test lo requiera (OYS_REQUIRE_RENDER).
	_apply_render_mode_for(path)

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
		_adopt_runner_scene(runner)

		if not is_instance_valid(runner.scene()):
			# scene_runner() can silently fail to instance the scene (e.g. the resource
			# was still mid-load from a prior in-game scene reload of the same path,
			# "already being loaded, cyclic reference"). Left unguarded, the next
			# runner.simulate_frames() call yields on a null scene tree and never
			# resumes, hanging this test until GdUnit3's own suite watchdog fires
			# minutes later. Fail fast instead.
			fail("scene_runner() failed to instance scene (resource load race?): %s" % scene_path)
			return

		# Garantizar estado limpio inicial
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

			_arm_replay_result_capture()
		SessionManager.load_and_play(path)

		var timeout_setup = 100
		while not SessionManager.is_replaying and timeout_setup > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout_setup -= 1

		var timeout = 5000
		while SessionManager.is_replaying and timeout > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout -= 1

		if timeout <= 0:
			_cleanup_runner_scene(runner)
			fail("Replay timed out: %s" % path)

		# Limpieza final para cerrar ventana
		_cleanup_runner_scene(runner)
		
		# Verificar aserciones lógicas grabadas
		if SessionManager.oys_assert_failed:
			_cleanup_runner_scene(runner)
			fail("OYS ASSERT FAILED durante replay JSON.")
			return

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		var drift_threshold = _get_drift_threshold_for_path(path)
		var drift_warning = _get_drift_warning_for_path(path)
		var measured_drift = _effective_drift(drift_info)
		if measured_drift < 0.0 and drift_info.get("not_applicable", false):
			print("[INFO] Chequeo de drift no aplica (%s): %s" % [drift_info.reason, path])
		elif measured_drift < 0.0:
			_cleanup_runner_scene(runner)
			fail("No se pudo medir el drift (%s): %s" % [drift_info.reason, path])
			return
		elif measured_drift > drift_threshold:
			_cleanup_runner_scene(runner)
			fail("Drift demasiado alto: %s (umbral: %s)" % [measured_drift, drift_threshold])
		elif measured_drift > drift_warning:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [measured_drift, drift_warning])
		_cleanup_runner_scene(runner)

	if path.ends_with(".oys"):
		var scene_path = _get_scene_for_test(path)
		
		print("[TEST_RUNNER] Using scene: ", scene_path)
		var runner := scene_runner(scene_path)
		runner.maximize_view()
		_adopt_runner_scene(runner)

		if not is_instance_valid(runner.scene()):
			fail("scene_runner() failed to instance scene (resource load race?): %s" % scene_path)
			return

		# PASS 1: Simular OYS y grabar resultado físico exacto a JSON
		print("[TEST_RUNNER] --- PASS 1: RECORDING OYS ---")

		# Garantizar estado limpio inicial
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()
			
		SessionManager._should_snapshot = true
		_arm_replay_result_capture()
		SessionManager.load_and_play(path)

		var timeout_setup1 = 100
		while not SessionManager.is_replaying and timeout_setup1 > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout_setup1 -= 1

		var timeout1 = 5000
		while SessionManager.is_replaying and timeout1 > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout1 -= 1

		if timeout1 <= 0:
			# Sin este fail, PASS 1 se cortaba en silencio (p.ej. a mitad de un respawn),
			# no reescribia el JSON y PASS 2 comparaba contra una grabacion vieja: drift fantasma.
			_cleanup_runner_scene(runner)
			fail("Grabacion OYS timed out en PASS 1: %s" % path)
			return

		# Verificar si algún ASSERT de OYS falló
		if SessionManager.oys_assert_failed:
			_cleanup_runner_scene(runner)
			fail("OYS ASSERT FAILED: El test OYS falló en una aserción.")
			return

		# LIMPIEZA EXPLÍCITA PARA CERRAR VENTANA Y REINSTANCIAR
		_cleanup_runner_scene(runner)
		runner = null
		# Varios idle frames (no solo uno): si el propio OYS recargó esta misma escena
		# en juego (p. ej. un airlock cuyo destino es el mismo .tscn, como
		# test_tube_airlock), el ResourceLoader puede seguir resolviendo esa carga
		# cuando PASS 2 intenta re-instanciar el mismo path un frame después ->
		# "already being loaded, cyclic reference" y scene_runner() devuelve una
		# instancia rota (ver guard de is_instance_valid(runner.scene()) más abajo).
		for _i in range(5):
			yield (get_tree(), "idle_frame")

		# PASS 2: Verificar que el JSON grabado sea reproducible
		var skip_json = OS.get_environment("OYS_NODET") != ""
		if not skip_json and _oys_has_directive(path, "OYS_NODET=1"):
			skip_json = true
			print("[TEST_RUNNER] Script directive detected: OYS_NODET=1")
		if skip_json:
			print("[TEST_RUNNER] Skipping --- PASS 2: VERIFYING JSON --- (OYS_NODET detected)")
			return

		var json_path = path.get_basename() + ".json"
		print("[TEST_RUNNER] --- PASS 2: VERIFYING JSON ---")
		var json_file = File.new()
		if not json_file.file_exists(json_path):
			print("[TEST_RUNNER] JSON companion missing, skipping PASS 2 for: ", path)
			print("[test_replay] Finalizado: ", desc)
			return

		# Re-instanciar runner y escena para evitar state bleeding
		runner = scene_runner(scene_path)
		runner.maximize_view()
		_adopt_runner_scene(runner)

		if not is_instance_valid(runner.scene()):
			fail("scene_runner() failed to instance scene (resource load race?): %s" % scene_path)
			return

		# RE-SINCRONIZACIÓN ABSOLUTA PARA PASS 2
		SessionManager.is_replaying = false
		SessionManager._peak_y = 0.0 # RESET ESTADÍSTICAS
		SessionManager._find_player()
		if is_instance_valid(SessionManager.player) and SessionManager.player.has_method("full_reset"):
			SessionManager.player.full_reset()

		SessionManager._should_snapshot = false
		_arm_replay_result_capture()
		SessionManager.load_and_play(json_path)

		var timeout_setup = 100
		while not SessionManager.is_replaying and timeout_setup > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout_setup -= 1
		
		var timeout = 5000
		while SessionManager.is_replaying and timeout > 0:
			yield (get_tree(), "physics_frame") # el replay avanza por tick de fisica, no por idle frame
			timeout -= 1
		
		if timeout <= 0:
			_cleanup_runner_scene(runner)
			fail("Replay timed out en PASS 2: %s" % json_path)
			return
		
		# Verificar aserciones lógicas grabadas también en PASS 2 (JSON replay)
		if SessionManager.oys_assert_failed:
			_cleanup_runner_scene(runner)
			fail("OYS ASSERT FAILED durante replay JSON (PASS 2).")
			return

		# Chequeo de drift si corresponde
		var drift_info = _compute_drift(SessionManager.player, SessionManager.final_expected_state)
		var drift_threshold = _get_drift_threshold_for_path(path)
		var drift_warning = _get_drift_warning_for_path(path)
		var measured_drift = _effective_drift(drift_info)
		if measured_drift < 0.0 and drift_info.get("not_applicable", false):
			print("[INFO] Chequeo de drift no aplica (%s): %s" % [drift_info.reason, path])
		elif measured_drift < 0.0:
			_cleanup_runner_scene(runner)
			fail("No se pudo medir el drift (%s): %s" % [drift_info.reason, path])
			return
		elif measured_drift > drift_threshold:
			_cleanup_runner_scene(runner)
			fail("Drift demasiado alto: %s (umbral: %s)" % [measured_drift, drift_threshold])
		elif measured_drift > drift_warning:
			print("[WARNING] Drift alto: %s (umbral warning: %s)" % [measured_drift, drift_warning])
		_cleanup_runner_scene(runner)

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

func _cleanup_runner_scene(runner) -> void:
	# An OYS can replace current_scene through SceneManager. In that case the
	# runner still owns only its original scene, so freeing runner.scene() leaves
	# the replacement alive and contaminates every following parametrized case.
	if SceneManager.is_transitioning():
		SceneManager._force_reset_stuck_transition("test_cleanup")
	SceneManager._pending_scene_path = ""
	SceneManager._pending_transition_params.clear()

	var runner_scene: Node = runner.scene() if runner and runner.has_method("scene") else null
	var active_scene: Node = get_tree().current_scene
	if is_instance_valid(active_scene) and active_scene != runner_scene:
		get_tree().current_scene = null
		active_scene.free()

	if runner and runner.has_method("scene"):
		if is_instance_valid(runner_scene):
			if get_tree().current_scene == runner_scene:
				get_tree().current_scene = null
			runner_scene.free()

func _adopt_runner_scene(runner) -> void:
	# GdUnit agrega la escena a /root pero no la vuelve current_scene. SessionManager
	# entonces no acepta su Pilot y carga una segunda TestScene para el replay.
	var runner_scene: Node = runner.scene() if runner and runner.has_method("scene") else null
	if is_instance_valid(runner_scene):
		get_tree().current_scene = runner_scene
		SessionManager.player = null

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
