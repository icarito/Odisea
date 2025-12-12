extends Node

signal recording_stopped(frame_count, replay_path)

const ReplayScript = preload("res://scripts/replay/Replay.gd")

const REPLAY_GROUP = "replay_track"
const REPLAYS_DIR = "res://replays/"

const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint"
]

var recording_paused: bool = false
var current_replay: Resource = null

func _physics_process(_delta: float) -> void:
	if not recording_paused:
		_record_frame()

func start_recording() -> void:
	print("Starting recording...")
	
	var replay = ReplayScript.new()
	replay.scene_path = get_tree().current_scene.filename
	replay.godot_version = Engine.get_version_info()["string"]
	replay.timestamp = Time.get_datetime_string_from_unix_time(Time.get_unix_time_from_system())

	for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
		var path = get_tree().current_scene.get_path_to(node)
		replay.initial_states[path] = _get_node_state(node)

	current_replay = replay
	set_physics_process(true)

func stop_recording() -> void:
	print("Stopping recording.")
	set_physics_process(false)

	var frame_count = len(current_replay.frames)

	var dir = Directory.new()
	if not dir.dir_exists(REPLAYS_DIR):
		dir.make_dir_recursive(REPLAYS_DIR)

	var filename = String(current_replay.timestamp).replace(":", "-") + ".json"
	var path = REPLAYS_DIR.plus_file(filename)

	current_replay.save_to_json(path)
	print("Replay saved to: " + path)
	
	emit_signal("recording_stopped", frame_count, path)

	current_replay = null


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
			state["linear_velocity"] = Vector3.ZERO

	return state
