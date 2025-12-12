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

	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(false)  # Ensure player's automatic physics is disabled

	# If we have reached the end of the replay, stop playback.
	if frame_index >= total_logical_frames:
		stop_playback()
		return

	var frame_data = current_replay.frames[frame_index]
	var recorded_delta = frame_data.get("delta", 1.0 / 60.0) # Obtener el delta grabado
	
	_debug_log("ReplayPlayback _physics_process: Simulating frame " + str(frame_index))

	# 1. Aplicación de inputs (Mouse y Teclado)
	var recorded_inputs = frame_data.inputs
	print("[ReplayPlayback] Frame %d, Applying Mouse Motion: %s" % [frame_index, recorded_inputs.get("mouse_motion", Vector2.ZERO)])
	_apply_inputs_from_frame(frame_data)

	# 2. Simulación de física:
	if player and player.has_method("_physics_process"):
		player._physics_process(recorded_delta)

	# 3. VERIFICACIÓN: Posición simulada vs. Posición registrada
	if current_replay.frame_states.size() > frame_index:
		var recorded_state = current_replay.frame_states[frame_index]
		var player_data = recorded_state.get(str(player_path))
		if player_data:
			var recorded_pos_str = player_data.get("player_position")
			print("[ReplayPlayback DEBUG] Player Data Exists: True | Raw Position String: %s" % str(recorded_pos_str))
		else:
			print("[ReplayPlayback DEBUG] Player Data Exists: False (Frame keys: %s)" % [recorded_state.keys()])
	else:
		print("[ReplayPlayback DEBUG] frame_states index out of bounds")

	# 4. Restauración del estado de la cámara (para puntería):
	if frame_data.has("camera"):
		var cam_data = frame_data["camera"]
		var recorded_yaw = cam_data.get("yaw", 0.0)
		print("[ReplayPlayback] RESTORING Camera/Player Yaw: %s" % [recorded_yaw])
		if player:
			player.rotation.y = recorded_yaw + PI
			var camera_rig = player.get_node_or_null("CameraRig")
			if camera_rig:
				var yaw_node = camera_rig.get_node_or_null("Yaw")
				if yaw_node:
					yaw_node.rotation.y = recorded_yaw
	
	# PASO 3: Comprobar drift
	check_for_drift(frame_data)

	# PASO 4: Avanzar al siguiente frame lógico
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
		# Reset player state to frame 0 exact before enabling physics
		player.velocity = Vector3.ZERO
		if player.external_velocity:
			player.external_velocity.velocity = Vector3.ZERO
		player.set_physics_process(false) # CRITICAL: Disable auto-physics, we call it manually now.
		print("[ReplayPlayback] Player physics enabled? ", player.is_physics_processing())
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
		# Do not re-enable player physics here. It must remain disabled.
		print("[ReplayPlayback] Player physics enabled in resume_playback")
	
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
		player.external_velocity.velocity = frame_data["player_external_velocity"]

	if player and frame_data.has("player_gravity_override"):
		player.set("gravity_override", frame_data["player_gravity_override"])

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
func check_for_drift(frame_data: Dictionary) -> void:
	if not player:
		return
	if current_replay.frame_states.size() <= frame_index:
		return
	
	var recorded_state = current_replay.frame_states[frame_index]
	if not recorded_state.has(str(player_path)):
		return
	
	var expected_transform_string = recorded_state[str(player_path)]["global_transform"]
	var expected_transform = str2var(expected_transform_string)
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

func _get_node_state(node: Node) -> Dictionary:
	return get_node("/root/ReplayUtils").get_node_state(node)

func _set_node_state(node: Node, state: Dictionary) -> void:
	if node.has_method("set_replay_state"):
		node.set_replay_state(state)
		return
	state = get_node("/root/ReplayUtils").from_json_safe(state) # Convert the entire state dictionary from JSON-safe types to Godot types
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
		elif key == "linear_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.linear_velocity = state[key]
		elif key == "angular_velocity" and node is RigidBody:
			if state[key] is Vector3:
				node.angular_velocity = state[key]
