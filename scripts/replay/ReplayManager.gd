extends Node

signal replay_failed

const ReplayScript = preload("res://scripts/replay/Replay.gd")

enum ReplayMode {
	NONE,
	RECORDING,
	PLAYBACK
}

var mode: int = ReplayMode.NONE
var current_replay: Resource = null
var frame_index: int = 0
var playback_paused: bool = false
var headless: bool = false

const REPLAY_GROUP = "replay_track"
const REPLAYS_DIR = "res://replays/"

const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint"
]

const FLOAT_TOLERANCE = 0.001

func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS

func _physics_process(_delta: float) -> void:
	if mode == ReplayMode.RECORDING:
		_record_frame()
	elif mode == ReplayMode.PLAYBACK and not playback_paused:
		_playback_frame()

func start_recording() -> void:
	if mode != ReplayMode.NONE:
		return

	print("Starting recording...")
	mode = ReplayMode.RECORDING

	var replay = ReplayScript.new()
	replay.scene_path = get_tree().current_scene.filename
	replay.godot_version = Engine.get_version_info()["string"]
	replay.timestamp = OS.get_datetime_string_from_unix_time(OS.get_unix_time())

	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		var path = get_tree().current_scene.get_path_to(node)
		replay.initial_states[path] = _get_node_state(node)

	current_replay = replay

func stop_recording() -> void:
	if mode != ReplayMode.RECORDING:
		return

	print("Stopping recording.")

	var dir = Directory.new()
	if not dir.dir_exists(REPLAYS_DIR):
		dir.make_dir_recursive(REPLAYS_DIR)

	var filename = String(current_replay.timestamp).replace(":", "-") + ".json"
	var path = REPLAYS_DIR.plus_file(filename)

	current_replay.save_to_json(path)
	print("Replay saved to: " + path)

	mode = ReplayMode.NONE
	current_replay = null

func start_playback(replay_path: String, is_headless: bool = false) -> void:
	if mode != ReplayMode.NONE:
		return

	var replay = ReplayScript.new()
	if replay.load_from_json(replay_path) != OK:
		print("Failed to load replay: " + replay_path)
		return

	print("Starting playback...")

	get_tree().change_scene(replay.scene_path)
	yield(get_tree(), "idle_frame")

	mode = ReplayMode.PLAYBACK
	current_replay = replay
	frame_index = 0
	playback_paused = false
	headless = is_headless

	for path in current_replay.initial_states:
		var node = get_tree().root.get_node(path)
		if node:
			_set_node_state(node, current_replay.initial_states[path])

func stop_playback() -> void:
	if mode != ReplayMode.PLAYBACK:
		return

	print("Stopping playback.")
	mode = ReplayMode.NONE
	current_replay = null
	for action in INPUT_ACTIONS:
		Input.action_release(action)

func step_frame() -> void:
	if mode == ReplayMode.PLAYBACK and playback_paused:
		_playback_frame()

func _record_frame() -> void:
	if not current_replay:
		return

	var frame_data = {
		"inputs": {},
		"nodes": {}
	}

	for action in INPUT_ACTIONS:
		frame_data["inputs"][action] = Input.is_action_pressed(action)

	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		var path = get_tree().current_scene.get_path_to(node)
		frame_data["nodes"][path] = _get_node_state(node)

	current_replay.frames.append(frame_data)

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
					emit_signal("replay_failed")
					stop_playback()
				else:
					get_tree().paused = true
				return

	frame_index += 1

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
		pass

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
