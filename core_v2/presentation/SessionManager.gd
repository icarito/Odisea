extends Node

export(NodePath) var player_path
onready var player = get_node(player_path)

var buffer := []
var is_recording := false
var is_replaying := false
var replay_meta := {} # Metadatos del replay
var final_expected_state = null
var is_cli_mode := false
var _drift_validated := false

func _ready():
	# Detección de parámetro --replay
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--replay" and i + 1 < args.size():
			is_cli_mode = true
			load_and_play(args[i+1])

func _physics_process(_dt):
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
	buffer.clear()
	is_recording = true
	replay_meta = {
		"date": OS.get_datetime(),
		"unix_time": OS.get_unix_time(),
		"scene": get_tree().current_scene.filename
	}
	# Guardamos el estado inicial como primer elemento del buffer
	buffer.append({"snapshot": player.get_full_snapshot()})
	var cam = player.camera_rig if player.camera_rig else null
	print("GRAB_START\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

func stop_and_save_recording():
	is_recording = false
	var cam = player.camera_rig if player.camera_rig else null
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
				var cam = player.camera_rig if player.camera_rig else null
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
		var cam = player.camera_rig
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
	# Detectar cuando el provider llega al final del buffer y validar
	if player and "input_provider" in player and player.input_provider:
		var prov = player.input_provider
		if prov.mode == prov.Mode.REPLAY:
			var idx = prov.playback_index
			var sz = prov.playback_buffer.size()
			if idx >= sz and not _drift_validated:
				_finish_and_validate()
