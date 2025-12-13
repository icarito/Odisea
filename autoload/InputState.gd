extends Node

# InputState.gd — Singleton global para gestión de input (LIVE/RECORD/PLAYBACK)
# No permite acceso directo a Input desde gameplay/cámara.

# Modos de operación
enum Mode { LIVE, RECORD, PLAYBACK }

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
	match mode:
		Mode.LIVE:
			_update_from_input()
		Mode.RECORD:
			_update_from_input()
			_record_current_frame()
		Mode.PLAYBACK:
			_apply_replay_frame()

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
	# Mouse delta
	mouse_delta = Input.get_last_mouse_speed()

func _record_current_frame():
	var frame = {
		"actions": actions.duplicate(),
		"axes": axes.duplicate(),
		"mouse_delta": mouse_delta
	}
	recorded_frames.append(frame)

func _apply_replay_frame():
	if replay_frame >= recorded_frames.size():
		return # Fin del replay
	var frame = recorded_frames[replay_frame]
	actions = frame["actions"].duplicate()
	axes = frame["axes"].duplicate()
	mouse_delta = frame["mouse_delta"]
	replay_frame += 1

# API pública para gameplay/cámara
func is_action_pressed(action):
	return bool(actions.get(action, false))

func get_axis(axis):
	return axes.get(axis, 0.0)

func get_mouse_delta():
	return mouse_delta

func start_recording():
	set_mode(Mode.RECORD)

func start_playback():
	set_mode(Mode.PLAYBACK)

func stop():
	set_mode(Mode.LIVE)
