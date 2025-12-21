extends Node

signal playback_started(total_frames)
signal playback_stopped
signal playback_failed
signal playback_paused
signal playback_resumed
signal frame_updated(frame_index, total_frames)

const ReplayScript = preload("res://scripts/replay/Replay.gd")
const GameGlobals = preload("res://autoload/GameGlobals.gd")
const REPLAY_GROUP = "replay_track"
const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]
const DRIFT_THRESHOLD = 0.05 # Maximum allowed position difference before correction
const DRIFT_SNAP_THRESHOLD = 0.5 # Umbral de teletransporte de emergencia (hard snap)
const MAX_CORRECTION_DISTANCE = 0.5 # Max distance to correct per frame, use snapping above this
const RESYNC_INTERVAL = 1 # Corregir drift cada frame para evitar acumulación
const ROTATION_DRIFT_THRESHOLD = 0.05 # ~0.5 grados
const DRIFT_CORRECTION_STRENGTH = 100.0 # Suavidad de la corrección. 10 es firme, 5 es suave.
const MIN_DIVERGENCE_TO_CORRECT = 0.01 # Threshold to avoid insignificant corrections
const FIXED_DELTA = 1.0 / 60.0 # Fixed delta para 60 FPS (máxima precisión)
const IGNORE_THRESHOLD = 0.001 # Ignore micro-drift to eliminate floating
const FAST_LERP_THRESHOLD = 0.05 # Use ultra-fast LERP if between this and SNAP
const SNAP_THRESHOLD = 0.02 # Instant correction threshold (10cm, forzar corrección agresiva)
const LERP_STRENGTH_ULTRA_FAST = 200.0 # Ultra-fast LERP strength
const PILOT_STATE_KEY = "Pilot" # Key correcta según el JSON grabado

var current_replay: Resource = null
var current_replay_filename: String = ""
var frame_index: int = 0
var total_logical_frames: int = 0
var playback_paused: bool = false
var playback_status: String = "Stopped"  # "Playing", "Paused", "Stopped"

var time_accumulator: float = 0.0
var headless: bool = false
var playback_start_time: int = 0
var frame_count: int = 0

var camera_rig: Node = null
var player: Node = null
var player_path: NodePath
var spawn_point: Node = null

func _find_spawn_point():
	spawn_point = get_tree().root.find_node("SpawnPoint", true, false)
	print("ReplayPlayback spawn_point found: ", spawn_point)
	process_priority = -100  # Ensure replay logic runs before player physics
	set_physics_process(false)

func _debug_log(message: String) -> void:
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayPlayback] " + message)

func _apply_smooth_drift_correction(pilot: Spatial, target_transform: Transform, delta: float) -> void:
	# Cálculo frame-rate-independiente.
	var t = 1.0 - exp(-delta * DRIFT_CORRECTION_STRENGTH)
	
	# 1. Suavizar Posición (LERP)
	var new_origin = pilot.global_transform.origin.linear_interpolate(
		target_transform.origin, t
	)
	
	# 2. Suavizar Rotación (SLERP)
	var new_basis = pilot.global_transform.basis.slerp(target_transform.basis, t) 
	
	# 3. Aplicar
	pilot.global_transform.origin = new_origin
	pilot.global_transform.basis = new_basis

func _physics_process(_delta: float) -> void:
	if get_node("/root/GameGlobals") and get_node("/root/GameGlobals").is_test_mode:
		return
	frame_count += 1
	var player = PlayerManager.get_player()
	if player and is_instance_valid(player):
		print("[ReplayPlayback] Frame ", frame_count, " - Player pos: ", player.global_transform.origin)
	else:
		print("[ReplayPlayback] Frame ", frame_count, " - Player pos: null")
	var _player = PlayerManager.get_player()
	
	# Guard clause: Do nothing if there's no replay loaded or if it's paused.
	if not current_replay or playback_paused:
		return
	
	# Si llegamos al final del replay, detener playback usando el tamaño real de frame_states
	var max_frames = 0
	if current_replay and current_replay.frame_states:
		max_frames = current_replay.frame_states.size()
	else:
		max_frames = total_logical_frames
	if frame_index >= max_frames:
		stop_playback()
		return
	
	var frame_data = current_replay.frames[frame_index]
	
	# --- DRIFT CHECK & LOG DETALLADO ---
	_process_drift_check(_delta)
	
	# Solo forzar posición y rotación del mesh en los snapshots (cada RESYNC_INTERVAL)
	if current_replay and current_replay.frame_states.size() > frame_index and current_replay.frame_states[frame_index].has(PILOT_STATE_KEY):
		var player_state = current_replay.frame_states[frame_index][PILOT_STATE_KEY]
		if frame_index % RESYNC_INTERVAL == 0:
			if player_state.has("rotation") and _player and is_instance_valid(_player):
				var rot_euler = ReplayUtils.dict_to_vector3(player_state["rotation"])
				_player.rotation.y = rot_euler.y
			if player_state.has("pilot_pos") and _player and is_instance_valid(_player) and spawn_point:
				_player.global_transform.origin = spawn_point.to_global(ReplayUtils.dict_to_vector3(player_state["pilot_pos"]))
	
		# Fallback: Forzar rotación absoluta de la cámara si los valores grabados existen (esto sí, cada frame)
		var cam_rig_group = get_tree().get_nodes_in_group("camera_rig_group")
		if cam_rig_group.size() > 0:
			var camera_rig = cam_rig_group.front()
			if camera_rig:
				if player_state.has("camera_yaw"):
					if camera_rig.has("yaw"):
						camera_rig.yaw.rotation.y = player_state["camera_yaw"]
				if player_state.has("camera_pitch"):
					if camera_rig.has("pitch"):
						camera_rig.pitch.rotation.x = player_state["camera_pitch"]
	
	# Aplicar inputs y avanzar frame SOLO aquí (no en _process_drift_check)
	_apply_inputs_from_frame(frame_data)
	frame_index += 1
	emit_signal("frame_updated", frame_index, total_logical_frames)
	
func _process_drift_check(delta: float) -> void:
	# Skip drift correction in test mode to see pure error
	if GameGlobals and GameGlobals.is_test_mode:
		return
	# 🚨 Log de nivel superior para asegurar que la función se ejecuta
	if frame_index % 10 == 0:  # Reducir logs
		print("[DRIFT DEBUG] ¡Chequeo de deriva activado! Frame: ", frame_index)
	else:
		pass  # Siempre chequear

	if not current_replay or current_replay.frame_states.size() <= frame_index:
		return
	var recorded_states = current_replay.frame_states[frame_index]
	# Siempre chequear drift
	print("[DRIFT DEBUG] ¡Chequeo de deriva activado! Frame: ", frame_index)
	# Recorrer los nodos marcados para tracking
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		var _node_path = get_tree().current_scene.get_path_to(node)
		# 1. Chequeo del Pilot
		if node.name == PILOT_STATE_KEY and recorded_states.has(PILOT_STATE_KEY):
			var current_node = node
			var recorded_state = recorded_states[PILOT_STATE_KEY]
			# 1a. Obtener la verdad del mundo (Posición y Rotación)
			var current_pos = current_node.global_transform.origin
			var recorded_pos = Vector3.ZERO
			if recorded_state.has("pilot_pos") and spawn_point:
				recorded_pos = spawn_point.to_global(ReplayUtils.dict_to_vector3(recorded_state["pilot_pos"]))
			var current_rot = current_node.rotation
			var recorded_rot = Vector3.ZERO
			if recorded_state.has("rotation"):
				recorded_rot = ReplayUtils.dict_to_vector3(recorded_state["rotation"])
			var distance = current_pos.distance_to(recorded_pos)
			var angular_drift = abs(fmod(current_rot.y - recorded_rot.y, PI * 2.0))
			# 💥 LOG CRÍTICO QUE DEBE APARECER Y MOSTRAR EL DRIFT REAL 💥
			print(
				"[DRIFT CHECK][PILOT] Frame:", frame_index,
				" | **Distancia:** ", distance,
				" | **Grabado POS:** ", recorded_pos,
				" | **Actual POS:** ", current_pos,
				" | Drift Vec: ", recorded_pos - current_pos,
				" | Drift Magnitude: ", (recorded_pos - current_pos).length(),
				" | Angular: ", angular_drift
			)
			# 1b. Corrección Posicional y Angular
			if distance > DRIFT_SNAP_THRESHOLD:
				# Hard snap solo si la deriva es extrema
				var t = current_node.global_transform
				t.origin = recorded_pos
				t.basis = Basis(recorded_rot)
				current_node.global_transform = t
				if recorded_state.has("velocity"):
					current_node.velocity = ReplayUtils.dict_to_vector3(recorded_state["velocity"])
				if recorded_state.has("linear_velocity"):
					current_node.linear_velocity = ReplayUtils.dict_to_vector3(recorded_state["linear_velocity"])
				if recorded_state.has("horizontal_velocity"):
					current_node.horizontal_velocity = ReplayUtils.dict_to_vector3(recorded_state["horizontal_velocity"])
				print("[DRIFT CORRECTION] HARD SNAP Posición, Rotación y Velocidades Forzadas. Dist: ", distance, " Ang: ", angular_drift)
				# Corregir el rig de la cámara para que los inputs futuros sean correctos
				var cam_rig_group = get_tree().get_nodes_in_group("camera_rig_group")
				if cam_rig_group.size() > 0:
					var cam_rig = cam_rig_group.front()
					if cam_rig and cam_rig.has_method("set_replay_state"):
						var cam_state = {"yaw": recorded_rot.y}
						if recorded_state.has("camera_pitch"):
							cam_state["pitch"] = recorded_state["camera_pitch"]
						cam_rig.set_replay_state(cam_state)
			elif distance > DRIFT_THRESHOLD or angular_drift > ROTATION_DRIFT_THRESHOLD:
				# Corrección suave: inyectar velocidad y rotación
				if recorded_state.has("velocity"):
					current_node.velocity = ReplayUtils.dict_to_vector3(recorded_state["velocity"])
				# Rotación: interpolar hacia la rotación grabada
				var t = current_node.global_transform
				t.basis = t.basis.slerp(Basis(recorded_rot), delta * DRIFT_CORRECTION_STRENGTH)
				current_node.global_transform.basis = t.basis
				print("[DRIFT CORRECTION] SOFT: Inyección de velocidad y rotación suave. Dist: ", distance, " Ang: ", angular_drift)
	# Aquí puedes añadir la lógica de chequeo para otros nodos en REPLAY_GROUP
	# ...aquí puedes añadir la lógica para otros nodos del grupo REPLAY_GROUP si lo necesitas...


func start_playback(replay_path: String, is_headless: bool = false) -> void:
	var replay = ReplayScript.new()
	if replay.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		emit_signal("playback_failed")
		return

	current_replay_filename = replay_path.get_file()
	print("Loading replay scene: ", replay.scene_path)
	
	current_replay = replay
	playback_start_time = Time.get_ticks_usec()
	headless = is_headless
	frame_index = 0
	total_logical_frames = len(current_replay.frames)
	time_accumulator = 0.0
	
	# Load frames into InputState
	InputState.recorded_frames = current_replay.frames.duplicate()
	InputState.mode = InputState.Mode.PLAYBACK
	InputState.paused = true  # Start paused
	InputState.replay_frame = 0
	
	# Deterministic setup for regression testing
	Engine.set_physics_jitter_fix(0.0)
	seed(12345)
	
	# Wait for one frame to ensure the entire scene tree is ready.
	# This prevents "node not found" errors when accessing nodes immediately after a scene load.
	if get_tree():
		yield(get_tree(), "idle_frame")
	
	# Validate that player exists and has required nodes before proceeding
	var player_check = PlayerManager.get_player()
	if not is_instance_valid(player_check) or not player_check.has_node("PlayerInput"):
		print("[ReplayPlayback] ERROR: Player not found or missing PlayerInput. Aborting playback.")
		emit_signal("playback_failed")
		return
	
	call_deferred("_find_spawn_point")
	
	# Update references after scene change
	if get_tree() and get_tree().current_scene:
		var _camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		player = PlayerManager.get_player()
		if is_instance_valid(player) and player.is_inside_tree():
			player_path = get_tree().current_scene.get_path_to(player)
	
	_prepare_scene_for_playback()
	
	# The playback is loaded, but paused, waiting for the user to press play.
	pause_playback() 
	
	emit_signal("playback_started", total_logical_frames)
	
	# Go to first frame
	seek(0)

func _prepare_scene_for_playback():
	_set_tracked_nodes_physics_process(false)

	# Stop music
	if get_tree() and get_tree().root.has_node("AudioSystem"):
		get_tree().root.get_node("AudioSystem").stop_bgm()
		
	if get_tree() and get_tree().current_scene:
		# Validate that player exists and has required nodes
		var player_check = PlayerManager.get_player()
		if not is_instance_valid(player_check) or not player_check.has_node("PlayerInput"):
			print("[ReplayPlayback] ERROR: Player not found or missing PlayerInput. Aborting playback preparation.")
			emit_signal("playback_failed")
			return
		
		var _pilot = get_tree().current_scene.get_node("Pilot/PlayerInput")
		var _scene = get_tree().current_scene
		for path in current_replay.initial_states:
			var node_name = path.trim_prefix("@")
			var node = get_tree().current_scene.find_node(node_name, true, false)
			print (node, path)
			if node:
				_set_node_state(node, current_replay.initial_states[path])
		print("Done **************************************************")				
		print("Done")

func start_loaded_playback() -> void:
	print("[ReplayPlayback] >>>>> start_loaded_playback called")
	frame_count = 0

	# Disable camera input
	if get_tree() and get_tree().current_scene:
		var _camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		var _player = PlayerManager.get_player()
		if is_instance_valid(_player):
			_player.set_physics_process(true)  # Enable player physics for deterministic simulation
			print("[ReplayPlayback] Player physics enabled in resume_playback")
			set_physics_process(true)
			print("[ReplayPlayback] Node in replay_track physics enabled? ", is_physics_processing())

	playback_status = "Playing"
	playback_start_time = Time.get_ticks_usec()  # Reset start time when playback actually begins
	if GameGlobals:
		GameGlobals.replay_debug_mode = true
		GameGlobals.is_replaying = true
	resume_playback()

func stop_playback() -> void:
	print("Stopping playback.")
	playback_paused = true
	playback_status = "Stopped"
	frame_index = 0

	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)

	if GameGlobals:
		GameGlobals.is_replaying = false

	# Release mouse/camera control to user, but keep player frozen
	InputState.mode = InputState.Mode.LIVE
	InputState.paused = false

	for action in INPUT_ACTIONS:
		Input.action_release(action)

	var _player = PlayerManager.get_player()
	if is_instance_valid(_player):
		# Freeze player by disabling physics
		_player.set_physics_process(false)
		# Stop animations
		if _player.animation_tree:
			_player.animation_tree.active = false

	# Release camera control to user
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_method("set_process_input"):
				camera_rig.set_process_input(true)
			if camera_rig.has_method("set_physics_process"):
				camera_rig.set_physics_process(true)

	# Reset player input mode
	if _player and is_instance_valid(_player) and _player.has_node("PlayerInput"):
		var player_input = _player.get_node("PlayerInput")
		player_input.is_replay_mode = false

	if get_tree() and get_tree().root.has_node("AudioSystem"):
		get_tree().root.get_node("AudioSystem").stop_bgm()

	emit_signal("playback_stopped")

func pause_playback() -> void:
	if playback_paused:
		return
	playback_paused = true
	playback_status = "Paused"
	
	# Use a check to prevent error if trying to remove from a group it's not in.
	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)
	InputState.paused = true
	emit_signal("playback_paused")
	set_physics_process(false)

func resume_playback() -> void:
	print("[ReplayPlayback] >>>>> resume_playback called")
	if not playback_paused:
		return
	if not is_in_group("playback_active"): # Add to group when playback actually resumes
		add_to_group("playback_active")

	playback_paused = false
	playback_status = "Playing"
	set_physics_process(true)
	InputState.paused = false
	
	# Asegurar física del player activada para playback
	var _player = PlayerManager.get_player()
	if is_instance_valid(_player):
		_player.set_physics_process(true)  # Enable player physics for deterministic simulation
		print("[ReplayPlayback] Player physics enabled in resume_playback")
		
		# Sincronizar estado al resumir para asegurar consistencia
		var frame_state_to_apply = null
		if current_replay.initial_states.has(PILOT_STATE_KEY):
			frame_state_to_apply = current_replay.initial_states[PILOT_STATE_KEY]
		elif current_replay.frame_states and current_replay.frame_states.size() > 0 and current_replay.frame_states[0].has(PILOT_STATE_KEY):
			frame_state_to_apply = current_replay.frame_states[0][PILOT_STATE_KEY]

		if frame_state_to_apply:
			# 1. Posición y rotación exactas
			if frame_state_to_apply.has("pilot_pos"):
				var rel_pos = ReplayUtils.dict_to_vector3(frame_state_to_apply["pilot_pos"])
				_player.global_transform.origin = spawn_point.to_global(rel_pos) if spawn_point else rel_pos
			
			if frame_state_to_apply.has("rotation"):
				var rot_euler = ReplayUtils.dict_to_vector3(frame_state_to_apply["rotation"])
				_player.global_transform.basis = Basis(rot_euler)
			
			# 2. Velocidad
			if frame_state_to_apply.has("velocity"):
				_player.velocity = ReplayUtils.dict_to_vector3(frame_state_to_apply["velocity"])
			if frame_state_to_apply.has("linear_velocity"):
				_player.linear_velocity = ReplayUtils.dict_to_vector3(frame_state_to_apply["linear_velocity"])
			if frame_state_to_apply.has("horizontal_velocity"):
				_player.horizontal_velocity = ReplayUtils.dict_to_vector3(frame_state_to_apply["horizontal_velocity"])
			
			# 3. Estados internos críticos
			if frame_state_to_apply.has("on_floor"):
				_player.set("on_floor", frame_state_to_apply["on_floor"])
			if frame_state_to_apply.has("was_on_floor"):
				_player.set("was_on_floor", frame_state_to_apply["was_on_floor"])
			if frame_state_to_apply.has("coyote_timer"):
				_player.set("coyote_timer", frame_state_to_apply["coyote_timer"])
			if frame_state_to_apply.has("jump_buffer_timer"):
				_player.set("jump_buffer_timer", frame_state_to_apply["jump_buffer_timer"])

			print("[ReplayPlayback] STATE SYNC ON RESUME (from frame_states[%d]) | Pos: %s | Rot: %s" % [frame_index, _player.global_transform.origin, _player.rotation])
		
		elif current_replay.initial_states.has(PILOT_STATE_KEY): # Fallback
			var initial_data = current_replay.initial_states[PILOT_STATE_KEY]
			if initial_data.has("global_transform"):
				_player.global_transform = ReplayUtils.from_json_safe(initial_data["global_transform"])
			if initial_data.has("velocity"):
				_player.velocity = ReplayUtils.from_json_safe(initial_data["velocity"])
			print("[ReplayPlayback] STATE SYNC ON RESUME (from initial_states): %s" % _player.global_transform.origin)
	
	emit_signal("playback_resumed")

func rewind_playback() -> void:
	seek(0)

func seek(frame_idx: int) -> void:
	if not current_replay or frame_idx < 0 or frame_idx >= total_logical_frames:
		return
		
	frame_index = frame_idx
	
	time_accumulator = 0.0
	# In a pure input-based system, we can't instantly jump to an arbitrary frame's state.
	# We can only restore the initial state when seeking to the beginning.
	if frame_index == 0:
		if get_tree() and get_tree().current_scene:
			for path in current_replay.initial_states:
				var node_name = path.trim_prefix("@")
				var node = get_tree().current_scene.find_node(node_name, true, false)
				if node:
					_set_node_state(node, current_replay.initial_states[path])

	emit_signal("frame_updated", frame_index, total_logical_frames)

func step_frame() -> void:
	if frame_index < total_logical_frames - 1:
		seek(frame_index + 1)

func step_back_frame() -> void:
	if frame_index > 0:
		seek(frame_index - 1)

func _apply_inputs_from_frame(frame_data: Dictionary) -> void:
	# --- INYECCIÓN DE ESTADO DE STRAFING ---
	var strafe_val = frame_data.get("strafing_active", false)
	InputState.is_strafing_mode_active = strafe_val
	if frame_data.has("strafing_timer"):
		InputState.strafing_timer = frame_data.get("strafing_timer", 0.0)

	# --- INYECCIÓN DE MOUSE ---
	if frame_data.has("mouse_delta"):
		var md = frame_data["mouse_delta"]
		var mouse_delta_vec = Vector2.ZERO
		if md is Dictionary:
			mouse_delta_vec = Vector2(md.get("x", 0), md.get("y", 0))
		else:
			mouse_delta_vec = Vector2.ZERO

		InputState.mouse_delta = mouse_delta_vec
		print("[REPLAY][ReplayPlayback] Inyectando mouse_delta.x=", mouse_delta_vec.x, " mouse_delta.y=", mouse_delta_vec.y)

		# Enviar el input del mouse directamente al camera rig
		if mouse_delta_vec.length_squared() > 0:
			var cam_rig_group = get_tree().get_nodes_in_group("camera_rig_group")
			print("[REPLAY DEBUG] Found ", cam_rig_group.size(), " nodes in camera_rig_group")

			if cam_rig_group.size() > 0:
				var camera_rig = cam_rig_group.front()
				print("[REPLAY DEBUG] Camera rig node: ", camera_rig.name, " path: ", camera_rig.get_path())
				
				# No setear strafe en camera_rig directamente, ya se maneja via InputState
				# camera_rig.set("is_strafing_mode_active", strafe_val)
				# var actual_strafe_state = camera_rig.get("is_strafing_mode_active")
				# print("[REPLAY DEBUG] Setting camera_rig.is_strafing_mode_active to ", strafe_val, ". Actual value is now: ", actual_strafe_state)

				if camera_rig.has_method("process_camera_rotation"):
					print("[REPLAY DEBUG] Camera rig HAS process_camera_rotation. Calling it now.")
					camera_rig.process_camera_rotation(mouse_delta_vec)
				else:
					print("[REPLAY DEBUG] ERROR: Camera rig does NOT have process_camera_rotation method.")
			else:
				print("[REPLAY DEBUG] ERROR: camera_rig_group is empty.")
	else:
		InputState.mouse_delta = Vector2.ZERO
		print("[REPLAY][ReplayPlayback] Inyectando mouse_delta.x=0 mouse_delta.y=0 (no grabado)")

	# --- INYECCIÓN DE BOTONES ---
	_debug_log("Applying inputs: " + str(frame_data["inputs"]))
	_debug_log("Sprint pressed: " + str(frame_data["inputs"].get("sprint", false)))
	
	var _player = PlayerManager.get_player()
	if _player and is_instance_valid(_player) and _player.has_node("PlayerInput"):
		var player_input = _player.get_node("PlayerInput")
		player_input.inject_input(frame_data["inputs"])
	else:
		# Fallback to old method if not available
		for action in frame_data["inputs"]:
			if action == "mouse_motion":
				continue
			var value = frame_data["inputs"][action]
			if value is bool:
				if value:
					Input.action_press(action)
				else:
					Input.action_release(action)

	# --- APLICAR ESTADOS DE FÍSICA NO INPUTABLES ---
	if _player and is_instance_valid(_player) and _player.external_velocity and frame_data.has("player_external_velocity"):
		_player.external_velocity.velocity = ReplayUtils.dict_to_vector3(frame_data["player_external_velocity"])

	if _player and is_instance_valid(_player) and frame_data.has("player_gravity_override"):
		_player.set("gravity_override", ReplayUtils.dict_to_vector3(frame_data["player_gravity_override"]))

	# --- INYECCIÓN CRÍTICA DE LA VELOCIDAD DE FÍSICA SOLO SI HUBO CORRECCIÓN DE DERIVA ---
	# Solo inyectar la velocidad si el drift posicional o angular supera el umbral
	if _player and is_instance_valid(_player) and current_replay.frame_states.size() > frame_index:
		var recorded_state = current_replay.frame_states[frame_index]
		var player_data = recorded_state.get(PILOT_STATE_KEY)
		var _apply_velocity_correction := false
		if player_data and player_data.has("pilot_pos") and player_data.has("rotation") and spawn_point:
			var current_pos = _player.global_transform.origin
			var recorded_pos = spawn_point.to_global(ReplayUtils.dict_to_vector3(player_data["pilot_pos"]))
			var current_rot = _player.rotation
			var recorded_rot = ReplayUtils.dict_to_vector3(player_data["rotation"])
			var distance = current_pos.distance_to(recorded_pos)
			var angular_drift = abs(fmod(current_rot.y - recorded_rot.y, PI * 2.0))
			if distance > DRIFT_THRESHOLD or angular_drift > ROTATION_DRIFT_THRESHOLD:
				_apply_velocity_correction = true
	# --- VELOCIDAD NO SE INYECTA PARA EVITAR DRIFT ---
	# Eliminado: Inyección de velocidad grabada para permitir que la simulación física determine la velocidad basada en inputs.
	# Esto previene el drift causado por valores flotantes inconsistentes.
	# if _apply_velocity_correction and player_data and player_data.has("pre_move_velocity"):
	#	var recorded_velocity = ReplayUtils.from_json_safe(player_data["pre_move_velocity"])
	#	player.velocity = recorded_velocity
	#	player.pre_move_velocity_for_replay = recorded_velocity # Para consistencia en logs
	#	player.horizontal_velocity = recorded_velocity - Vector3(0, recorded_velocity.y, 0)
	#	if player.movement_comp:
	#		player.movement_comp.horizontal_velocity = player.horizontal_velocity
	#	_debug_log("VELOCITY INJECTED: %s" % str(recorded_velocity))


func _sync_pilot_to_frame(frame_data_state: Dictionary) -> void:
	"""Force the player's position and rotation to match the recorded state exactly."""
	if not player:
		return
	
	# Set transform directly from recorded state
	# if frame_data_state.has("global_transform"):
	#	var transform_dict = frame_data_state["global_transform"]
	#	player.global_transform = ReplayUtils.dict_to_transform(transform_dict)
	
	# Set velocity directly
	if frame_data_state.has("velocity"):
		var vel_dict = frame_data_state["velocity"]
		player.velocity = ReplayUtils.dict_to_vector3(vel_dict)
	
	# Set other critical state
	if frame_data_state.has("on_floor"):
		player.was_on_floor = frame_data_state["on_floor"]
	
	# Additional state restoration if needed
	if frame_data_state.has("platform_velocity_fixed"):
		var pv_dict = frame_data_state["platform_velocity_fixed"]
		player.platform_velocity_fixed = ReplayUtils.dict_to_vector3(pv_dict)
	
	if frame_data_state.has("airborne_inherited"):
		var ai_dict = frame_data_state["airborne_inherited"]
		player.airborne_inherited = ReplayUtils.dict_to_vector3(ai_dict)

func _set_tracked_nodes_physics_process(enabled: bool) -> void:
	"""Helper function to enable or disable physics for all tracked nodes."""
	var player = PlayerManager.get_player()
	if player and is_instance_valid(player):
		player.set_physics_process(enabled)
		print("[ReplayPlayback] _set_tracked_nodes_physics_process: Player physics enabled? ", enabled, player.is_physics_processing())
	if get_tree():
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			if node and is_instance_valid(node):
				node.set_physics_process(enabled)
				print("[ReplayPlayback] _set_tracked_nodes_physics_process: Node ", node, " physics enabled? ", enabled, node.is_physics_processing())

func _set_node_state(node: Node, state: Dictionary) -> void:
	if node.has_method("set_replay_state"):
		node.set_replay_state(state)
		return
	state = ReplayUtils.from_json_safe(state) # Convert the entire state dictionary from JSON-safe types to Godot types
	for key in state:
		if key == "global_transform" and node is Spatial:
			var transform_val = state[key]
			if transform_val is String:
				# Attempt to parse as a standard Godot Transform string (e.g., Transform(1,0,0,...))
				var parsed_val = str2var(transform_val)
				if parsed_val is Transform:
					node.global_transform = parsed_val # Legacy support for old string formats
			elif transform_val is Transform:
				node.global_transform = transform_val
			elif transform_val is Dictionary:
				node.global_transform = ReplayUtils.dict_to_transform(transform_val)
		elif key == "linear_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.linear_velocity = state[key]
			elif state[key] is Dictionary:
				node.linear_velocity = ReplayUtils.dict_to_vector3(state[key])
		elif key == "angular_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.angular_velocity = state[key]
			elif state[key] is Dictionary:
				node.angular_velocity = ReplayUtils.dict_to_vector3(state[key])
