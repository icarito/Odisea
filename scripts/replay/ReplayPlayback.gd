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

func _debug_log(message: String) -> void:
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayPlayback] " + message)

func _physics_process(delta: float) -> void:
	# Guard clause: Do nothing if there's no replay loaded or if it's paused.
	if not current_replay or playback_paused:
		return

	time_accumulator += delta

	while frame_index < total_logical_frames:
		var frame_data = current_replay.frames[frame_index]
		var recorded_delta = frame_data.get("delta", 1.0 / 60.0)

		if time_accumulator >= recorded_delta:
			_debug_log("ReplayPlayback _physics_process: Simulating frame " + str(frame_index))
			_apply_inputs_from_frame(frame_data)
			_simulate_frame(recorded_delta, frame_data)
			time_accumulator -= recorded_delta
		else:
			# Not enough accumulated time to process the next frame, break the loop
			break

	if frame_index >= total_logical_frames:
		stop_playback()

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
	
	# Wait for one frame to ensure the entire scene tree is ready.
	# This prevents "node not found" errors when accessing nodes immediately after a scene load.
	yield(get_tree(), "idle_frame")
	
	# Update references after scene change
	camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	player = PlayerManager.get_player()
	
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
	print("Starting loaded playback...")
	
	# Disable camera input
	var camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig:
		camera_rig.set_process_input(false)

	# Disable player input to prevent user interference during playback
	var player = PlayerManager.get_player()
	if player:
		player.set_process_input(false)

	playback_status = "Playing"
	resume_playback()
	resume_playback()
func stop_playback() -> void:
	print("Stopping playback.")
	playback_paused = true
	playback_status = "Stopped"
	
	# Use a check to prevent error if trying to remove from a group it's not in.
	if is_in_group("playback_active"):
		remove_from_group("playback_active")

	set_physics_process(false)

	for action in INPUT_ACTIONS:
		Input.action_release(action)

	# Re-enable physics and input for camera only, keep player frozen
	_set_tracked_nodes_physics_process(true)
	var camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig:
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
	if not playback_paused:
		return
	if not is_in_group("playback_active"): # Add to group when playback actually resumes
		add_to_group("playback_active")

	playback_paused = false
	playback_status = "Playing"
	set_physics_process(true)
	emit_signal("playback_resumed")
	set_physics_process(true)
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
			if player and player.has_node("PlayerInput"):
				# Directly provide the mouse motion to the component that handles it.
				player.get_node("PlayerInput").mouse_motion += mouse_motion
func _simulate_frame(recorded_delta: float, frame_data: Dictionary) -> void:
	_debug_log("Simulating frame " + str(frame_index))

	var expected_time: float = current_replay.frames[frame_index].get("timestamp", 0.0)
	var actual_time: float = Time.get_ticks_usec() - playback_start_time
	print("[Timing] Frame %d: expected %.3f ms, actual %.3f ms, diff %.3f ms" % [frame_index, expected_time / 1000.0, actual_time / 1000.0, (actual_time - expected_time) / 1000.0])

	# Manually call _physics_process on the player with the recorded delta
	var player = PlayerManager.get_player()
	if player:
		player._physics_process(recorded_delta)

	# Manually call _physics_process on the camera rig to simulate camera movement
	var camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig and frame_data.has("camera"):
		camera_rig.set_replay_state(frame_data["camera"])
	if camera_rig:
		camera_rig._physics_process(recorded_delta)

	# Log drift if debug mode
	if GameGlobals and GameGlobals.replay_debug_mode and frame_index < len(current_replay.frame_states):
		var expected_state = current_replay.frame_states[frame_index]
		var actual_state = {}
		if player:
			actual_state[get_tree().current_scene.get_path_to(player)] = player.get_replay_state()
		if camera_rig and camera_rig.has_method("get_replay_state"):
			actual_state[get_tree().current_scene.get_path_to(camera_rig)] = camera_rig.get_replay_state()
		
		# Compare positions or key values
		for path in expected_state:
			if actual_state.has(path):
				var expected = expected_state[path]
				var actual = actual_state[path]
				if expected.has("global_transform") and actual.has("global_transform"):
					var exp_pos = expected["global_transform"]["origin"] if expected["global_transform"] is Dictionary else Vector3.ZERO
					var act_pos = actual["global_transform"]["origin"] if actual["global_transform"] is Dictionary else Vector3.ZERO
					var drift = (exp_pos - act_pos).length()
					print("[Drift] Frame %d, Node %s: position drift %.6f" % [frame_index, path, drift])

	# Advance the logical frame counter for UI display
	frame_index += 1
	emit_signal("frame_updated", frame_index, total_logical_frames)

func _set_tracked_nodes_physics_process(enabled: bool) -> void:
	"""Helper function to enable or disable physics for all tracked nodes."""
	var player = PlayerManager.get_player()
	if player:
		# When playback starts, we disable automatic physics processing for the player.
		# When it stops, we re-enable it.
		player.set_physics_process(enabled)
		
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		# Other nodes can still be controlled automatically if needed.
		node.set_physics_process(enabled)

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
