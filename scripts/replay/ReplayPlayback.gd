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
	"left", "right", "forward", "backward", "jump", "sprint"
]

var current_replay: Resource = null
var current_replay_filename: String = ""
var frame_index: int = 0
var playback_paused: bool = false
var headless: bool = false

func _physics_process(_delta: float) -> void:
	if not playback_paused:
		_playback_frame()

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
	
	_prepare_scene_for_playback()
	
	# The playback is loaded, but paused, waiting for the user to press play.
	pause_playback() 
	
	emit_signal("playback_started", len(current_replay.frames))
	
	# Go to first frame
	seek(0)

func _prepare_scene_for_playback():
	# Stop physics process for player and replay group nodes
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(false)
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		node.set_physics_process(false)

	# Stop music
	if get_node("/root/AudioSystem"):
		get_node("/root/AudioSystem").stop_bgm()
		
	for path in current_replay.initial_states:
		var node = get_tree().root.get_node(path)
		if node:
			_set_node_state(node, current_replay.initial_states[path])


func start_loaded_playback() -> void:
	print("Starting loaded playback...")
	
	# Re-enable physics process
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(true)
		player.set_process_input(false)  # Disable input during playback
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		node.set_physics_process(true)

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
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(true)
		player.set_process_input(true)
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		node.set_physics_process(true)

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
	# Disable physics to stop simulation
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(false)
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		node.set_physics_process(false)
	emit_signal("playback_paused")

func resume_playback() -> void:
	if not playback_paused:
		return
	playback_paused = false
	set_physics_process(true)
	# Re-enable physics
	var player = PlayerManager.get_player()
	if player:
		player.set_physics_process(true)
	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		node.set_physics_process(true)
	emit_signal("playback_resumed")

func rewind_playback() -> void:
	seek(0)

func seek(frame_idx: int) -> void:
	if not current_replay or frame_idx < 0 or frame_idx >= len(current_replay.frames):
		return
		
	frame_index = frame_idx
	var frame_data = current_replay.frames[frame_index]
	for path in frame_data["nodes"]:
		var node = get_tree().root.get_node(path)
		if node:
			_set_node_state(node, frame_data["nodes"][path])
	
	emit_signal("frame_updated", frame_index, len(current_replay.frames))

func step_frame() -> void:
	if frame_index < len(current_replay.frames) - 1:
		seek(frame_index + 1)

func step_back_frame() -> void:
	if frame_index > 0:
		seek(frame_index - 1)

func _playback_frame() -> void:
	if not current_replay or frame_index >= len(current_replay.frames):
		stop_playback()
		return

	var frame_data = current_replay.frames[frame_index]

	for action in frame_data["inputs"]:
		if frame_data["inputs"][action]:
			Input.action_press(action)
		else:
			Input.action_release(action)

	yield(get_tree(), "idle_frame")

	for path in frame_data["nodes"]:
		var node = get_tree().root.get_node(path)
		if node:
			var recorded_state = frame_data["nodes"][path]
			var live_state = _get_node_state(node)
			if not _compare_states(recorded_state, live_state):
				print("State mismatch at frame %d for node %s" % [frame_index, path])
				print("  Recorded: %s" % [recorded_state])
				print("  Live:     %s" % [live_state])
				if headless:
					emit_signal("playback_failed")
					stop_playback()
				else:
					get_tree().paused = true
				return

	frame_index += 1
	emit_signal("frame_updated", frame_index, len(current_replay.frames))


func _get_node_state(node: Node) -> Dictionary:
	if node.has_method("get_replay_state"):
		return node.get_replay_state()

	var state = {}
	if node is Spatial:
		state["global_transform"] = node.global_transform
	if node is RigidBody:
		state["linear_velocity"] = node.linear_velocity
		state["angular_velocity"] = node.angular_velocity
	if node is KinematicBody:
		if node.has_method("get_horizontal_velocity"):
			state["linear_velocity"] = node.get_horizontal_velocity()
		else:
			state["linear_velocity"] = Vector3.ZERO  # Default if no method

	return state

func _set_node_state(node: Node, state: Dictionary) -> void:
	if node.has_method("set_replay_state"):
		node.set_replay_state(state)
		return

	for key in state:
		if key == "global_transform" and node is Spatial:
			node.global_transform = state[key]
		elif key == "linear_velocity" and node is RigidBody:
			node.linear_velocity = state[key]
		elif key == "angular_velocity" and node is RigidBody:
			node.angular_velocity = state[key]
		else:
			node.set(key, state[key])

func _compare_states(recorded_state: Dictionary, live_state: Dictionary) -> bool:
	for key in recorded_state:
		if not live_state.has(key):
			return false

		var recorded_val = recorded_state[key]
		var live_val = live_state[key]

		if typeof(recorded_val) != typeof(live_val):
			return false

		match typeof(recorded_val):
			TYPE_REAL:
				if abs(recorded_val - live_val) > FLOAT_TOLERANCE:
					return false
			TYPE_VECTOR2, TYPE_VECTOR3:
				if recorded_val.distance_to(live_val) > FLOAT_TOLERANCE:
					return false
			TYPE_TRANSFORM, TYPE_TRANSFORM2D:
				if recorded_val.origin.distance_to(live_val.origin) > FLOAT_TOLERANCE:
					return false
				if not recorded_val.basis.is_equal_approx(live_val.basis):
					return false
			_:
				if recorded_val != live_val:
					return false
	return true
