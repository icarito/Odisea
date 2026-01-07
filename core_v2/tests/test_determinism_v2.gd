# /core_v2/tests/test_determinism_v2.gd
# Test de determinismo que usa SessionManager directamente (misma lógica que replay CLI)
extends GdUnitTestSuite

const REFERENCE_PATH = "res://core_v2/tests/reference.json"
const FIXED_DT = 1.0 / 60.0

var _reference_data: Dictionary

func before():
	var file = File.new()
	if file.open(REFERENCE_PATH, File.READ) == OK:
		var json_parsed = JSON.parse(file.get_as_text())
		if json_parsed.error == OK:
			_reference_data = json_parsed.result
		file.close()
	assert_dict(_reference_data).is_not_empty()

func test_determinismo_headless():
	# 1. Cargar la escena indicada en metadata
	var meta = _reference_data.get("meta", {})
	var scene_path = meta.get("scene", "") if typeof(meta) == TYPE_DICTIONARY else ""
	assert_str(scene_path).is_not_empty()

	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		fail("No se pudo cargar la escena: %s" % scene_path)
		return

	var world_scene = packed.instance()
	get_tree().get_root().add_child(world_scene)

	# 2. Buscar el player y ponerlo en replay mode temporalmente
	var player = get_tree().get_root().find_node("Pilot", true, false)
	if player:
		player.is_replay_mode = true  # Evitar que consuma input live durante setup
	
	# 3. Esperar UN frame para que _ready() se ejecute y los nodos se agreguen a grupos
	yield(get_tree(), "idle_frame")
	
	# 4. Obtener sync_nodes (plataformas) para debug
	var early_sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	print("[TEST] Found ", early_sync_nodes.size(), " nodes in replay_sync after idle_frame")

	# 5. Esperar otro frame
	yield(get_tree(), "idle_frame")

	# 6. Si no encontramos player antes, buscarlo ahora
	if not player:
		player = get_tree().get_root().find_node("Pilot", true, false)
	if not player:
		# Si no hay Pilot en la escena, instanciar uno
		player = load("res://core_v2/scenes/Pilot_v2.tscn").instance()
		world_scene.add_child(player)
		player.is_replay_mode = true
		yield(get_tree(), "idle_frame")

	# 7. Obtener datos del buffer y world_start_state
	var buffer = _reference_data.get("buffer", []).duplicate(true)
	assert_array(buffer).is_not_empty()
	
	var world_start_state = meta.get("world_start_state", {}) if meta.has("world_start_state") else {}
	var final_expected = _reference_data.get("final_expected_state", {})

	print("[REPORT] determinism: buffer_frames=", buffer.size(), ", has_world_start_state=", world_start_state.size() > 0)

	# 8. Restaurar estado inicial del mundo (plataformas, etc.) - IGUAL QUE SessionManager
	for node_path in world_start_state.keys():
		var node = get_tree().get_root().get_node_or_null(node_path)
		if node and node.has_method("restore_snapshot"):
			node.restore_snapshot(world_start_state[node_path])

	# 7. Restaurar estado inicial del jugador desde el primer snapshot del buffer
	if buffer.size() > 0 and buffer[0].has("snapshot"):
		if player.has_method("restore_snapshot"):
			player.restore_snapshot(buffer[0]["snapshot"])
			print("[TEST] Player restored to: ", player.global_transform.origin)
		buffer.remove(0)

	# 8. Crear InputProviderV2 y cargar inputs
	var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
	var input_provider = InputProviderV2.new()
	var input_buffer = []
	for entry in buffer:
		if entry.has("input"):
			input_buffer.append(entry["input"])
	input_provider.set_replay_data(input_buffer)

	# 9. Asignar provider al jugador
	if "input_provider" in player:
		player.input_provider = input_provider

	# 10. ACTIVAR physics en player y plataformas - usar el engine real de Godot
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	print("[TEST] sync_nodes count: ", sync_nodes.size())
	
	# Activar _physics_process en plataformas (el engine las moverá)
	for node in sync_nodes:
		print("[TEST] sync_node: ", node.name, " has_step=", node.has_method("step"))
		if node != player:
			node.set_physics_process(true)
	
	# Activar physics en player también
	player.set_physics_process(true)
	player.is_replay_mode = false  # Dejar que el player use su _physics_process normal

	# 11. Ejecutar simulación usando physics frames REALES del engine
	var frame_count = 0
	var max_frames = 4000

	while frame_count < max_frames and input_provider.playback_index < input_provider.playback_buffer.size():
		# Esperar un physics frame real del engine
		yield(get_tree(), "physics_frame")

		frame_count += 1

	print("[TEST] Total frames executed: ", frame_count)

	# 11. Capturar y validar estado final
	var final_pos = player.global_transform.origin
	var final_yaw = player.yaw if "yaw" in player else 0.0
	var final_pitch = player.pitch if "pitch" in player else 0.0

	var expected_pos_arr = final_expected.get("position", [0, 0, 0])
	var expected_pos = Vector3(expected_pos_arr[0], expected_pos_arr[1], expected_pos_arr[2])
	var expected_yaw = final_expected.get("yaw", 0.0)
	var expected_pitch = final_expected.get("pitch", 0.0)

	var drift = final_pos.distance_to(expected_pos)
	var yaw_diff = abs(final_yaw - expected_yaw)
	var pitch_diff = abs(final_pitch - expected_pitch)

	print("[REPORT] determinism: final_pos=", final_pos, ", expected_pos=", expected_pos, ", drift=", drift)
	print("PLAYBACK_END")
	print("rotation:", final_yaw, ",", final_pitch)
	print("pos:", final_pos)
	print("expected_pos:", expected_pos)
	print("DRIFT_CHECK: dist=", drift, ", yaw_diff=", yaw_diff, ", pitch_diff=", pitch_diff)

	# 12. Assertion - Validación estricta de determinismo
	assert_vector3(final_pos).is_equal_approx(expected_pos, Vector3(0.0001, 0.0001, 0.0001))

	# 13. Limpieza
	world_scene.free()

func after():
	pass
