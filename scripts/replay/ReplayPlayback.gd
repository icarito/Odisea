extends Node

signal playback_started(total_frames)
signal playback_stopped
signal playback_failed
signal playback_paused
signal playback_resumed
signal frame_updated(frame_index, total_frames)

const ReplayScript = preload("res://scripts/replay/Replay.gd")
const REPLAY_GROUP = "replay_track"
const FLOAT_TOLERANCE = 0.001
const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]

var current_replay: Resource = null
var current_replay_filename: String = ""
var frame_index: int = 0
var playback_paused: bool = false

var desync_frames_count := 0
const DESYNC_FRAME_TOLERANCE = 5 # Let it run for N frames after first desync to gather more info.

var headless: bool = false

func _debug_log(message: String) -> void:
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayPlayback] " + message)

func _physics_process(delta: float) -> void:
	if not playback_paused:
		# During playback, we ignore the engine's delta and use the one from the replay file.
		var frame_data = current_replay.frames[frame_index]
		var recorded_delta = frame_data.get("delta", delta) # Fallback to engine delta if not present
		_playback_frame(recorded_delta)


func start_playback(replay_path: String, is_headless: bool = false) -> void:
	var replay = ReplayScript.new()
	if replay.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		emit_signal("playback_failed")
		return

	current_replay_filename = replay_path.get_file()
	print("Loading replay scene: ", replay.scene_path)
	
	current_replay = replay
	headless = is_headless
	
	# Wait for one frame to ensure the entire scene tree is ready.
	# This prevents "node not found" errors when accessing nodes immediately after a scene load.
	yield(get_tree(), "idle_frame")
	_prepare_scene_for_playback()
	
	# The playback is loaded, but paused, waiting for the user to press play.
	pause_playback() 
	
	emit_signal("playback_started", len(current_replay.frames))
	
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
	_set_tracked_nodes_physics_process(true)

	# Disable camera input
	var camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig:
		camera_rig.set_process_input(false)

	resume_playback()

func stop_playback() -> void:
	print("Stopping playback.")
	playback_paused = true
	set_physics_process(false)

	for action in INPUT_ACTIONS:
		Input.action_release(action)

	# Re-enable physics and input
	_set_tracked_nodes_physics_process(true)
	var player = PlayerManager.get_player()
	if player:
		player.set_process_input(true)

	# Re-enable camera input
	var camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig:
		camera_rig.set_process_input(true)

	if get_node("/root/AudioSystem"):
		get_node("/root/AudioSystem").stop_bgm() # consider if we want to resume music

	emit_signal("playback_stopped")

func pause_playback() -> void:
	if playback_paused:
		return
	playback_paused = true
	set_physics_process(false)
	_set_tracked_nodes_physics_process(false)
	emit_signal("playback_paused")

func resume_playback() -> void:
	if not playback_paused:
		return
	playback_paused = false
	set_physics_process(true)
	_set_tracked_nodes_physics_process(true)
	emit_signal("playback_resumed")

func rewind_playback() -> void:
	seek(0)

func seek(frame_idx: int) -> void:
	if not current_replay or frame_idx < 0 or frame_idx >= len(current_replay.frames):
		return
		
	frame_index = frame_idx
	var frame_data = current_replay.frames[frame_index]
	for path in frame_data["nodes"]:
		var node = get_tree().current_scene.get_node(path)
		if node:
			_set_node_state(node, frame_data["nodes"][path])
	
	emit_signal("frame_updated", frame_index, len(current_replay.frames))

func step_frame() -> void:
	if frame_index < len(current_replay.frames) - 1:
		seek(frame_index + 1)

func step_back_frame() -> void:
	if frame_index > 0:
		seek(frame_index - 1)

func _playback_frame(recorded_delta: float) -> void:
	if not current_replay or frame_index >= len(current_replay.frames):
		stop_playback()
		return

	_debug_log("Playing frame " + str(frame_index))
	var frame_data = current_replay.frames[frame_index]

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
	
	# Manually call _physics_process on the player with the recorded delta
	var player = PlayerManager.get_player()
	if player:
		player._physics_process(recorded_delta)

	var desync_detected_this_frame = false
	for path in frame_data["nodes"]:
		var node = get_tree().current_scene.get_node(path)
		if node:
			var recorded_state = frame_data["nodes"][path]
			var live_state = _get_node_state(node)
			if not _compare_states(recorded_state, live_state):
				desync_detected_this_frame = true
				desync_frames_count += 1
				print("State mismatch at frame %d for node %s (desync count: %d)" % [frame_index, path, desync_frames_count])
				print("  Recorded: %s" % [recorded_state])
				print("  Live:     %s" % [live_state])
				if desync_frames_count >= DESYNC_FRAME_TOLERANCE:
					if headless:
						emit_signal("playback_failed")
						stop_playback()
					else:
						get_tree().paused = true
					return

	if not desync_detected_this_frame:
		desync_frames_count = 0 # Reset counter if the frame is in sync

	# Advance frame index, accounting for skipped frames
	if frame_data.has("skip"):
		frame_index += frame_data["skip"] + 1
	else:
		frame_index += 1
		
	emit_signal("frame_updated", frame_index, len(current_replay.frames))

func _set_tracked_nodes_physics_process(enabled: bool) -> void:
	"""Helper function to enable or disable physics for all tracked nodes."""
	# We will now manage the player's physics process manually.
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(false) # Let the playback node call it manually

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

func _compare_states(recorded_state: Dictionary, live_state: Dictionary) -> bool:
	for key in recorded_state:
		if not live_state.has(key):
			return false

		var recorded_val = recorded_state[key]
		var live_val = live_state[key] # live_state already has Godot types

		# Convert recorded_val from JSON-safe dictionary to Godot type for comparison
		recorded_val = get_node("/root/ReplayUtils").from_json_safe(recorded_val)

		if typeof(recorded_val) != typeof(live_val):
			_debug_log("Type mismatch for key '%s': Recorded is %s (value: %s), Live is %s (value: %s)" % [key, typeof(recorded_val), recorded_val, typeof(live_val), live_val])
			return false

		match typeof(recorded_val):
			TYPE_TRANSFORM:
				# Use tolerance for Transform comparison
				if recorded_val.origin.distance_squared_to(live_val.origin) > FLOAT_TOLERANCE * FLOAT_TOLERANCE:
					_debug_log("Transform origin mismatch for key '%s': Recorded %s, Live %s" % [key, recorded_val.origin, live_val.origin])
					return false
				if not recorded_val.basis.is_equal_approx(live_val.basis):
					_debug_log("Transform basis mismatch for key '%s': Recorded %s, Live %s" % [key, recorded_val.basis, live_val.basis])
					return false
			TYPE_REAL:
				if abs(recorded_val - live_val) > FLOAT_TOLERANCE:
					_debug_log("Float mismatch for key '%s': Recorded %f, Live %f" % [key, recorded_val, live_val])
					return false
			TYPE_VECTOR2, TYPE_VECTOR3:
				if recorded_val.distance_to(live_val) > FLOAT_TOLERANCE:
					_debug_log("Vector mismatch for key '%s': Recorded %s, Live %s" % [key, recorded_val, live_val])
					return false
			# Removed the duplicate TYPE_TRANSFORM comparison.
			# TYPE_TRANSFORM2D would fall through to default comparison if not explicitly handled.
			_: # Default comparison for other types (int, bool, string, etc.)
				if recorded_val != live_val:
					_debug_log("Value mismatch for key '%s': Recorded %s, Live %s" % [key, recorded_val, live_val])
					return false
	return true
