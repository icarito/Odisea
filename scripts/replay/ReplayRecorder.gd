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
var player: Node = null
var camera_rig: Node = null
var start_time: int = 0

func _debug_log(message: String) -> void:
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayRecorder] " + message)

func _ready() -> void:
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if is_recording() and event is InputEventMouseMotion:
		mouse_motion_this_frame += event.relative

func _physics_process(delta: float) -> void:
	if not recording_paused:
		_record_frame(delta)

func start_recording(): # This function now acts like a coroutine
	# Defer the start of recording by one frame to ensure all Autoloads are ready.
	_debug_log("Starting recording...")
	start_time = Time.get_ticks_usec()
	GameGlobals.is_recording = true

	var replay = ReplayScript.new()
	replay.scene_path = get_tree().current_scene.filename
	replay.godot_version = Engine.get_version_info()["string"]
	replay.timestamp = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()))

	player = PlayerManager.get_player()
	var initial = {}
	if player:
		initial[get_tree().current_scene.get_path_to(player)] = player.get_replay_state()
	
	# Add CameraRig state
	camera_rig = get_tree().get_root().find_node("CameraRig", true, false)
	if camera_rig and camera_rig.has_method("get_replay_state"):
		initial[get_tree().current_scene.get_path_to(camera_rig)] = camera_rig.get_replay_state()
	
	replay.initial_states = get_node("/root/ReplayUtils").to_json_safe(initial)
	# Initialize last_frame_data with an empty inputs dict. This ensures the first
	# frame is always recorded and prevents a crash when accessing .inputs.
	last_frame_data = {"inputs": {}}

	current_replay = replay
	set_physics_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
	GameGlobals.is_recording = false


func _record_frame(delta: float) -> void:
	if not current_replay:
		return

	var frame_data = {
		"delta": delta,
		"inputs": {},
		# "nodes": {} # We no longer record node state per frame for an input-based replay
	}

	for action in INPUT_ACTIONS:
		frame_data["inputs"][action] = Input.is_action_pressed(action)

	frame_data["inputs"]["mouse_motion"] = mouse_motion_this_frame
	frame_data["timestamp"] = Time.get_ticks_usec() - start_time
	mouse_motion_this_frame = Vector2.ZERO
	
	current_replay.frames.append(frame_data)
	last_frame_data = frame_data
	
	# Record states for drift measurement
	var states = {}
	if player:
		states[get_tree().current_scene.get_path_to(player)] = player.get_replay_state()
	if camera_rig and camera_rig.has_method("get_replay_state"):
		states[get_tree().current_scene.get_path_to(camera_rig)] = camera_rig.get_replay_state()
	current_replay.frame_states.append(states)


func is_recording() -> bool:
	return current_replay != null and not recording_paused

func _are_dictionaries_equal(dict1: Dictionary, dict2: Dictionary) -> bool:
	# Comparing JSON strings is a fast and reliable way to perform a deep comparison
	# of dictionaries, including nested ones.
	# We pass `false` for the `indent` argument to ensure the strings are compact and comparable.
	return JSON.print(dict1, "", false) == JSON.print(dict2, "", false)
