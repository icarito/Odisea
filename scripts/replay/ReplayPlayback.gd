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
const DRIFT_THRESHOLD = 0.001 # Maximum allowed position difference for replay verification

var current_replay: Resource = null
var current_replay_filename: String = ""
var frame_index: int = 0
var total_logical_frames: int = 0
var playback_paused: bool = false
var playback_status: String = "Stopped"  # "Playing", "Paused", "Stopped"

var time_accumulator: float = 0.0
var headless: bool = false
var playback_start_time: int = 0

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

func _physics_process(delta: float) -> void:
	# Guard clause: Do nothing if there's no replay loaded or if it's paused.
	if not current_replay or playback_paused:
		return

	# CHEQUEO DE DERIVA (DRIFT) para el frame ANTERIOR
	# Se ejecuta ANTES de aplicar los nuevos inputs.
	# De esta forma, el estado actual del player es el resultado de la simulación del frame anterior.
	if frame_index > 0:
		var last_frame_index = frame_index - 1
		var player = PlayerManager.get_player()
		if player and current_replay.frame_states.size() > last_frame_index:
			var recorded_state = current_replay.frame_states[last_frame_index]
			var player_data = recorded_state.get(str(player_path))
			if player_data:
				var recorded_pos_dict = player_data.get("player_position")
				if recorded_pos_dict:
					var recorded_position = ReplayUtils.dict_to_vector3(recorded_pos_dict)
					var simulated_pos = player.global_transform.origin
					var divergence = recorded_position.distance_to(simulated_pos)
					if divergence > DRIFT_THRESHOLD:
						print("--- REGRESSION TEST FAILED: DRIFT DETECTED ---")
						print("Frame: %d" % last_frame_index)
						print("Divergence: %s" % divergence)
						print("Expected Position: %s" % recorded_position)
						print("Actual Position: %s" % simulated_pos)
						push_error("Physics drift exceeded tolerance.")
					else:
						# This log is very noisy, let's keep it for real debug sessions
						# print("--- Frame %d Locked. Divergence: %s ---" % [last_frame_index, divergence])
						pass


	# If we have reached the end of the replay, stop playback.
	if frame_index >= total_logical_frames:
		stop_playback()
		return

	var frame_data = current_replay.frames[frame_index]
	var recorded_delta = frame_data.get("delta", 1.0 / 60.0) # Obtener el delta grabado
	
	_debug_log("ReplayPlayback _physics_process: Simulating frame " + str(frame_index))

	# Aplicar Inputs
	_apply_inputs_from_frame(frame_data)

	# El estado de la cámara se aplica en _apply_inputs_from_frame, no es necesario duplicarlo.
	# NOTA: Esto era una fuente potencial de no-determinismo si se restauraba estado de cámara
	# que afectara la lógica del player. Ahora se centraliza en apply_inputs.

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
	
	# Deterministic setup for regression testing
	Engine.set_physics_jitter_fix(0.0)
	seed(12345)
	
	# Wait for one frame to ensure the entire scene tree is ready.
	# This prevents "node not found" errors when accessing nodes immediately after a scene load.
	yield(get_tree(), "idle_frame")
	
	# Update references after scene change
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
	if get_node("/root/AudioSystem"):
		get_node("/root/AudioSystem").stop_bgm()
		
	for path in current_replay.initial_states:
		var node = get_tree().current_scene.get_node(path)
		if node:
			_set_node_state(node, current_replay.initial_states[path])

func start_loaded_playback() -> void:
	print("[ReplayPlayback] >>>>> start_loaded_playback called")

	# Disable camera input
	var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
	if camera_rig:
		if camera_rig.has_method("set_process_input"):
			camera_rig.set_process_input(false)

	# Disable player input to prevent user interference during playback
	var player = PlayerManager.get_player()
	if player:
		player.set_process_input(false)
		player.set_physics_process(true)  # Enable for deterministic simulation
		player_path = get_tree().current_scene.get_path_to(player)

	# Asegurar física en todos los nodos del grupo replay_track
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
	
	# Use a check to prevent error if trying to remove from a group it's not in.
	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)

	if GameGlobals:
		GameGlobals.is_replaying = false

	for action in INPUT_ACTIONS:
		Input.action_release(action)

	# Re-enable physics and input for camera only, keep player frozen
	_set_tracked_nodes_physics_process(true)
	var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
	if camera_rig:
		if camera_rig.has_method("set_process_input"):
			camera_rig.set_process_input(true)

	# Do not re-enable player input to keep it frozen at last frame
	# var player = PlayerManager.get_player()
	# if player:
	#     player.set_process_input(true)

	if get_node("/root/AudioSystem"):
		get_node("/root/AudioSystem").stop_bgm() # consider if we want to resume music

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
	
	# Asegurar física del player activada para playback
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(true)  # Enable player physics for deterministic simulation
		print("[ReplayPlayback] Player physics enabled in resume_playback")
		
		# Configurar estado inicial una sola vez
		if current_replay.initial_states.has(str(player_path)):
			var initial_data = current_replay.initial_states[str(player_path)]
			
			# 1. RESTAURAR TRANSFORMACIÓN COMPLETA (CRÍTICO)
			if initial_data.has("global_transform"):
				var initial_transform = ReplayUtils.from_json_safe(initial_data["global_transform"])
				player.global_transform = initial_transform
				# --- AGREGAR ESTA LÍNEA DE DEBUG ---
				print("[ReplayPlayback] INITIAL POS APPLIED: %s" % player.global_transform.origin)
				
			# 2. RESTAURAR VELOCIDAD
			if initial_data.has("velocity"):
				player.velocity = ReplayUtils.from_json_safe(initial_data["velocity"])
	
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
		for path in current_replay.initial_states:
			var node = get_tree().current_scene.get_node(path)
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
	_debug_log("Applying inputs: " + str(frame_data["inputs"]))
	_debug_log("Sprint pressed: " + str(frame_data["inputs"].get("sprint", false)))
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
			var player = PlayerManager.get_player()
			#if player and player.has_node("PlayerInput"):
				# Directamente provee el mouse motion al componente que lo maneja.
				# player.get_node("PlayerInput").mouse_motion += mouse_motion # COMENTAR ESTO

	# --- APLICAR ESTADOS DE FÍSICA NO INPUTABLES ---
	var player = PlayerManager.get_player()
	if player and player.external_velocity and frame_data.has("player_external_velocity"):
		player.external_velocity.velocity = ReplayUtils.dict_to_vector3(frame_data["player_external_velocity"])

	if player and frame_data.has("player_gravity_override"):
		player.set("gravity_override", ReplayUtils.dict_to_vector3(frame_data["player_gravity_override"]))

	# Aplicar estado de la cámara
	if frame_data.has("camera"):
		var cam_data = frame_data["camera"]
		var camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig:
			if camera_rig.has_node("Yaw"):
				camera_rig.get_node("Yaw").rotation.y = cam_data["yaw"]
			if camera_rig.has_node("Pitch"):
				camera_rig.get_node("Pitch").rotation.x = cam_data["pitch"]
			if camera_rig.has_node("SpringArm"):
				var springarm = camera_rig.get_node("SpringArm")
				if springarm.has_method("set_spring_length"):
					springarm.set_spring_length(cam_data["spring_length"])
	
	# --- INYECCIÓN CRÍTICA DE LA VELOCIDAD DE FÍSICA ---
	# Esto sincroniza el estado de la física antes de que se ejecute _physics_process,
	# eliminando la acumulación de errores de punto flotante.
	if player and current_replay.frame_states.size() > frame_index:
		var recorded_state = current_replay.frame_states[frame_index]
		var player_data = recorded_state.get(str(player_path))
		
		if player_data and player_data.has("pre_move_velocity"):
			var recorded_velocity = ReplayUtils.from_json_safe(player_data["pre_move_velocity"])
			
			# Inyectar la velocidad y sus componentes descompuestos en el controlador.
			# Esto es crucial porque _physics_process usa 'horizontal_velocity' y 'vertical_velocity'
			# para calcular el movimiento final.
			player.velocity = recorded_velocity
			player.pre_move_velocity_for_replay = recorded_velocity # Para consistencia en logs
			player.horizontal_velocity = recorded_velocity - Vector3(0, recorded_velocity.y, 0)
			player.vertical_velocity.y = recorded_velocity.y
			
			# Adicionalmente, actualizar el componente de movimiento si existe.
			if player.movement_comp:
				player.movement_comp.horizontal_velocity = player.horizontal_velocity
			
			_debug_log("VELOCITY INJECTED: %s" % str(recorded_velocity))
func check_for_drift(frame_data: Dictionary) -> void:
	if not player:
		return
	if current_replay.frame_states.size() <= frame_index:
		return
	
	var recorded_state = current_replay.frame_states[frame_index]
	if not recorded_state.has(str(player_path)):
		return
	
	var expected_transform_dict = recorded_state[str(player_path)]["global_transform"]
	var expected_transform = ReplayUtils.dict_to_transform(expected_transform_dict)
	if not expected_transform is Transform:
		return
	
	var expected_origin = expected_transform.origin
	var current_origin = player.global_transform.origin
	var difference = current_origin.distance_to(expected_origin)
	
	if difference > DRIFT_THRESHOLD:
		printerr("--- REGRESSION TEST FAILED: DRIFT DETECTED ---")
		printerr("Frame: %d" % frame_index)
		printerr("Divergence: %s" % difference)
		printerr("Expected Position: %s" % expected_origin)
		printerr("Actual Position: %s" % current_origin)
		assert(false, "Physics drift exceeded tolerance.")

func _set_tracked_nodes_physics_process(enabled: bool) -> void:
	"""Helper function to enable or disable physics for all tracked nodes."""
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(enabled)
		print("[ReplayPlayback] _set_tracked_nodes_physics_process: Player physics enabled? ", enabled, player.is_physics_processing())
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
