extends Node

# InputState.gd — Singleton global para gestión de input (LIVE/RECORD/PLAYBACK)
# No permite acceso directo a Input desde gameplay/cámara.

# Modos de operación
enum Mode { LIVE, RECORD, PLAYBACK }

var paused: bool = false

# Acciones lógicas (rellenar según necesidades del juego)
var actions := {
	"move_forward": false,
	"move_back": false,
	"move_left": false,
	"move_right": false,
	"jump": false,
	"run": false,
	"crouch": false,
	"interact": false,
	"roll": false,
	"attack": false,
	"aim": false
}

# Ejes analógicos (ejemplo: para sticks o mouse)
var axes := {
	"move_x": 0.0,
	"move_y": 0.0
}

# Master key lists used for recording to ensure missing keys default to safe values
const ACTION_KEYS = ["move_forward","move_back","move_left","move_right","jump","run","crouch","interact","roll","attack","aim"]
const AXIS_KEYS = ["move_x","move_y"]

# Mouse delta (para cámara)
var mouse_delta = Vector2.ZERO
var _mouse_motion_this_frame = Vector2.ZERO
var recorded_mouse_delta = Vector2.ZERO

# Estado de strafing
var is_strafing_mode_active = false
var strafing_timer = 0.0

var mode: int = Mode.LIVE setget set_mode

# Fixed delta for deterministic replay
const FIXED_DELTA = 1.0 / 60.0

# Frame actual de replay (solo en playback/record)
var replay_frame = 0

# Buffer de frames grabados (solo en record/playback)
var recorded_frames := []

# Fallback tracking de posición del ratón para entornos donde
# InputEventMouseMotion no se entrega al singleton.
var _last_mouse_position := Vector2.ZERO

# Flag para modo manual (usado en tests para inyección directa)
var manual_playback: bool = false

# Máximo mouse delta (en píxeles) aceptable desde frames de replay para evitar picos
const MAX_REPLAY_MOUSE_DELTA = 100.0


func set_mode(new_mode: int) -> void:
	mode = new_mode
	reset()
	# Ensure the InputState receives physics ticks when recording, playing back, or in live for strafe
	if mode == Mode.RECORD or mode == Mode.PLAYBACK or mode == Mode.LIVE:
		set_physics_process(true)
		# Also enable input processing so _input receives InputEvent callbacks
		set_process_input(true)
	else:
		set_physics_process(false)
		set_process_input(false)

	# If switching to playback, clear any accumulated mouse motion to avoid
	# hardware artefacts contaminating the recorded deltas.
	if mode == Mode.PLAYBACK:
		_mouse_motion_this_frame = Vector2.ZERO
		mouse_delta = Vector2.ZERO

# --- RESET DE ESTADO COMPLETO ---

func reset():
	for k in actions.keys():
		actions[k] = false
	for k in axes.keys():
		axes[k] = 0.0
	mouse_delta = Vector2.ZERO
	recorded_mouse_delta = Vector2.ZERO
	_mouse_motion_this_frame = Vector2.ZERO
	is_strafing_mode_active = false
	strafing_timer = 0.0
	replay_frame = 0
	recorded_frames.clear()
	_virtual_joystick_vector = Vector2.ZERO


func _physics_process(_delta):
	if mode == Mode.PLAYBACK:
		# Clear any accumulated live mouse motion before applying the recorded frame
		# to guarantee the recorded camera deltas are authoritative.
		_mouse_motion_this_frame = Vector2.ZERO
		# Removed: mouse_delta = Vector2.ZERO  # Don't reset during playback, as it's set from recorded frames
		if not paused and not manual_playback:
			_apply_replay_frame()
		# En playback, no procesar lógica de input real ni de strafing
		return

	match mode:
		Mode.LIVE:
			_update_from_input()
		Mode.RECORD:
			if not manual_playback:
				_update_from_input()
				_record_current_frame()

	if mode == Mode.LIVE or mode == Mode.RECORD:
		# Prefer accumulated events, but fall back to a safe mouse-position delta
		var live_delta = _mouse_motion_this_frame
		if live_delta == Vector2.ZERO:
			# Fallback: compute delta using Input.get_mouse_position() if available.
			# Protect calls that may not exist in some embedded runtimes.
			if Input.has_method("get_mouse_position"):
				var current_pos = Input.get_mouse_position()
				# Initialize _last_mouse_position on first use to avoid huge spikes
				if _last_mouse_position == Vector2.ZERO:
					_last_mouse_position = current_pos
				var os_delta = current_pos - _last_mouse_position
				_last_mouse_position = current_pos
				if os_delta != Vector2.ZERO:
					# Clamp large deltas to avoid spikes from alt-tab or focus changes
					if os_delta.length() > MAX_REPLAY_MOUSE_DELTA:
						os_delta = os_delta.normalized() * MAX_REPLAY_MOUSE_DELTA
					live_delta = os_delta
			# If Input.get_mouse_position() is unavailable, silently skip fallback
		mouse_delta = live_delta
		recorded_mouse_delta = mouse_delta

		# --- Deterministic Strafing Mode Logic (solo LIVE/RECORD) ---
		# 1. Activation: If there's mouse movement, activate strafe mode.
		if mouse_delta.length_squared() > 0.001:
			if not is_strafing_mode_active:
				is_strafing_mode_active = true
				strafing_timer = 5.0 # Reset timer
				print("[InputState LIVE] Strafe ACTIVATED. mouse_delta=", mouse_delta, " timer=", strafing_timer)

		# 2. Persistence: If strafe mode is active, countdown the timer.
		if is_strafing_mode_active:
			strafing_timer -= FIXED_DELTA
			if strafing_timer <= 0.0:
				is_strafing_mode_active = false
				strafing_timer = 0.0
				print("[InputState LIVE] Strafe DEACTIVATED (timer). mouse_delta=", mouse_delta, " timer=", strafing_timer)

		# Debug trace each physics frame for strafe/mouse state (keep minimal)
		if OS.has_feature("debug"):
			print("[InputState LIVE][FRAME] mouse_delta=", mouse_delta, " strafing=", is_strafing_mode_active, " timer=", strafing_timer)

		# Consume/clear any accumulated raw mouse motion for this frame so it
		# doesn't keep growing if other systems only peek at the value.
		_mouse_motion_this_frame = Vector2.ZERO

# Permite a los tests avanzar el replay manualmente cuando manual_playback es true
func step_replay_frame():
	if mode == Mode.PLAYBACK and manual_playback and not paused:
		_apply_replay_frame()

	_mouse_motion_this_frame = Vector2.ZERO

var _virtual_joystick_vector := Vector2.ZERO

func _update_from_input():
	# Mapear acciones lógicas
	actions["move_forward"] = Input.is_action_pressed("move_forward")
	actions["move_back"] = Input.is_action_pressed("move_back")
	actions["move_left"] = Input.is_action_pressed("move_left")
	actions["move_right"] = Input.is_action_pressed("move_right")
	actions["jump"] = Input.is_action_pressed("jump")
	actions["crouch"] = Input.is_action_pressed("crouch")
	actions["interact"] = Input.is_action_pressed("interact")
	actions["roll"] = Input.is_action_pressed("roll")
	actions["attack"] = Input.is_action_pressed("attack")
	actions["aim"] = Input.is_action_pressed("aim")

	# --- AXES INPUT (KEYBOARD, PHYSICAL & VIRTUAL JOYSTICK) ---
	# 1. Get keyboard vector
	var keyboard_vec = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	)

	# 2. Get physical joystick vector (device 0)
	var joy_vec = Vector2(
		Input.get_joy_axis(0, JOY_AXIS_0), # X-axis
		-Input.get_joy_axis(0, JOY_AXIS_1)  # Y-axis invertido SOLO para joystick físico
	)
	
	# 3. Use the vector with the greatest magnitude (keyboard, physical joy, or virtual joy)
	# El joystick virtual emite la Y invertida, así que lo invertimos aquí para unificar el sistema.
	var virtual_vec = Vector2(_virtual_joystick_vector.x, -_virtual_joystick_vector.y)
	var final_vec = Vector2.ZERO # Initialize to zero
	var input_source = ""

	# Determine the dominant input source and its vector
	if keyboard_vec.length_squared() > final_vec.length_squared():
		final_vec = keyboard_vec
		input_source = "keyboard"

	if joy_vec.length_squared() > final_vec.length_squared():
		final_vec = joy_vec
		input_source = "physical_joy"
	
	if virtual_vec.length_squared() > final_vec.length_squared():
		final_vec = virtual_vec
		input_source = "virtual_joy"

	axes["move_x"] = final_vec.x
	axes["move_y"] = final_vec.y
	
	if input_source == "keyboard":
		actions["run"] = Input.is_action_pressed("run")
	else: # It's a joystick (physical or virtual)
		actions["run"] = Input.is_action_pressed("run") or final_vec.length() > 0.8

	# Mouse delta is now handled in _input and _physics_process

# Public API for virtual joystick to send its data
func set_virtual_joystick_vector(vector: Vector2):
	_virtual_joystick_vector = vector

func reset_virtual_joystick():
	_virtual_joystick_vector = Vector2.ZERO



func _record_current_frame():
	var pilot = PlayerManager.player_reference
	if not pilot or not is_instance_valid(pilot):
		return
	# Only record controller/input state per-frame. Positional and camera
	# states are recorded by the ReplayRecorder at snapshot intervals into
	# `frame_states` to avoid large per-frame payloads.
	# Build a complete inputs dict using ACTION_KEYS so tests that replace
	# `actions` with a sparse dict still result in a full snapshot.
	var inputs_snapshot = {}
	for k in ACTION_KEYS:
		inputs_snapshot[k] = bool(actions.get(k, false))

	# Build a complete axes dict using AXIS_KEYS
	var axes_snapshot = {}
	for k in AXIS_KEYS:
		axes_snapshot[k] = float(axes.get(k, 0.0))

	# --- SINCRONIZACIÓN DE ESTADO FÍSICO ---
	# Grabar el estado 'is_on_floor' para forzar la tracción en el replay.
	var on_floor = false
	if pilot and pilot.has_method("is_on_floor"):
		on_floor = pilot.is_on_floor()

	# --- SINCRONIZACIÓN DE ÁNGULO ABSOLUTO ---
	# Grabar el yaw y pitch absolutos de la cámara en cada frame.
	var cam_yaw = 0.0
	var cam_pitch = 0.0
	var cam_rig = get_tree().current_scene.find_node("CameraRig", true, false) if get_tree().current_scene else null
	if cam_rig and cam_rig.has_method("get_replay_state"):
		var cam_state = cam_rig.get_replay_state()
		cam_yaw = cam_state.get("yaw", 0.0)
		cam_pitch = cam_state.get("pitch", 0.0)

	var frame = {
		"inputs": inputs_snapshot,
		"axes": axes_snapshot,
		"mouse_delta": recorded_mouse_delta,
		"strafing_active": is_strafing_mode_active,
		"strafing_timer": strafing_timer,
		"camera_yaw": cam_yaw,
		"camera_pitch": cam_pitch
	}
	recorded_frames.append(frame)
	if recorded_frames.size() % 10 == 0:
		print("[InputState][RECORD] Frame=", recorded_frames.size() - 1,
			" inputs=", inputs_snapshot,
			" axes=", axes_snapshot,
			" mouse_delta=", recorded_mouse_delta,
			" strafe=", is_strafing_mode_active)

func _apply_replay_frame():
	if replay_frame >= recorded_frames.size():
		return # Fin del replay
	var frame = recorded_frames[replay_frame]
	actions = frame["inputs"].duplicate()
	axes = frame["axes"].duplicate()
	var md = frame.get("mouse_delta", {"x": 0, "y": 0})
	# Use the recorded mouse_delta even on the first playback frame.
	# The ReplayPlayback will restore the camera's initial transform/state
	# to avoid jumps caused by immediate delta application.
	if md is String:
		mouse_delta = str2var("Vector2" + md)
	else:
		mouse_delta = Vector2(FixedPoint.from_fixed(md.get("x", 0)), FixedPoint.from_fixed(md.get("y", 0)))
	recorded_mouse_delta = mouse_delta
	is_strafing_mode_active = frame.get("strafing_active", false)
	strafing_timer = frame.get("strafing_timer", 0.0)
	print("[InputState][PLAYBACK] Frame=", replay_frame, " actions=", actions, " axes=", axes, " mouse_delta=", mouse_delta, " strafe=", is_strafing_mode_active)
	replay_frame += 1

# API pública para gameplay/cámara
func is_action_pressed(action):
	if mode == Mode.PLAYBACK:
		return bool(actions.get(action, false))
	else:
		return bool(actions.get(action, false))

func get_axis(axis):
	if mode == Mode.PLAYBACK:
		return axes.get(axis, 0.0)
	else:
		return axes.get(axis, 0.0)

func get_mouse_delta():
	if mode == Mode.PLAYBACK:
		return mouse_delta
	else:
		return mouse_delta

func get_live_mouse_delta() -> Vector2:
	var delta = _mouse_motion_this_frame
	# Consuming getter (used by some callers). Keep for compatibility.
	_mouse_motion_this_frame = Vector2.ZERO
	return delta

# Peek current accumulated mouse motion without clearing it.
func peek_mouse_motion() -> Vector2:
	return _mouse_motion_this_frame

func clean_mouse_delta_y():
	mouse_delta.y = 0.0

func clean_mouse_delta_x():
	mouse_delta.x = 0.0

func start_recording():
	set_mode(Mode.RECORD)

func start_playback():
	set_mode(Mode.PLAYBACK)

func load_replay(replay_data: Array):
	# Switch to PLAYBACK mode first (this calls reset()), then set the frames
	set_mode(Mode.PLAYBACK)
	recorded_frames = replay_data.duplicate()
	replay_frame = 0
	print("load_replay set replay_frame to 0")

func stop():
	set_mode(Mode.LIVE)

func _input(event):
	# Ignore real OS mouse input during replay playback to avoid double-application
	if typeof(GameGlobals) != TYPE_NIL and GameGlobals and GameGlobals.is_replaying:
		return
	if mode == Mode.PLAYBACK:
		# In playback mode we should not accept live mouse motion
		return
	if event is InputEventMouseMotion:
		_mouse_motion_this_frame += event.relative
		if OS.has_feature("debug"):
			print("[InputState._input] MouseMotion received: rel=", event.relative, " _mouse_motion_this_frame=", _mouse_motion_this_frame)
	elif event is InputEventScreenDrag:
		_mouse_motion_this_frame += event.relative
		if OS.has_feature("debug"):
			print("[InputState._input] ScreenDrag received: rel=", event.relative, " _mouse_motion_this_frame=", _mouse_motion_this_frame)


func notify_mouse_motion(delta: Vector2) -> void:
	# Called by camera/controllers that already saw mouse motion
	# Ensure InputState tracks it for strafing logic and recording
	if not (delta is Vector2):
		return
	_mouse_motion_this_frame += delta
	if delta.length_squared() > 0.0:
		is_strafing_mode_active = true
		strafing_timer = 5.0
		# Also record a trace for debugging
		print("[InputState] notify_mouse_motion called ->", delta, " strafing_timer=", strafing_timer)
