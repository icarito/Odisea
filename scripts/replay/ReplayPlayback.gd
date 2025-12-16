extends Node

signal playback_started(total_frames)
signal playback_stopped
signal playback_failed
signal playback_paused
signal playback_resumed
signal frame_updated(frame_index, total_frames)

const ReplayScript = preload("res://scripts/replay/Replay.gd")
const REPLAY_GROUP = "replay_track"
const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]
const DRIFT_THRESHOLD = 0.005 # Maximum allowed position difference before correction
const MAX_CORRECTION_DISTANCE = 0.5 # Max distance to correct per frame, use snapping above this
const RESYNC_INTERVAL = 20 # Frames between drift checks and corrections
const DRIFT_CORRECTION_STRENGTH = 10.0 # Suavidad de la corrección. 10 es firme, 5 es suave.
const MIN_DIVERGENCE_TO_CORRECT = 0.01 # Threshold to avoid insignificant corrections
const FIXED_DELTA = 0.016667 # Fixed delta for 60 FPS simulation
const IGNORE_THRESHOLD = 0.001 # Ignore micro-drift to eliminate floating
const FAST_LERP_THRESHOLD = 0.05 # Use ultra-fast LERP if between this and SNAP
const SNAP_THRESHOLD = 0.005 # Instant correction threshold (5mm)
const LERP_STRENGTH_ULTRA_FAST = 200.0 # Ultra-fast LERP strength
const PILOT_STATE_KEY = "@Pilot@10" # Key for pilot state in frame_states and initial_states

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

const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")

func _ready() -> void:
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

func _physics_process(delta: float) -> void:
	frame_count += 1
	# Guard clause: Do nothing if there's no replay loaded or if it's paused.
	if not current_replay or playback_paused:
		return

	# If we have reached the end of the replay, stop playback.
	if frame_index >= total_logical_frames:
		stop_playback()
		return

	var frame_data = current_replay.frames[frame_index]
	
	# Force player state to recorded state for this frame
	if current_replay.frame_states.size() > frame_index:
		var recorded_state = current_replay.frame_states[frame_index]
		if recorded_state.has(PILOT_STATE_KEY):
			var pilot_state = recorded_state[PILOT_STATE_KEY]
			var pilot = PlayerManager.get_player()
			if pilot and pilot_state.has("global_transform"):
				var target_transform = ReplayUtils.dict_to_transform(pilot_state["global_transform"])
				_apply_smooth_drift_correction(pilot, target_transform, delta)

	
	# Apply inputs (for camera and other non-physics systems)
	_apply_inputs_from_frame(frame_data)

	frame_index += 1
	emit_signal("frame_updated", frame_index, total_logical_frames)

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
	
	# Update references after scene change
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		player = PlayerManager.get_player()
		if player:
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
		var pilot = get_tree().current_scene.get_node("Pilot/PlayerInput")
		var scene = get_tree().current_scene
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
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_method("set_process_input"):
				camera_rig.set_process_input(false)

	# Disable player input to prevent user interference during playback
	var player = PlayerManager.get_player()
	if player:
		player.set_process_input(false)
		player.set_physics_process(true)  # Enable for deterministic simulation
		if get_tree() and get_tree().current_scene:
			player_path = get_tree().current_scene.get_path_to(player)
			# Find the correct player_path key from initial_states to match frame_states
			for path in current_replay.initial_states:
				var node_name = path.trim_prefix("@")
				var node = get_tree().current_scene.find_node(node_name, true, false)
				if node == player:
					player_path = path
					break
		if player.has_node("PlayerInput"):
			var player_input = player.get_node("PlayerInput")
			player_input.is_replay_mode = true

	# Asegurar física en todos los nodos del grupo replay_track
	if get_tree():
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			node.set_physics_process(true)
			print("[ReplayPlayback] Node in replay_track physics enabled? ", node, node.is_physics_processing())

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

	var player = PlayerManager.get_player()
	if player:
		# Freeze player by disabling physics
		player.set_physics_process(false)
		# Stop animations
		if player.animation_tree:
			player.animation_tree.active = false

	# Release camera control to user
	if get_tree() and get_tree().current_scene:
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_method("set_process_input"):
				camera_rig.set_process_input(true)
			if camera_rig.has_method("set_physics_process"):
				camera_rig.set_physics_process(true)

	# Reset player input mode
	if player and player.has_node("PlayerInput"):
		var player_input = player.get_node("PlayerInput")
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
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(true)  # Enable player physics for deterministic simulation
		print("[ReplayPlayback] Player physics enabled in resume_playback")
		
		# Configurar estado inicial una sola vez
		if current_replay.initial_states.has(PILOT_STATE_KEY):
			var initial_data = current_replay.initial_states[PILOT_STATE_KEY]
			
			# 1. RESTAURAR TRANSFORMACIÓN COMPLETA (CRÍTICO) - USE FIXED-POINT FOR DETERMINISM
			if initial_data.has("player_position_fixed"):
				var pos_fixed = initial_data["player_position_fixed"]
				player.global_transform.origin = ReplayUtils.fixed_dict_to_vector3(pos_fixed)
			elif initial_data.has("global_transform"):
				var initial_transform = ReplayUtils.from_json_safe(initial_data["global_transform"])
				player.global_transform = initial_transform
			
			# 2. RESTAURAR BASIS FROM FIXED-POINT
			if initial_data.has("basis_fixed"):
				var basis_fixed = initial_data["basis_fixed"]
				player.global_transform.basis = ReplayUtils.fixed_dict_to_basis(basis_fixed)
			
			# 3. RESTAURAR VELOCIDAD FROM FIXED-POINT
			if initial_data.has("velocity_fixed"):
				var vel_fixed = initial_data["velocity_fixed"]
				player.velocity = ReplayUtils.fixed_dict_to_vector3(vel_fixed)
			elif initial_data.has("velocity"):
				player.velocity = ReplayUtils.from_json_safe(initial_data["velocity"])
			
			# --- AGREGAR ESTA LÍNEA DE DEBUG ---
			print("[ReplayPlayback] INITIAL POS APPLIED: %s" % player.global_transform.origin)
	
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
	if frame_data.has("strafing_active"):
		InputState.is_strafing_mode_active = frame_data.get("strafing_active", false)
	if frame_data.has("strafing_timer"):
		InputState.strafing_timer = frame_data.get("strafing_timer", 0.0)

	# --- CORRECCIÓN FALTANTE: INYECCIÓN DE MOUSE DELTA ---
	if frame_data.has("mouse_delta"):
		var md = frame_data["mouse_delta"]
		# Es vital convertir el Diccionario {x, y} a Vector2
		InputState.mouse_delta = Vector2(md.get("x", 0), md.get("y", 0))
	else:
		InputState.mouse_delta = Vector2.ZERO

	_debug_log("Applying inputs: " + str(frame_data["inputs"]))
	_debug_log("Sprint pressed: " + str(frame_data["inputs"].get("sprint", false)))
	
	var player = PlayerManager.get_player()
	if player and player.has_node("PlayerInput"):
		var player_input = player.get_node("PlayerInput")
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

	if frame_data["inputs"].has("mouse_motion"):
		var mouse_motion = frame_data["inputs"]["mouse_motion"]
		if mouse_motion is Vector2 and mouse_motion.length_squared() > 0:
			if get_tree() and get_tree().current_scene:
				var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
				if camera_rig and camera_rig.has_method("process_camera_rotation"):
					camera_rig.process_camera_rotation(mouse_motion)
	elif frame_data.has("mouse_delta"):
		var md_dict = frame_data["mouse_delta"]
		if md_dict is Dictionary:
			var mouse_motion = Vector2(md_dict.get("x", 0.0), md_dict.get("y", 0.0))
			if mouse_motion.length_squared() > 0:
				if get_tree() and get_tree().current_scene:
					var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
					if camera_rig and camera_rig.has_method("process_camera_rotation"):
						camera_rig.process_camera_rotation(mouse_motion)

	# --- APLICAR ESTADOS DE FÍSICA NO INPUTABLES ---
	if player and player.external_velocity and frame_data.has("player_external_velocity"):
		player.external_velocity.velocity = ReplayUtils.dict_to_vector3(frame_data["player_external_velocity"])

	if player and frame_data.has("player_gravity_override"):
		player.set("gravity_override", ReplayUtils.dict_to_vector3(frame_data["player_gravity_override"]))

	# --- INYECCIÓN CRÍTICA DE LA VELOCIDAD DE FÍSICA ---
	# Esto sincroniza el estado de la física antes de que se ejecute _physics_process,
	# eliminando la acumulación de errores de punto flotante.
	if player and current_replay.frame_states.size() > frame_index:
		var recorded_state = current_replay.frame_states[frame_index]
		var player_data = recorded_state.get(PILOT_STATE_KEY)
		
		if player_data and player_data.has("pre_move_velocity"):
			var recorded_velocity = ReplayUtils.from_json_safe(player_data["pre_move_velocity"])
			
			# Inyectar la velocidad y sus componentes descompuestos en el controlador.
			# Esto es crucial porque _physics_process usa 'horizontal_velocity' y 'vertical_velocity'
			# para calcular el movimiento final.
			player.velocity = recorded_velocity
			player.pre_move_velocity_for_replay = recorded_velocity # Para consistencia en logs
			player.horizontal_velocity = recorded_velocity - Vector3(0, recorded_velocity.y, 0)
			# player.vertical_velocity.y = recorded_velocity.y  # Commented out due to access error
			
			# Adicionalmente, actualizar el componente de movimiento si existe.
			if player.movement_comp:
				player.movement_comp.horizontal_velocity = player.horizontal_velocity
			
			_debug_log("VELOCITY INJECTED: %s" % str(recorded_velocity))


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
	if player:
		player.set_physics_process(enabled)
		print("[ReplayPlayback] _set_tracked_nodes_physics_process: Player physics enabled? ", enabled, player.is_physics_processing())
	if get_tree():
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
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
