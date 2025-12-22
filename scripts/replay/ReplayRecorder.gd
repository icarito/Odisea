extends Node

onready var ReplayScript = load("res://scripts/replay/Replay.gd")

const REPLAY_GROUP = "replay_track"
const REPLAYS_DIR = "res://replays/"
const FIXED_DELTA = 1.0 / 60.0 # Fixed delta for deterministic recording
const SNAPSHOT_INTERVAL = 100

const INPUT_ACTIONS = [
	"left", "right", "forward", "backward", "jump", "sprint", "roll", "attack", "aim"
]

signal recording_stopped(frame_count, replay_path)

var recording_paused: bool = false
var current_replay: Resource = null
var mouse_motion_accumulated := Vector2.ZERO
var last_frame_data: Dictionary = {}
var player: Node = null
var camera_rig: Node = null
var start_time: int = 0

const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")

func _debug_log(message: String) -> void:
	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if game_globals and game_globals.replay_debug_mode:
		print("[ReplayRecorder] " + message)

func _ready() -> void:
	process_priority = -10  # Low priority to run before CameraRig
	var game_globals = GameGlobals
	if not game_globals:
		game_globals = get_node_or_null("/root/GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../GameGlobals")
	if not game_globals:
		game_globals = get_node_or_null("../../GameGlobals")
	if not (game_globals and game_globals.is_replaying):  # Only enable input processing when not replaying
		set_process_input(true)
		set_process_unhandled_input(true)
	else:
		set_process_input(false)
		set_process_unhandled_input(false)
	print("ReplayRecorder _ready: process_input enabled: ", is_processing_input())
	print("ReplayRecorder is in tree: ", is_inside_tree())
	if is_inside_tree():
		print("ReplayRecorder tree path: ", get_path())

func _input(event: InputEvent) -> void:
	if is_recording() and event is InputEventMouseMotion:
		mouse_motion_accumulated += event.relative
		print("DEBUG CAPTURE: Mouse Motion acumulado: ", mouse_motion_accumulated)
		# Do not accept the event, so it continues to CameraRig

func _unhandled_input(event: InputEvent) -> void:
	if is_recording() and event is InputEventMouseMotion:
		mouse_motion_accumulated += event.relative
		print("DEBUG UNHANDLED CAPTURE: Mouse Motion acumulado: ", mouse_motion_accumulated)

func _physics_process(delta: float) -> void:
	if not recording_paused:
		record_frame(delta)

func start_recording(): # This function now acts like a coroutine
	# Defer the start of recording by one frame to ensure all Autoloads are ready.
	print("ReplayRecorder start_recording called")
	_debug_log("Starting recording...")
	start_time = Time.get_ticks_usec()
	GameGlobals.is_recording = true
	InputState.mode = InputState.Mode.RECORD

	var replay = ReplayScript.new()
	if get_tree() and get_tree().current_scene:
		replay.scene_path = get_tree().current_scene.filename
	else:
		replay.scene_path = "unknown"
	replay.godot_version = Engine.get_version_info()["string"]
	replay.timestamp = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()))

	# Assign current_replay early so stop_recording() can safely run
	# even if this function yields waiting for deferred nodes to enter the tree.
	current_replay = replay

	player = PlayerManager.get_player()
	var initial = {}
	if player:
		# If player was spawned via deferred call, it might not be in the SceneTree yet.
		# Wait a single idle frame to allow deferred add_child() to complete,
		# then only call get_path() if the node is inside the tree.
		if not player.is_inside_tree():
			yield(get_tree(), "idle_frame")
		if player.is_inside_tree():
			initial[player.get_path()] = player.get_replay_state()
	
	# Add CameraRig state
	if get_tree() and get_tree().current_scene:
		camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig and camera_rig.has_method("get_replay_state"):
			if not camera_rig.is_inside_tree():
				yield(get_tree(), "idle_frame")
			if camera_rig.is_inside_tree():
				initial[camera_rig.get_path()] = camera_rig.get_replay_state()
	
	replay.initial_states = ReplayUtils.to_json_safe(initial)
	# Initialize last_frame_data with an empty inputs dict. This ensures the first
	# frame is always recorded and prevents a crash when accessing .inputs.
	last_frame_data = {"inputs": {}}

	current_replay = replay
	set_physics_process(true)
	MouseCapture.set_capture(true)

func stop_recording() -> void:
	_debug_log("Stopping recording.")
	set_physics_process(false)

	if not current_replay:
		_debug_log("stop_recording called but no current_replay present; ignoring.")
		return

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


func record_frame(delta: float) -> void:
	# _debug_log("Start of _record_frame: mouse_motion_this_frame = " + str(mouse_motion_this_frame))
	if not current_replay:
		return
	if GameGlobals and GameGlobals.is_replaying:
		return  # Do not record during replay playback

	# Resolve InputState: prefer autoload (/root/InputState), fall back to current_scene node named "InputState"
	var input_state_node = null
	if get_tree():
		# Prefer the InputState instance in the current scene (tests create a scene-local
		# InputState). Fallback to autoload /root/InputState if none exists in scene.
		if get_tree().current_scene:
			input_state_node = get_tree().current_scene.get_node_or_null("InputState")
		if not input_state_node:
			input_state_node = get_node_or_null("/root/InputState")

	var inputs_dict = {}
	var axes_dict = {}
	var mouse_delta_dict = {"x": 0.0, "y": 0.0}
	var strafing_active = false
	var strafing_timer_val = 0.0
	if input_state_node:
		# InputState script defines these properties; access directly.
		inputs_dict = input_state_node.actions.duplicate()
		axes_dict = input_state_node.axes.duplicate()
		mouse_delta_dict = {"x": input_state_node.recorded_mouse_delta.x, "y": input_state_node.recorded_mouse_delta.y}
		strafing_active = input_state_node.is_strafing_mode_active
		strafing_timer_val = input_state_node.strafing_timer

	var frame_data = {
		"delta": FIXED_DELTA,
		"inputs": inputs_dict,
		"axes": axes_dict,
		"mouse_delta": mouse_delta_dict,
		"strafing_active": strafing_active,
		"strafing_timer": strafing_timer_val,
		"timestamp": Time.get_ticks_usec() - start_time
	}
	
	# Snapshot placeholder for every frame; actual positional states (player/camera) are recorded
	# into frame_states only at SNAPSHOT_INTERVAL to avoid large per-frame data.
	var snapshot = {}
	frame_data["snapshot"] = snapshot
	
	# Record camera state
	var camera = camera_rig
	if camera:
		var camera_yaw = camera.yaw.rotation.y
		var camera_pitch = camera.pitch.rotation.x
		var spring_length = camera.springarm.spring_length
		frame_data["camera"] = {"yaw": camera_yaw, "pitch": camera_pitch, "spring_length": spring_length}
	
	# Record player external velocity
	if player and player.external_velocity:
		frame_data["player_external_velocity"] = ReplayUtils.vector3_to_dict(player.external_velocity.velocity)
	
	# Record player gravity override
	if player:
		var grav = player.get("gravity_override")
		if grav == null:
			grav = Vector3(0, -9.8, 0)
		frame_data["player_gravity_override"] = ReplayUtils.vector3_to_dict(grav)
	
	# Ensure frame data is JSON-safe before storing
	var safe_frame = ReplayUtils.to_json_safe(frame_data)
	current_replay.frames.append(safe_frame)
	last_frame_data = safe_frame

	# Every SNAPSHOT_INTERVAL frames, capture debug snapshot and record positional states
	var frame_index = len(current_replay.frames)
	if frame_index % SNAPSHOT_INTERVAL == 0:
		var debug_snapshot = {}
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			if not node.is_inside_tree():
				continue
			if node.has_method("get_replay_state"):
				debug_snapshot[node.get_path()] = node.get_replay_state()

		# store debug snapshot in snapshots map
		current_replay.snapshots[str(frame_index)] = ReplayUtils.to_json_safe(debug_snapshot)

		# also attach debug snapshot into the last frame's snapshot.debug for test expectations
		if current_replay.frames.size() > 0:
			var last_frame = current_replay.frames[current_replay.frames.size() - 1]
			if last_frame.has("snapshot"):
				last_frame["snapshot"]["debug"] = ReplayUtils.to_json_safe(debug_snapshot)

		# Record states for drift measurement (player and camera positions)
		var states = {}
		if player and player.is_inside_tree():
			states[player.get_path()] = player.get_replay_state()
		if camera_rig and camera_rig.has_method("get_replay_state") and camera_rig.is_inside_tree():
			states[camera_rig.get_path()] = camera_rig.get_replay_state()
		current_replay.frame_states.append(ReplayUtils.to_json_safe(states))


func is_recording() -> bool:
	return current_replay != null and not recording_paused

func record_frames(count: int) -> void:
	for i in range(count):
		record_frame(1.0/60.0)

func _are_dictionaries_equal(dict1: Dictionary, dict2: Dictionary) -> bool:
	# Comparing JSON strings is a fast and reliable way to perform a deep comparison
	# of dictionaries, including nested ones.
	# We pass `false` for the `indent` argument to ensure the strings are compact and comparable.
	return JSON.print(dict1, "", false) == JSON.print(dict2, "", false)
