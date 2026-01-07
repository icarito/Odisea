# /core_v2/tests/test_player_determinism_v2.gd
extends GdUnitTestSuite

# Referencias a dependencias críticas del Core v2
const REFERENCE_PATH = "res://core_v2/tests/reference.json"

var _reference_data: Dictionary

# Funciones de utilidad para el cálculo esperado de plataforma
func _pingpong_logic(value: float, length: float) -> float:
	if length == 0: return 0.0
	return length - abs(fmod(value, 2.0 * length) - length)

func _apply_easing(t: float) -> float:
	# MVP: Sin easing para determinismo perfecto. Solo interpolación linear.
	return t

func before():
	# Carga de datos de referencia generados por SessionManager.gd
	var file = File.new()
	if file.open(REFERENCE_PATH, File.READ) == OK:
		var json_parsed = JSON.parse(file.get_as_text())
		if json_parsed.error == OK:
			_reference_data = json_parsed.result
		file.close()
	
	assert_dict(_reference_data).is_not_empty()

func test_determinismo_headless():
	# 1. Cargar el entorno (world scene) indicado en la metadata del JSON
	var scene_path = ""
	var meta = _reference_data.get("meta", {})
	if typeof(meta) == TYPE_DICTIONARY:
		scene_path = meta.get("scene", "")

	assert_str(scene_path).is_not_empty()

	if scene_path == "res://" or scene_path.ends_with("/") or scene_path.get_extension() == "":
		fail("test_determinismo_headless: scene_path inválido en metadata: '%s'" % scene_path)
		return

	var packed = load(scene_path)
	if packed == null:
		fail("test_determinismo_headless: no se pudo cargar la escena: %s" % scene_path)
		return
	if not (packed is PackedScene):
		fail("test_determinismo_headless: recurso cargado no es PackedScene: %s" % scene_path)
		return

	var world_scene = packed.instance()
	get_tree().get_root().add_child(world_scene)

	# 2. Instanciar el Player
	var player = load("res://core_v2/scenes/Pilot_v2.tscn").instance()
	player.set_physics_process(false)
	player.set_process(false)
	world_scene.add_child(player)

	# 3. Esperar a que la escena se registre en PhysicsServer
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")

	# 4. Obtener datos del buffer
	var buffer = _reference_data.get("buffer", []).duplicate(true)
	assert_array(buffer).is_not_empty()

	# 5. Obtener datos de estado inicial del mundo (plataformas, etc.)
	var world_start_state = {}
	if meta.has("world_start_state"):
		world_start_state = meta.get("world_start_state", {})
	
	# 5b. Obtener datos esperados finales
	var _final_expected_state = _reference_data.get("final_expected_state", {})

	print("[REPORT] determinism: buffer_frames=", buffer.size(), ", has_world_start_state=", world_start_state.size() > 0)

	# 6. Restaurar estado inicial del mundo ANTES de simular
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	for node_path in world_start_state.keys():
		var node = get_tree().get_root().get_node_or_null(node_path)
		if node and node.has_method("restore_snapshot"):
			node.restore_snapshot(world_start_state[node_path])

	# 7. Restaurar estado inicial del jugador desde el primer snapshot del buffer
	var buffer_copy = buffer.duplicate(true)
	if buffer_copy.size() > 0 and buffer_copy[0].has("snapshot"):
		if player.has_method("restore_snapshot"):
			player.restore_snapshot(buffer_copy[0]["snapshot"])
		buffer_copy.remove(0)

	# 8. Crear InputProviderV2 en modo REPLAY
	var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
	var input_provider = InputProviderV2.new()
	var input_buffer = []
	for entry in buffer_copy:
		if entry.has("input"):
			input_buffer.append(entry["input"])
	input_provider.set_replay_data(input_buffer)

	# 9. Asignar provider al jugador
	if "input_provider" in player:
		player.input_provider = input_provider
	player.is_replay_mode = true
	player.set_physics_process(true)

	# 10. Desactivar _physics_process en plataformas (usaremos step centralizado)
	for node in sync_nodes:
		if node != player:
			print("[TEST] Disabling physics_process for: ", node.name)
			node.set_physics_process(false)

	# 11. Ejecutar la simulación FIXED_DT step-by-step
	var FIXED_DT = 1.0 / 60.0
	var frame_count = 0
	var max_frames = 4000
	var platform = get_tree().get_root().get_node_or_null("/root/TestScene/MovingPlatformV2")
	var _last_platform_pos = platform.global_transform.origin if platform else Vector3.ZERO
	var _platform_diverge_frame = -1
	var _player_diverge_frame = -1
	var _player_initial_pos = player.global_transform.origin
	
	print("[DEBUG] Platform at restore: pos=", platform.global_transform.origin if platform else "N/A")
	
	while frame_count < max_frames and input_provider.playback_index < input_provider.playback_buffer.size():
		# Obtener input
		var input = input_provider.get_input()
		
		if frame_count == 0:
			print("[TEST] Frame 0: input=", input.to_dict(), " playback_index=", input_provider.playback_index)
			print("[TEST] Player pos at frame 0: ", player.global_transform.origin)

		# Step player FIRST (mismo orden que en SessionManager)
		if player.has_method("step"):
			player.step(FIXED_DT, input)
			# Marcar que el input fue consumido externamente, igual que en SessionManager
			if "external_input_provided" in player:
				player.external_input_provided = true

		# Step plataformas SECOND
		for node in sync_nodes:
			if node != player and node.has_method("step"):
				var pos_before = node.global_transform.origin
				node.step(FIXED_DT)
				var pos_after = node.global_transform.origin
				if frame_count < 3:
					print("[TEST] Frame ", frame_count, " platform: ", pos_before, " -> ", pos_after, " move_dist=", pos_before.distance_to(pos_after))

		# Rastrear divergencia de plataforma cada 60 frames
		if platform and frame_count % 60 == 0 and frame_count > 0:
			var curr_platform_pos = platform.global_transform.origin
			# Calcular posición esperada usando lógica de easing (como lo hace la plataforma)
			var plat_snapshot = world_start_state.get("/root/TestScene/MovingPlatformV2", {})
			var snap_pos = Vector3(plat_snapshot.get("pos", [0, 0, 0])[0], plat_snapshot.get("pos", [0, 0, 0])[1], plat_snapshot.get("pos", [0, 0, 0])[2])
			var snap_time = plat_snapshot.get("time", 0)
			var snap_cycle_duration = plat_snapshot.get("cycle_duration", 4.0)
			var snap_movement_vector = Vector3(plat_snapshot.get("movement_vector", [0, 0, 0])[0], plat_snapshot.get("movement_vector", [0, 0, 0])[1], plat_snapshot.get("movement_vector", [0, 0, 0])[2])
			
			# Usar start_position del snapshot si existe, sino calcular
			var snap_start_position: Vector3
			if plat_snapshot.has("start_position"):
				var sp = plat_snapshot.get("start_position", [0, 0, 0])
				snap_start_position = Vector3(sp[0], sp[1], sp[2])
			else:
				# Calcular start_position retroactivamente desde pos y time
				var half_cycle = snap_cycle_duration / 2.0
				var snap_progress_value = _pingpong_logic(snap_time, half_cycle) / half_cycle if half_cycle > 0 else 0.0
				var snap_cooked_progress = _apply_easing(snap_progress_value)
				snap_start_position = snap_pos - snap_movement_vector * snap_cooked_progress
			
			# Calcular posición esperada en frame actual
			# IMPORTANTE: El snapshot se restaura ANTES del loop, luego en frame 0 se llama step().
			# Así que cuando frame_count=0, ya se ha ejecutado 1 step. Por eso sumamos (frame_count + 1).
			var current_time = snap_time + FIXED_DT * (frame_count + 1)
			var half_cycle = snap_cycle_duration / 2.0
			
			# Simular pingpong_logic EXACTAMENTE como está en MovingPlatformV2
			var raw_progress_value = _pingpong_logic(current_time, half_cycle) / half_cycle if half_cycle > 0 else 0.0
			
			# Simular apply_easing para SINE (ease_type=1)
			var cooked_progress = _apply_easing(raw_progress_value)
			
			# Calcular expected_pos
			var expected_pos = snap_start_position + snap_movement_vector * cooked_progress
			
			var drift_platform = curr_platform_pos.distance_to(expected_pos)
			if drift_platform > 0.01 and _platform_diverge_frame == -1:
				_platform_diverge_frame = frame_count
				print("⚠️ PLATFORM DIVERGENCE at frame ", frame_count, ": time=", current_time, " raw=", raw_progress_value, " cooked=", cooked_progress)
				print("  actual=", curr_platform_pos, ", expected=", expected_pos, ", drift=", drift_platform)

		frame_count += 1
	
	print("DEBUG: Platform divergence frame: ", _platform_diverge_frame)

	# 12. Capturar estado final
	var final_pos = player.global_transform.origin
	var final_vel = player.velocity if "velocity" in player else Vector3.ZERO
	var final_yaw = player.yaw if "yaw" in player else 0.0
	var final_pitch = player.pitch if "pitch" in player else 0.0

	# 13. Verificación de resultados finales
	var final_expected = _reference_data.get("final_expected_state", {})
	var expected_pos_arr = final_expected.get("position", null)
	var expected_pos = Vector3()
	if expected_pos_arr != null and typeof(expected_pos_arr) == TYPE_ARRAY and expected_pos_arr.size() >= 3:
		expected_pos = Vector3(expected_pos_arr[0], expected_pos_arr[1], expected_pos_arr[2])

	var expected_vel = null
	var expected_vel_arr = final_expected.get("velocity", null)
	if expected_vel_arr != null and typeof(expected_vel_arr) == TYPE_ARRAY and expected_vel_arr.size() >= 3:
		expected_vel = Vector3(expected_vel_arr[0], expected_vel_arr[1], expected_vel_arr[2])

	var drift = final_pos.distance_to(expected_pos)
	var expected_yaw = final_expected.get("yaw", null)
	var expected_pitch = final_expected.get("pitch", null)
	var yaw_diff = null
	var pitch_diff = null
	if expected_yaw != null:
		yaw_diff = abs(final_yaw - expected_yaw)
	if expected_pitch != null:
		pitch_diff = abs(final_pitch - expected_pitch)

	print("[REPORT] determinism: final_pos=", final_pos, ", expected_pos=", expected_pos, ", drift=", drift)
	print("[REPORT] determinism: final_vel=", final_vel, ", expected_vel=", (expected_vel if typeof(expected_vel) == TYPE_VECTOR3 else null))
	print("[REPORT] determinism: yaw(actual,expected,diff)=", final_yaw, ",", expected_yaw, ",", yaw_diff, ", pitch(actual,expected,diff)=", final_pitch, ",", expected_pitch, ",", pitch_diff)
	print("PLAYBACK_END")
	print("rotation:", final_yaw, ",", final_pitch)
	print("pos:", final_pos)
	print("expected_pos:", expected_pos)
	print("DRIFT_CHECK: dist=", drift, ", yaw_diff=", yaw_diff, ", pitch_diff=", pitch_diff)

	# 14. Assertion - Validación estricta de determinismo
	assert_vector3(final_pos).is_equal_approx(expected_pos, Vector3(0.0001, 0.0001, 0.0001))

	if expected_vel != null and final_vel != null:
		assert_vector3(final_vel).is_equal_approx(expected_vel, Vector3(0.5, 0.5, 0.5))

	# 15. Limpieza
	world_scene.free()

func after():
	pass
