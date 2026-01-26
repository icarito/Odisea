extends Node
const FIXED_DT := 1.0 / 60.0
signal replay_finished(success, drift, frames)

var player: KinematicBody = null
var _player_searched = false
var buffer := []
var is_recording := false
var is_replaying := false
var replay_meta := {} # Metadatos del replay
var final_expected_state = null
var is_cli_mode := false
var _drift_validated := false
var _is_replaying_fail_loop := false # Flag para evitar loops infinitos si falla

# Drift correction: checkpoint pendiente para guardar en el próximo frame
var _pending_drift_checkpoint := false
# Drift correction: frame en el que guardar un checkpoint "settle" (15 frames después del contacto)
var _pending_settle_checkpoint_frame := -1
# Drift correction en replay: diccionario {frame_index: position}
var _drift_checkpoints := {}
# Contador de frames durante grabación
var _recording_frame := 0

func _find_player():
	if not is_instance_valid(player):
		# Prioridad 1: Buscar en el árbol desde la raíz (más genérico)
		player = get_tree().get_root().find_node("Pilot", true, false)
		# Prioridad 2: Buscar en la escena actual si la raíz falló o dio un nodo inválido
		if not is_instance_valid(player) and get_tree().current_scene:
			player = get_tree().current_scene.find_node("Pilot", true, false)
		
		if not is_instance_valid(player):
			player = null

func _ready():
	# Detección de parámetro --replay
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--replay" and i + 1 < args.size():
			is_cli_mode = true
			var replay_path = args[i + 1]
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
	# Esperamos un frame idle para que todos los nodos ejecuten _ready() y se agreguen a sus grupos
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")
	
	# Ahora es seguro buscar al jugador y cargar el replay.
	_find_player()
	if player:
		player.is_replay_mode = true
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


var _replay_frame := 0
var _total_replay_frames := 0

func _physics_process(_dt):
	_find_player()

	if Input.is_action_just_pressed("record-toggle"):
		if not is_recording:
			start_recording()
		else:
			stop_and_save_recording()

	if is_replaying:
		# Obtener input primero para verificar si hay más inputs disponibles
		if not player or not player.has_method("step"):
			run_playback() # Solo para terminar replay si no hay player
			_replay_frame += 1
			return
		
		# Aplicar drift checkpoint si existe para este frame (ANTES del step)
		if _drift_checkpoints.has(_replay_frame):
			var checkpoint_pos = _drift_checkpoints[_replay_frame]
			var current_pos = player.global_transform.origin
			var drift = current_pos.distance_to(checkpoint_pos)
			if drift > 0.001:
				print("[DriftCorrection] Frame %d: Aplicando corrección. Drift=%.6f, Pos actual=%s -> %s" % [_replay_frame, drift, current_pos, checkpoint_pos])
				var t = player.global_transform
				t.origin = checkpoint_pos
				player.global_transform = t
			
		var input = player.input_provider.get_input()
		
		# Si no hay más inputs, terminar
		if input == null:
			run_playback()
			return
		
		# Step player con el input
		player.step(FIXED_DT, input)
		
		# Step plataformas
		var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
		for node in sync_nodes:
			if node != player and node.has_method("step"):
				node.step(FIXED_DT)
		
		_replay_frame += 1
		_total_replay_frames = _replay_frame
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
		
		var frame_entry = {"input": input_data.to_dict()}
		
		# Guardar drift checkpoint si el player dejó de tocar un RigidBody
		if _pending_drift_checkpoint:
			frame_entry["drift_checkpoint"] = {
				"position": var2str(player.global_transform.origin)
			}
			_pending_drift_checkpoint = false
			# Programar un checkpoint "settle" 15 frames después
			_pending_settle_checkpoint_frame = _recording_frame + 15
		
		# Guardar checkpoint "settle" si llegamos al frame programado
		if _recording_frame == _pending_settle_checkpoint_frame:
			frame_entry["drift_checkpoint"] = {
				"position": var2str(player.global_transform.origin)
			}
			_pending_settle_checkpoint_frame = -1
		
		buffer.append(frame_entry)
		_recording_frame += 1
		# Step player
		if player and player.has_method("step"):
			player.step(FIXED_DT, input_data)
			# señalizamos para que PlayerController no vuelva a consumir el input este frame
			player.external_input_provided = true
		# Step plataformas TAMBIÉN durante grabación para determinismo
		var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
		for node in sync_nodes:
			if node != player and node.has_method("step"):
				node.step(FIXED_DT)

func start_recording():
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede iniciar la grabación, no se encontró al jugador.")
		return
	buffer.clear()
	is_recording = true
	_pending_drift_checkpoint = false
	_pending_settle_checkpoint_frame = -1
	_recording_frame = 0
	replay_meta = {
		"date": OS.get_datetime(),
		"unix_time": OS.get_unix_time(),
		"scene": get_tree().current_scene.filename,
		"world_snapshot": {}
	}

	# --- Resetear nodos replay_sync a estado inicial ---
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	# Desactivar _physics_process en plataformas durante grabación para usar step centralizado
	for node in sync_nodes:
		if node != player and node.has_method("step"):
			node.set_physics_process(false)
	
	# Marcar player como "controlado externamente" para evitar doble step
	if player:
		player.is_replay_mode = true # Usamos esta bandera para indicar control externo
		# Conectar señal de drift correction
		if player.has_signal("rigid_contact_ended") and not player.is_connected("rigid_contact_ended", self, "_on_rigid_contact_ended"):
			player.connect("rigid_contact_ended", self, "_on_rigid_contact_ended")
	
	# --- Capturar estado inicial del mundo (nodos en 'replay_sync') ---
	var world_start_state = {}
	for node in sync_nodes:
		if node.has_method("get_snapshot"):
			world_start_state[node.get_path()] = node.get_snapshot()
		else:
			printerr("Node %s in group 'replay_sync' does not have get_snapshot() method." % node.name)
	replay_meta["world_start_state"] = world_start_state

	# Guardamos el estado inicial como primer elemento del buffer
	buffer.append({"snapshot": player.get_full_snapshot()})
	var cam = player.get_node_or_null("CameraRig")
	print("GRAB_START\nrotation:", player.yaw, player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

func _on_rigid_contact_ended():
	# Marcar que debemos guardar un checkpoint en el próximo frame del buffer
	_pending_drift_checkpoint = true

func stop_and_save_recording():
	if not is_instance_valid(player):
		printerr("SessionManager: No se puede detener la grabación, no se encontró al jugador.")
		return
	is_recording = false
	
	# Restaurar control normal del player
	if player:
		player.is_replay_mode = false
	
	# Reactivar _physics_process en plataformas
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	for node in sync_nodes:
		if node != player and node.has_method("step"):
			node.set_physics_process(true)
	
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
	print("[SessionManager] load_and_play called with: ", path)
	var file = File.new()
	if not file.file_exists(path):
		printerr("❌ Error: El archivo de replay no existe: ", path)
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return
	file.open(path, File.READ)
	var parsed = JSON.parse(file.get_as_text())
	file.close()

	if typeof(parsed.result) != TYPE_DICTIONARY:
		printerr("❌ Formato de replay inválido")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return

	var data = parsed.result
	var input_buffer_raw = data.get("buffer", [])

	# Extract pure input from buffer entries
	var input_buffer = []
	for entry in input_buffer_raw:
		if entry.has("input"):
			input_buffer.append(entry["input"])

	play_buffer(input_buffer, data)


func play_buffer(input_buffer: Array, replay_data: Dictionary):
	_find_player()

	if not is_instance_valid(player):
		printerr("❌ SessionManager: Player no encontrado para iniciar replay.")
		call_deferred("emit_signal", "replay_finished", false, -1.0, 0)
		return

	var meta = replay_data.get("meta", {})

	# Restaurar estado inicial del mundo ANTES del player
	if meta.has("world_start_state"):
		var world_start_state = meta["world_start_state"]
		for path in world_start_state.keys():
			var node = get_tree().get_root().get_node_or_null(path)
			if node and node.has_method("restore_snapshot"):
				node.restore_snapshot(world_start_state[path])

	# Restaurar snapshot inicial del player si existe
	if replay_data.get("buffer", [{}])[0].has("snapshot"):
		player.restore_snapshot(replay_data["buffer"][0]["snapshot"])

	# Desactivar _physics_process en plataformas
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	for node in sync_nodes:
		if node != player:
			node.set_physics_process(false)

	player.is_replay_mode = true
	player.input_provider.set_replay_data(input_buffer)

	final_expected_state = replay_data.get("final_expected_state", null)
	_drift_validated = false
	is_replaying = true
	_replay_frame = 0 # Reset frame counter
	print("▶️ Reproduciendo replay desde buffer...")

func _finish_and_validate():
	if _drift_validated:
		return
	_drift_validated = true
	var success = true
	var dist = -1.0
	var frames = _total_replay_frames

	# 1. Imprimir estado final
	if player:
		var cam = player.get_node_or_null("CameraRig")
		print("PLAYBACK_END\nrotation:", player.yaw, ",", player.pitch, "\npos:", player.global_transform.origin, "\ncam:", cam.global_transform.origin)

	# 2. Validar drift
	if final_expected_state == null:
		print("⚠️ No hay final_expected_state para validar.")
	else:
		var exp_pos_arr = final_expected_state.get("position", null)
		if exp_pos_arr == null or typeof(exp_pos_arr) != TYPE_ARRAY:
			print("⚠️ final_expected_state inválido (sin posición)")
		else:
			var expected_pos = Vector3(exp_pos_arr[0], exp_pos_arr[1], exp_pos_arr[2])
			var current_pos = player.global_transform.origin if player else Vector3()
			dist = current_pos.distance_to(expected_pos)
			var expected_yaw = final_expected_state.get("yaw", 0.0)
			var expected_pitch = final_expected_state.get("pitch", 0.0)
			var yaw_diff = abs(player.yaw - expected_yaw) if player else 0.0
			var pitch_diff = abs(player.pitch - expected_pitch) if player else 0.0
			print("DRIFT_CHECK: dist=", dist, ", yaw_diff=", yaw_diff, ", pitch_diff=", pitch_diff)
			var pos_threshold = 0.0005
			var ang_threshold = 0.0005
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

	# Emit signal for external listeners/tests
	print("[SessionManager] EMITTING replay_finished: ", success, ", ", dist, ", ", frames)
	emit_signal("replay_finished", success, dist, frames)

	# 3. Salir si estamos en modo CLI
	if is_cli_mode:
		print("[SessionManager] Exiting CLI mode")
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

# Helper para tests: ejecuta la simulación desde un buffer
# Asume que player ya está en el árbol y que las plataformas también están instanciadas
func run_simulation_from_buffer(buffer_data: Array, world_start_state: Dictionary, player_controller: Node, yield_frames: int = 3) -> Dictionary:
	var result = {
		"final_pos": null,
		"final_vel": null,
		"final_yaw": null,
		"final_pitch": null,
		"drift": 0.0,
		"passed": false
	}
	
	if not player_controller:
		printerr("SessionManager: player_controller is null")
		return result
	
	# 0. Esperar a que el árbol registre todos los nodos en physics_server
	for _i in range(yield_frames):
		player_controller.get_tree().call_group("", "update") # Update all nodes
	
	# 1. Restaurar estado inicial del mundo (plataformas, etc.)
	var sync_nodes = get_tree().get_nodes_in_group("replay_sync")
	for node_path in world_start_state.keys():
		var node = get_tree().get_root().get_node_or_null(node_path)
		if node and node.has_method("restore_snapshot"):
			node.restore_snapshot(world_start_state[node_path])
		else:
			print("Warning: Could not restore node at path ", node_path)
	
	# 2. Restaurar estado inicial del jugador si hay snapshot
	var buffer_copy = buffer_data.duplicate(true)
	if buffer_copy.size() > 0 and buffer_copy[0].has("snapshot"):
		if player_controller.has_method("restore_snapshot"):
			player_controller.restore_snapshot(buffer_copy[0]["snapshot"])
		buffer_copy.remove(0)
	
	# 3. Crear InputProviderV2 en modo REPLAY
	var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
	var input_provider = InputProviderV2.new()
	var input_buffer = []
	for entry in buffer_copy:
		if entry.has("input"):
			input_buffer.append(entry["input"])
	input_provider.set_replay_data(input_buffer)
	
	# 4. Asignar provider al jugador
	if "input_provider" in player_controller:
		player_controller.input_provider = input_provider
	player_controller.is_replay_mode = true
	player_controller.set_physics_process(true)
	
	# 5. Desactivar _physics_process en plataformas (usaremos step centralizado)
	for node in sync_nodes:
		if node != player_controller:
			node.set_physics_process(false)
	
	# 6. Ejecutar la simulación
	var frame_count = 0
	var max_frames = 4000 # XXX: Why do we need this limit?
	while frame_count < max_frames and input_provider.playback_index < input_provider.playback_buffer.size():
		# Obtener input
		var input = input_provider.get_input()
		
		# Step player
		if player_controller.has_method("step"):
			player_controller.step(FIXED_DT, input)
		
		# Step plataformas
		for node in sync_nodes:
			if node != player_controller and node.has_method("step"):
				node.step(FIXED_DT)
		
		frame_count += 1
	
	# 7. Capturar estado final
	result["final_pos"] = player_controller.global_transform.origin
	result["final_vel"] = player_controller.velocity if "velocity" in player_controller else Vector3.ZERO
	result["final_yaw"] = player_controller.yaw if "yaw" in player_controller else 0.0
	result["final_pitch"] = player_controller.pitch if "pitch" in player_controller else 0.0
	
	# 8. Limpiar
	player_controller.is_replay_mode = false
	
	return result