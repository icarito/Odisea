extends Node

var player: KinematicBody = null
var _player_searched = false
var buffer := []
var is_recording := false
var is_replaying := false
var replay_meta := {} # Metadatos del replay
var final_expected_state = null
var is_cli_mode := false
var _drift_validated := false

func _find_player():
	if not is_instance_valid(player) and get_tree().current_scene:
		# Busca al jugador en la escena actual. Asumimos que se llama 'Pilot_v2'.
		player = get_tree().get_root().find_node("Pilot", true, false)
		if not is_instance_valid(player):
			player = null # Asegurarse de que sea nulo si no se encuentra.

func _ready():
	# Detección de parámetro --replay
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--replay" and i + 1 < args.size():
			is_cli_mode = true
			var replay_path = args[i+1]
			# NO llamamos a load_and_play aquí. La escena aún no está lista.
			# En su lugar, nos conectamos a la señal 'tree_changed'.
			# Se disparará cuando la escena principal se cargue, y entonces ejecutaremos el replay.
			get_tree().connect("tree_changed", self, "_on_tree_changed_for_replay", [replay_path], CONNECT_ONESHOT)
			return

	
	# Capturar el mouse solo si no estamos en un entorno de test.
	# Hacemos la llamada de forma segura para evitar un error de compilación
	# cuando GdUnit3 no está presente (ej. en una ejecución normal).
	var is_testing = false
	if Engine.has_singleton("GdUnit3"):
		is_testing = Engine.get_singleton("GdUnit3").is_test_suite()
	
	# Do not capture mouse in CLI mode or during tests.
	if not is_testing and not is_cli_mode:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_tree_changed_for_replay(replay_path: String):
	# Esta función se ejecuta una sola vez cuando la escena principal está lista.
	# Ahora es seguro buscar al jugador y cargar el replay.
	_find_player()
	load_and_play(replay_path)

func _unhandled_input(event):
	# Gestionamos la captura y liberación del mouse de forma centralizada.
	# Esto evita que el PlayerController tenga que saber sobre el estado del UI.
	var is_testing = false
	if Engine.has_singleton("GdUnit3"):
		is_testing = Engine.get_singleton("GdUnit3").is_test_suite()

	# Do not manage mouse input in CLI mode or during tests.
	if not is_testing and not is_cli_mode:
		if event.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# Re-capturar al hacer click en la pantalla, solo si el cursor está visible.
		if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(_dt):
	_find_player()

	if Input.is_action_just_pressed("record-toggle"):
		if not is_recording:
			start_recording()
		else:
			stop_and_save_recording()

	if is_replaying:
		run_playback()
	elif is_recording:
		# Consumir input desde el provider una única vez y usar ese mismo input
		var input_data = null
		if player and "input_provider" in player and player.input_provider:
			input_data = player.input_provider.get_input()
		else:
			input_data = null
		if input_data == null:
			input_data = InputDataV2.new()
		buffer.append({"input": input_data.to_dict()})
		# Ejecutar el step del jugador con el mismo input para mantener sincronía
		if player and player.has_method("step"):
			# usamos el FIXED_DT del player si existe
			var dt = player.FIXED_DT if "FIXED_DT" in player else 1.0/60.0
			player.step(dt, input_data)
			# señalizamos para que PlayerController no vuelva a consumir el input este frame
			player.external_input_provided = true

func start_recording():
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede iniciar la grabación, no se encontró al jugador.")
		return
	buffer.clear()
	is_recording = true
	replay_meta = {
		"date": OS.get_datetime(),
		"unix_time": OS.get_unix_time(),
		"scene": get_tree().current_scene.filename,
		"world_snapshot": {}
	}

	# --- Capturar estado inicial del mundo (nodos en 'replay_sync') ---
	var world_snapshot = {}
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	for node in sync_nodes:
		if node.has_method("get_snapshot"):
			world_snapshot[node.get_path()] = node.get_snapshot()
		else:
			printerr("Node %s in group 'replay_sync' does not have get_snapshot() method." % node.name)
	replay_meta["world_snapshot"] = world_snapshot

	# Guardamos el estado inicial como primer elemento del buffer
	buffer.append({"snapshot": player.get_full_snapshot()})
	var cam = player.get_node_or_null("CameraRig")
	print("GRAB_START\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

func stop_and_save_recording():
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede detener la grabación, no se encontró al jugador.")
		return
	is_recording = false
	var cam = player.get_node_or_null("CameraRig")
	print("GRAB_END\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)
	var file_path = "user://replay_" + str(OS.get_unix_time()) + ".json"
	var file = File.new()
	file.open(file_path, File.WRITE)
	var out = {
		"meta": replay_meta,
		"buffer": buffer,
		"final_expected_state": player.get_full_snapshot()
	}
	file.store_string(JSON.print(out))
	file.close()
	print("💾 Replay guardado en: ", file_path)

var _playback_printed_start := false
var _playback_printed_end := false

func load_and_play(path: String):
	var file = File.new()
	if not file.file_exists(path):
		print("❌ Error: El archivo de replay no existe")
		return
	file.open(path, File.READ)
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	if typeof(parsed.result) == TYPE_DICTIONARY and parsed.result.has("buffer"):
		buffer = parsed.result["buffer"]
		if buffer.size() > 0 and buffer[0].has("snapshot"):
			if player and player.has_method("restore_snapshot"):
				player.restore_snapshot(buffer[0]["snapshot"])
				var cam = player.get_node_or_null("CameraRig")
				print("PLAYBACK_START\nrotation:", player.yaw, ",", player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)
				_playback_printed_start = true
			else:
				print("❌ El nodo player no tiene restore_snapshot() (tipo:", typeof(player), ")")
			buffer.remove(0)
		# Inyectar buffer al input_provider en modo REPLAY
		if player and "input_provider" in player and player.input_provider and player.input_provider.has_method("set_replay_data"):
			var input_buffer = []
			for entry in buffer:
				if entry.has("input"):
					input_buffer.append(entry["input"])
			player.input_provider.set_replay_data(input_buffer)
		else:
			print("❌ No se pudo acceder a input_provider en player para replay.")
		# Cargar snapshot final esperado si existe
		if typeof(parsed.result) == TYPE_DICTIONARY and parsed.result.has("final_expected_state"):
			final_expected_state = parsed.result["final_expected_state"]
		else:
			final_expected_state = null
		_drift_validated = false
		is_replaying = true
		print("▶️ Reproduciendo replay desde CLI...")
	else:
		print("❌ Formato de replay inválido")

func _finish_and_validate():
	if _drift_validated: return
	_drift_validated = true
	
	# 1. Imprimir estado final
	if player:
		var cam = player.get_node_or_null("CameraRig")
		print("PLAYBACK_END\nrotation:", player.yaw, ",", player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

	# 2. Validar drift
	var success = true
	if final_expected_state == null:
		print("⚠️ No hay final_expected_state para validar.")
	else:
		var exp_pos_arr = final_expected_state.get("position", null)
		if exp_pos_arr == null or typeof(exp_pos_arr) != TYPE_ARRAY:
			print("⚠️ final_expected_state inválido (sin posición)")
		else:
			var expected_pos = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
			var current_pos = player.global_transform.origin
			var dist = current_pos.distance_to(expected_pos)
			var expected_yaw = final_expected_state.get("yaw", 0.0)
			var expected_pitch = final_expected_state.get("pitch", 0.0)
			var yaw_diff = abs(player.yaw - expected_yaw)
			var pitch_diff = abs(player.pitch - expected_pitch)
			print("DRIFT_CHECK: dist=", dist, ", yaw_diff=", yaw_diff, ", pitch_diff=", pitch_diff)
			var pos_threshold = 0.0001
			var ang_threshold = 0.0001
			if dist > pos_threshold:
				printerr("❌ DRIFT ERROR: Positional drift = ", dist, " > ", pos_threshold)
				success = false
			else:
				print("✅ Positional drift dentro del umbral")
			if yaw_diff > ang_threshold or pitch_diff > ang_threshold:
				printerr("❌ ROTATION DRIFT: yaw=", yaw_diff, ", pitch=", pitch_diff, " (umbral=", ang_threshold, ")")
				success = false
			else:
				print("✅ Rotational drift dentro del umbral")

	# 3. Salir si estamos en modo CLI
	if is_cli_mode:
		get_tree().quit(0 if success else 1)

func run_playback():
	_find_player()

	# Detectar cuando el provider llega al final del buffer y validar
	if player and "input_provider" in player and player.input_provider:
		var prov = player.input_provider
		if prov.mode == prov.Mode.REPLAY:
			var idx = prov.playback_index
			var sz = prov.playback_buffer.size()
			if idx >= sz and not _drift_validated:
				_finish_and_validate()