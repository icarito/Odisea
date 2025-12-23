extends Node

onready var ReplayScript = load("res://scripts/replay/Replay.gd")

const REPLAY_GROUP = "replay_track"
const REPLAYS_DIR = "res://replays/"
const FIXED_DELTA = 1.0 / 60.0 # Fixed delta for deterministic recording
const SNAPSHOT_INTERVAL = 10

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
var role_map: Dictionary = {}
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
			initial["player"] = player.get_replay_state()
		# Populate role_map
	role_map["player"] = player
	
	# Add CameraRig state
	if get_tree() and get_tree().current_scene:
		var viewport_cam = null
		if get_viewport():
			viewport_cam = get_viewport().get_camera()
		role_map["camera"] = camera_rig if camera_rig else viewport_cam
		if get_viewport():
			viewport_cam = get_viewport().get_camera()
		if camera_rig and camera_rig.has_method("get_replay_state"):
			if not camera_rig.is_inside_tree():
				yield(get_tree(), "idle_frame")
			if camera_rig.is_inside_tree():
				initial["camera"] = camera_rig.get_replay_state()
		elif viewport_cam and viewport_cam.has_method("get_replay_state"):
			if not viewport_cam.is_inside_tree():
				yield(get_tree(), "idle_frame")
			if viewport_cam.is_inside_tree():
				initial["camera"] = viewport_cam.get_replay_state()
		# Ensure camera_rig variable references whichever we recorded (prefer rig)
		if not camera_rig and viewport_cam:
			camera_rig = viewport_cam

	# Also expose top-level camera yaw/pitch shortcuts for tests/tools
	if initial.has("camera"):
		var cam_state = initial["camera"]
		# cam_state expected to have 'yaw' and 'pitch' keys from CameraRig.get_replay_state()
		initial["camera_yaw"] = cam_state.get("yaw", 0.0)
		initial["camera_pitch"] = cam_state.get("pitch", 0.0)

	# If camera not present yet, retry a few idle frames to allow deferred camera nodes to enter the tree.
	if not initial.has("camera"):
		var attempts := 0
		while attempts < 5:
			var found_cam = null
			if get_tree() and get_tree().current_scene:
				found_cam = get_tree().current_scene.find_node("CameraRig", true, false)
			if not found_cam and get_viewport():
				found_cam = get_viewport().get_camera()
			if found_cam and found_cam.has_method("get_replay_state"):
				if not found_cam.is_inside_tree():
					yield(get_tree(), "idle_frame")
				if found_cam.is_inside_tree():
					initial["camera"] = found_cam.get_replay_state()
					camera_rig = found_cam
					# expose yaw/pitch shortcuts as before
					var cs = initial["camera"]
					initial["camera_yaw"] = cs.get("yaw", 0.0)
					initial["camera_pitch"] = cs.get("pitch", 0.0)
					break
			attempts += 1
			yield(get_tree(), "idle_frame")

	replay.initial_states = ReplayUtils.to_json_safe(initial)
	# Generate state hash for determinism verification
	replay.state_hash = ReplayUtils.generate_state_hash(initial)
	# mark initial states frame as 0 (recording starts at frame 0)
	replay.initial_states_frame = 0
	# Initialize last_frame_data with an empty inputs dict. This ensures the first
	# frame is always recorded and prevents a crash when accessing .inputs.
	last_frame_data = {"inputs": {}}

	current_replay = replay
	set_physics_process(true)
	MouseCapture.set_capture(true)

	# Ensure player/camera are part of the replay group so snapshots include them
	if player and player.is_inside_tree():
		if not player.is_in_group(REPLAY_GROUP):
			player.add_to_group(REPLAY_GROUP)
	if camera_rig and camera_rig.is_inside_tree():
		if not camera_rig.is_in_group(REPLAY_GROUP):
			camera_rig.add_to_group(REPLAY_GROUP)

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

	# Before saving, record final_states snapshot for debugging/drift checks
	var final_states = {}
	# Use consistent keys: "player" and "camera"
	if player and player.is_inside_tree() and player.has_method("get_replay_state"):
		final_states["player"] = player.get_replay_state()
	if camera_rig and camera_rig.is_inside_tree() and camera_rig.has_method("get_replay_state"):
		final_states["camera"] = camera_rig.get_replay_state()
	# Expose top-level camera yaw/pitch for final snapshot as well
	if final_states.has("camera"):
		var fcam = final_states["camera"]
		final_states["camera_yaw"] = fcam.get("yaw", 0.0)
		final_states["camera_pitch"] = fcam.get("pitch", 0.0)

	# Mark final states frame index (frame count)
	current_replay.final_states = ReplayUtils.to_json_safe(final_states)
	current_replay.final_states_frame = frame_count
	_debug_log("Final states captured count=" + str(final_states.size()))

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
		mouse_delta_dict = {"x": FixedPoint.to_fixed(input_state_node.recorded_mouse_delta.x), "y": FixedPoint.to_fixed(input_state_node.recorded_mouse_delta.y)}
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

	# Optionally include lightweight player logical flags in each frame so playback
	# can access them without needing a full snapshot (useful for tests).
	if player and player.is_inside_tree() and player.has_method("get_replay_state"):
		var pstate = player.get_replay_state()
		frame_data["player_flags"] = {
			"was_on_floor": pstate.get("was_on_floor", false),
			"just_jumped": pstate.get("just_jumped", false)
		}
	
	# Do NOT include any snapshot or positional state in per-frame data.
	# Positional states (pilot/camera) are recorded in `frame_states` only at
	# SNAPSHOT_INTERVAL to avoid large per-frame payloads.
	
	# Ensure frame data is JSON-safe before storing
	var safe_frame = ReplayUtils.to_json_safe(frame_data)
	current_replay.frames.append(safe_frame)
	# Attach a 1-based frame index to the last appended frame for traceability
	var frame_index = current_replay.frames.size()
	var last_frame = current_replay.frames[frame_index - 1]
	last_frame["frame_index"] = frame_index
	last_frame_data = last_frame

	# Every SNAPSHOT_INTERVAL frames, capture debug snapshot and record positional states
	# var frame_index = len(current_replay.frames)
	if frame_index % SNAPSHOT_INTERVAL == 0:
		var debug_snapshot = {}
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			if not node.is_inside_tree():
				continue
			if node.has_method("get_replay_state"):
				debug_snapshot[node.name] = node.get_replay_state()

		# Record states for drift measurement (player and camera positions)
		var states = {}
		if player and player.is_inside_tree():
			states["player"] = player.get_replay_state()
		if camera_rig and camera_rig.has_method("get_replay_state") and camera_rig.is_inside_tree():
			states["camera"] = camera_rig.get_replay_state()
		# Attach the frame index to the snapshot entry so we know which frame it corresponds to
		states["frame_index"] = frame_index
		current_replay.frame_states.append(ReplayUtils.to_json_safe(states))
		_debug_log("Captured frame_states entry for frame_index=" + str(frame_index) + " entries=" + str(current_replay.frame_states.size()))


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
