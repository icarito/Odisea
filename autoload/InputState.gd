extends Node

# InputState.gd — Singleton global para gestión de input (LIVE/RECORD/PLAYBACK)
# No permite acceso directo a Input desde gameplay/cámara.

# Modos de operación
enum Mode { LIVE, RECORD, PLAYBACK }

var paused: bool = false

# Acciones lógicas (rellenar según necesidades del juego)
var actions = {
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
var axes = {
	"move_x": 0.0,
	"move_y": 0.0
}

# Mouse delta (para cámara)
var mouse_delta = Vector2.ZERO
var _mouse_motion_this_frame = Vector2.ZERO
var recorded_mouse_delta = Vector2.ZERO

# Estado de strafing
var is_strafing_mode_active = false
var strafing_timer = 0.0

var mode = Mode.LIVE setget set_mode

# Frame actual de replay (solo en playback/record)
var replay_frame = 0

# Buffer de frames grabados (solo en record/playback)
var recorded_frames = []

func set_mode(new_mode):
	mode = new_mode
	if mode == Mode.LIVE:
		recorded_frames.clear()
		replay_frame = 0

func _physics_process(delta):
	if mode == Mode.LIVE or mode == Mode.RECORD:
		mouse_delta = _mouse_motion_this_frame
		recorded_mouse_delta = mouse_delta
		# _mouse_motion_this_frame is now cleared at the end of the function

		# --- Deterministic Strafing Mode Logic ---
		# 1. Activation: If there's mouse movement AND directional input, activate strafe mode.
		var has_input = abs(get_axis("move_x")) > 0.1 or abs(get_axis("move_y")) > 0.1
		if mouse_delta.length_squared() > 0.001 and has_input:
			is_strafing_mode_active = true
			strafing_timer = 2.0 # Reset timer

		# 2. Persistence: If strafe mode is active, countdown the timer.
		# This part runs regardless of mouse input in the current frame.
		if is_strafing_mode_active:
			strafing_timer -= delta
			if strafing_timer <= 0.0:
				is_strafing_mode_active = false
				strafing_timer = 0.0

	match mode:
		Mode.LIVE:
			_update_from_input()
		Mode.RECORD:
			_update_from_input()
			_record_current_frame()
		Mode.PLAYBACK:
			if not paused:
				_apply_replay_frame()
	
	_mouse_motion_this_frame = Vector2.ZERO

func _update_from_input():
	# Mapear acciones lógicas
	actions["move_forward"] = Input.is_action_pressed("move_forward")
	actions["move_back"] = Input.is_action_pressed("move_back")
	actions["move_left"] = Input.is_action_pressed("move_left")
	actions["move_right"] = Input.is_action_pressed("move_right")
	actions["jump"] = Input.is_action_pressed("jump")
	actions["run"] = Input.is_action_pressed("run")
	actions["crouch"] = Input.is_action_pressed("crouch")
	actions["interact"] = Input.is_action_pressed("interact")
	actions["roll"] = Input.is_action_pressed("roll")
	actions["attack"] = Input.is_action_pressed("attack")
	actions["aim"] = Input.is_action_pressed("aim")
	# Ejes analógicos (ejemplo WASD)
	axes["move_x"] = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	axes["move_y"] = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	# Mouse delta is now handled in _input and _physics_process


func _record_current_frame():
	var frame = {
		"inputs": actions.duplicate(),
		"axes": axes.duplicate(),
		"mouse_delta": mouse_delta,
		"strafing_active": is_strafing_mode_active,
		"strafing_timer": strafing_timer
	}
	recorded_frames.append(frame)

func _apply_replay_frame():
	if replay_frame >= recorded_frames.size():
		return # Fin del replay
	var frame = recorded_frames[replay_frame]
	actions = frame["inputs"].duplicate()
	axes = frame["axes"].duplicate()
	var md = frame.get("mouse_delta", {"x": 0.0, "y": 0.0})
	if md is Dictionary:
		mouse_delta = Vector2(md.get("x", 0.0), md.get("y", 0.0))
	else:
		mouse_delta = md
	recorded_mouse_delta = mouse_delta
	is_strafing_mode_active = frame.get("strafing_active", false)
	strafing_timer = frame.get("strafing_timer", 0.0)
	replay_frame += 1

# API pública para gameplay/cámara
func is_action_pressed(action):
	return bool(actions.get(action, false))

func get_axis(axis):
	return axes.get(axis, 0.0)

func get_mouse_delta():
	return mouse_delta

func get_live_mouse_delta() -> Vector2:
	return _mouse_motion_this_frame

func start_recording():
	set_mode(Mode.RECORD)

func start_playback():
	set_mode(Mode.PLAYBACK)

func stop():
	set_mode(Mode.LIVE)

func _input(event):
	if event is InputEventMouseMotion:
		_mouse_motion_this_frame += event.relative
