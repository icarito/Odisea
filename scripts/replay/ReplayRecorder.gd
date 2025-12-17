extends Node

const ReplayScript = preload("res://scripts/replay/Replay.gd")

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
	if GameGlobals and GameGlobals.replay_debug_mode:
		print("[ReplayRecorder] " + message)

func _ready() -> void:
	process_priority = -10  # Low priority to run before CameraRig
	if not (GameGlobals and GameGlobals.is_replaying):  # Only enable input processing when not replaying
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
	if not is_recording():
		return

	# Preparar frame_data como en _record_frame
	if not current_replay:
		return
	if GameGlobals and GameGlobals.is_replaying:
		return  # No grabar durante reproducción

	var frame_data = {
		"delta": FIXED_DELTA,
		"inputs": InputState.actions.duplicate(),
		"axes": InputState.axes.duplicate(),
		# mouse_delta se sobrescribe abajo
		"mouse_delta": {},
		"strafing_active": InputState.is_strafing_mode_active,
		"strafing_timer": InputState.strafing_timer,
		"timestamp": Time.get_ticks_usec() - start_time
	}
	# LOG: Delta y estado crítico para debug determinista
	if player:
		print("[REPLAY][Record][Frame] idx=", len(current_replay.frames), " delta=", FIXED_DELTA, " pos=", player.global_transform.origin, " rot=", player.rotation, " vel=", player.velocity)

	# Snapshot cada frame para posición determinista y estado completo
	var snapshot = {}
	if player:
		# Estado completo del PlayerController, incluyendo jump_comp y flags críticos
		snapshot["player"] = player.get_replay_state()
		if "strafe_mode_active" in player:
			snapshot["strafe_mode_active"] = player.strafe_mode_active
		if "strafe_timer" in player:
			snapshot["strafe_timer"] = player.strafe_timer
		# DEBUG: Print variables clave del snapshot
		var dbg = snapshot["player"]
		print("[REPLAY][Snapshot][Debug] idx=", len(current_replay.frames), " pos=", player.global_transform.origin, " vel=", player.velocity, " coyote=", dbg["coyote_timer"] if "coyote_timer" in dbg else "-", " jump_buf=", dbg["jump_buffer_timer"] if "jump_buffer_timer" in dbg else "-", " should_jump_buf=", dbg["should_jump_buffered"] if "should_jump_buffered" in dbg else "-", " strafe=", player.strafe_mode_active if "strafe_mode_active" in player else "-", " strafe_timer=", player.strafe_timer if "strafe_timer" in player else "-")
	frame_data["snapshot"] = snapshot

	# Estado de cámara
	var camera = camera_rig
	if camera:
		var camera_yaw = camera.yaw.rotation.y
		var camera_pitch = camera.pitch.rotation.x
		var spring_length = camera.springarm.spring_length
		frame_data["camera"] = {"yaw": camera_yaw, "pitch": camera_pitch, "spring_length": spring_length}

	# Velocidad externa del jugador
	if player and player.external_velocity:
		frame_data["player_external_velocity"] = ReplayUtils.vector3_to_dict(player.external_velocity.velocity)

	# Gravedad override
	if player:
		var grav = player.get("gravity_override")
		if grav == null:
			grav = Vector3(0, -9.8, 0)
		frame_data["player_gravity_override"] = ReplayUtils.vector3_to_dict(grav)

	# 1. Capturar el mouse acumulado
	frame_data["mouse_delta"] = ReplayUtils.vector2_to_dict(mouse_motion_accumulated)
	# 2. Resetear el acumulador
	mouse_motion_accumulated = Vector2.ZERO

	# 3. Guardar el frame
	current_replay.frames.append(frame_data)
	last_frame_data = frame_data

	# Snapshots de debug
	if len(current_replay.frames) % SNAPSHOT_INTERVAL == 0:
		var debug_snapshot = {}
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			if node.has_method("get_replay_state"):
				debug_snapshot[node.get_path()] = node.get_replay_state()
		current_replay.snapshots[str(len(current_replay.frames))] = debug_snapshot

	# Estados para drift
	var states = {}
	if player:
		states[get_tree().current_scene.get_path_to(player)] = player.get_replay_state()
	if camera_rig and camera_rig.has_method("get_replay_state"):
		states[get_tree().current_scene.get_path_to(camera_rig)] = camera_rig.get_replay_state()
	current_replay.frame_states.append(states)

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

	player = PlayerManager.get_player()
	var initial = {}
	if player and get_tree() and get_tree().current_scene:
		initial[get_tree().current_scene.get_path_to(player)] = player.get_replay_state()
	
	# Add CameraRig state (guardar rotación inicial exacta)
	if get_tree() and get_tree().current_scene:
		camera_rig = get_tree().current_scene.find_node("CameraRig", true, false)
		if camera_rig and camera_rig.has_method("get_replay_state"):
			# Forzar snapshot de yaw/pitch actuales
			var cam_state = camera_rig.get_replay_state()
			initial[get_tree().current_scene.get_path_to(camera_rig)] = cam_state
	
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
	# _debug_log("Start of _record_frame: mouse_motion_this_frame = " + str(mouse_motion_this_frame))
	if not current_replay:
		return
	if GameGlobals and GameGlobals.is_replaying:
		return  # Do not record during replay playback

	var frame_data = {
		"delta": FIXED_DELTA,
		"inputs": InputState.actions.duplicate(),
		"axes": InputState.axes.duplicate(),
		"mouse_delta": {"x": InputState.recorded_mouse_delta.x, "y": InputState.recorded_mouse_delta.y},
		"strafing_active": InputState.is_strafing_mode_active,
		"strafing_timer": InputState.strafing_timer,
		"timestamp": Time.get_ticks_usec() - start_time
	}
	
	# Snapshot every frame for deterministic position
	var snapshot = {}
	if player:
		snapshot["player"] = player.get_replay_state()
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
	
	current_replay.frames.append(frame_data)
	last_frame_data = frame_data
	
	# Record sparse snapshots for debugging
	if len(current_replay.frames) % SNAPSHOT_INTERVAL == 0:
		var debug_snapshot = {}
		for node in get_tree().get_nodes_in_group(REPLAY_GROUP):
			if node.has_method("get_replay_state"):
				debug_snapshot[node.get_path()] = node.get_replay_state()
		current_replay.snapshots[str(len(current_replay.frames))] = debug_snapshot
	
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
