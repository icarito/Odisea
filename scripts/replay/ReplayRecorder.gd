extends Node

const ReplayScript = preload("res://scripts/replay/Replay.gd")

const REPLAY_GROUP = "replay_track"
const REPLAYS_DIR = "res://replays/"

const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]

signal recording_stopped(frame_count, replay_path)

var recording_paused: bool = false
var current_replay: Resource = null
var mouse_motion_this_frame := Vector2.ZERO
var last_frame_data: Dictionary = {}

func _debug_log(message: String) -> void:
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayRecorder] " + message)

func _unhandled_input(event: InputEvent) -> void:
	if is_recording() and event is InputEventMouseMotion:
		mouse_motion_this_frame += event.relative

func _physics_process(delta: float) -> void:
	if not recording_paused:
		_record_frame(delta)

func start_recording(): # This function now acts like a coroutine
	# Defer the start of recording by one frame to ensure all Autoloads are ready.
	yield(get_tree(), "idle_frame")

	_debug_log("Starting recording...")
	
	var replay = ReplayScript.new()
	replay.scene_path = get_tree().current_scene.filename
	replay.godot_version = Engine.get_version_info()["string"]
	replay.timestamp = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()))

	replay.initial_states = get_node("/root/ReplayUtils").to_json_safe(_get_all_tracked_node_states())
	# Initialize last_frame_data with the initial state to allow skipping the very first frame if it's identical.
	last_frame_data = {"nodes": replay.initial_states}

	current_replay = replay
	set_physics_process(true)

func stop_recording() -> void:
	_debug_log("Stopping recording.")
	set_physics_process(false)

	var frame_count = len(current_replay.frames)

	var dir = Directory.new()
	if not dir.dir_exists(REPLAYS_DIR):
		dir.make_dir_recursive(REPLAYS_DIR)

	var filename = String(current_replay.timestamp).replace(":", "-") + ".json"
	var path = REPLAYS_DIR.plus_file(filename)

	current_replay.save_to_json(path)
	_debug_log("Replay saved to: " + path)
	
	emit_signal("recording_stopped", frame_count, path)

	current_replay = null
	last_frame_data = {}


func _record_frame(delta: float) -> void:
	if not current_replay:
		return

	var frame_data = {
		"delta": delta,
		"inputs": {},
		"nodes": {}
	}

	for action in INPUT_ACTIONS:
		frame_data["inputs"][action] = Input.is_action_pressed(action)

	frame_data["inputs"]["mouse_motion"] = mouse_motion_this_frame
	mouse_motion_this_frame = Vector2.ZERO

	frame_data["nodes"] = get_node("/root/ReplayUtils").to_json_safe(_get_all_tracked_node_states())

	# Compare only the node states, not the inputs, for more effective frame skipping.
	if not current_replay.frames.empty() and not last_frame_data.empty() and _are_dictionaries_equal(frame_data["nodes"], last_frame_data["nodes"]):
		var last_saved_frame = current_replay.frames[len(current_replay.frames) - 1]
		if not last_saved_frame.has("skip"):
			last_saved_frame["skip"] = 0
		last_saved_frame["skip"] += 1
		_debug_log("Frame skipped, new count: %d" % last_saved_frame["skip"])
	else:
		current_replay.frames.append(frame_data)
		last_frame_data = frame_data


func _get_all_tracked_node_states() -> Dictionary:
	var states = {}
	var player = PlayerManager.get_player()
	if player:
		var path = get_tree().current_scene.get_path_to(player)
		states[path] = _get_node_state(player)
		_debug_log("Getting state for player at path: " + path)

	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		var path = get_tree().current_scene.get_path_to(node)
		if not states.has(path):
			states[path] = _get_node_state(node)
			_debug_log("Getting state for node in group: " + path)
	return states

func _get_node_state(node: Node) -> Dictionary:
	return get_node("/root/ReplayUtils").get_node_state(node)

func is_recording() -> bool:
	return current_replay != null and not recording_paused

func _are_dictionaries_equal(dict1: Dictionary, dict2: Dictionary) -> bool:
	# Comparing JSON strings is a fast and reliable way to perform a deep comparison
	# of dictionaries, including nested ones.
	# We pass `false` for the `indent` argument to ensure the strings are compact and comparable.
	return JSON.print(dict1, "", false) == JSON.print(dict2, "", false)
