# /core_v2/tests/test_player_determinism_v2.gd
extends GdUnitTestSuite

# Referencias a dependencias críticas del Core v2
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const PlayerControllerV2 = preload("res://core_v2/sim/PlayerControllerV2.gd")
const REFERENCE_PATH = "res://core_v2/tests/reference.json"
const FIXED_DT = 1.0 / 60.0 # Delta constante para asegurar determinismo

var _reference_data: Dictionary

func before():
	# Carga de datos de referencia generados por SessionManager.gd
	var file = File.new()
	if file.open(REFERENCE_PATH, File.READ) == OK:
		var json_parsed = JSON.parse(file.get_as_text())
		if json_parsed.error == OK:
			_reference_data = json_parsed.result
		file.close()
	
	assert_dict(_reference_data).is_not_empty()
	# Desactivar explícitamente cualquier modo de prueba que use el SceneTree
	if has_node("/root/SessionManager"):
		get_node("/root/SessionManager").is_replaying = true

func test_determinismo_headless():
	# 1. Cargar el entorno (world scene) indicado en la metadata del JSON
	var scene_path = ""
	var meta = _reference_data.get("meta", {})
	# Priorizar `meta.scene` porque los JSON generados usan esa clave
	if typeof(meta) == TYPE_DICTIONARY:
		scene_path = meta.get("scene", "")
		if scene_path == "":
			scene_path = meta.get("scene_path", "")

	assert_str(scene_path).is_not_empty()

	# Validación preventiva: evitar llamar a `load("res://")` o a rutas sin extensión
	if scene_path == "res://" or scene_path.ends_with("/") or scene_path.get_extension() == "":
		fail("test_determinismo_headless: scene_path inválido en metadata: '%s'. Debe apuntar a un archivo de escena válido (ej. res://scenes/level.tscn)." % scene_path)
		return

	var packed = load(scene_path)
	# Asegurarnos de no llamar a `instance()` sobre un null
	if packed == null:
		fail("test_determinismo_headless: no se pudo cargar la escena: %s" % scene_path)
		return
	if not (packed is PackedScene):
		fail("test_determinismo_headless: recurso cargado no es PackedScene: %s" % scene_path)
		return

	var world_scene = packed.instance()
	# Añadir la escena del mundo al árbol usando call_deferred para evitar diferencias
	# inmediatas entre runner CLI y GUI y dejar que Godot registre internals.
	get_tree().get_root().call_deferred("add_child", world_scene)

	# 2. Instanciar el Player y añadirlo dentro del world_scene
	var player = load("res://core_v2/scenes/Pilot_v2.tscn").instance()
	# Desactivamos procesamiento automático; usaremos `player.step()` manualmente
	player.set_physics_process(false)
	player.set_process(false)

	world_scene.add_child(player)

	# 3. Restauración del estado inicial desde el snapshot (ya en el árbol)
	var buffer = _reference_data.get("buffer", [])
	assert_array(buffer).is_not_empty()

	var initial_snapshot = {}
	if buffer.size() > 0 and typeof(buffer[0]) == TYPE_DICTIONARY and buffer[0].has("snapshot"):
		initial_snapshot = buffer[0]["snapshot"]
	if player.has_method("restore_snapshot") and initial_snapshot != {}:
		# Esperar un par de frames de física para asegurar que el PhysicsServer
		# haya registrado todos los shapes y cuerpos del `world_scene`.
		yield(get_tree(), "physics_frame")
		yield(get_tree(), "physics_frame")
		player.restore_snapshot(initial_snapshot)

	# --- Reporte inicial (pos/vel) antes de la simulación ---
	var initial_pos = player.global_transform.origin
	var initial_vel = null
	if player.has_method("get_velocity"):
		initial_vel = player.get_velocity()
	elif player.get("velocity") != null:
		initial_vel = player.get("velocity")
	print("[REPORT] determinism: initial_pos=", initial_pos, ", initial_vel=", initial_vel, ", buffer_frames=", buffer.size())

	# 4. Bucle de simulación manual teniendo en cuenta las colisiones del world_scene
	for i in range(1, buffer.size()):
		var frame = buffer[i]
		var raw_input = frame.get("input", {})

		var input_obj = InputDataV2.new()
		input_obj.from_dict(raw_input)

		player.step(FIXED_DT, input_obj)

	# 5. Verificación de resultados finales
	var final_expected = _reference_data.get("final_expected_state", {})
	var expected_pos_arr = final_expected.get("position", null)
	var expected_pos = Vector3()
	if expected_pos_arr != null and typeof(expected_pos_arr) == TYPE_ARRAY and expected_pos_arr.size() >= 3:
		expected_pos = Vector3(expected_pos_arr[0], expected_pos_arr[1], expected_pos_arr[2])

	# Preparar expected_vel si existe (para usar en el reporte)
	var expected_vel = null
	var expected_vel_arr = final_expected.get("velocity", null)
	if expected_vel_arr != null and typeof(expected_vel_arr) == TYPE_ARRAY and expected_vel_arr.size() >= 3:
		expected_vel = Vector3(expected_vel_arr[0], expected_vel_arr[1], expected_vel_arr[2])

	var actual_pos = player.global_transform.origin
	# --- Reporte final detallado ---
	var actual_vel = null
	if player.has_method("get_velocity"):
		actual_vel = player.get_velocity()
	elif player.get("velocity") != null:
		actual_vel = player.get("velocity")

	var drift = actual_pos.distance_to(expected_pos)
	var actual_euler = player.global_transform.basis.get_euler()
	var actual_yaw = actual_euler.y
	var actual_pitch = actual_euler.x

	var expected_yaw = final_expected.get("yaw", null)
	var expected_pitch = final_expected.get("pitch", null)
	var yaw_diff = null
	var pitch_diff = null
	if expected_yaw != null:
		yaw_diff = abs(actual_yaw - expected_yaw)
	if expected_pitch != null:
		pitch_diff = abs(actual_pitch - expected_pitch)

	print("[REPORT] determinism: initial_pos=", initial_pos, ", initial_vel=", initial_vel)
	print("[REPORT] determinism: final_pos=", actual_pos, ", expected_pos=", expected_pos, ", drift=", drift)
	print("[REPORT] determinism: final_vel=", actual_vel, ", expected_vel=", (expected_vel if typeof(expected_vel) == TYPE_VECTOR3 else null))
	print("[REPORT] determinism: yaw(actual,expected,diff)=", actual_yaw, expected_yaw, yaw_diff, ", pitch(actual,expected,diff)=", actual_pitch, expected_pitch, pitch_diff)

	assert_vector3(actual_pos).is_equal_approx(expected_pos, Vector3(0.0001, 0.0001, 0.0001))

	# Verificar velocidad final si el estado esperado la incluye
	if expected_vel != null:
		if actual_vel != null:
			assert_vector3(actual_vel).is_equal_approx(expected_vel, Vector3(0.0001, 0.0001, 0.0001))

	# 6. Limpieza: liberar la escena completa del mundo (incluye al player)
	world_scene.free()

func after():
	# Restaurar estado del SessionManager si fuera necesario
	pass
