# scripts/multiplayer/PlayerInput.gd

extends Node

class_name PlayerInput

# ===== CONFIG =====
export var use_mouse_input := true
export var player_id := 1  # 1 o 2
export var analog_sprint_threshold := 0.9
export var debug_input := true
export var debug_interval := 0.5 # Time in seconds between log messages

# ===== MAPEO DE ACCIONES =====
var action_map = {
	1: {  # Player 1
		"left": "left",
		"right": "right",
		"forward": "forward",
		"backward": "backward",
		"jump": "jump",
		"sprint": "sprint"
	},
	2: {  # Player 2
		"left": "left_2",
		"right": "right_2",
		"forward": "forward_2",
		"backward": "backward_2",
		"jump": "jump_2",		"sprint": "sprint_2"
	}
}

var joypad_device := 0  # 0 para P1, 1 para P2
var mouse_motion := Vector2.ZERO # Almacenar movimiento relativo del mouse
var _last_log_time := {
	"vector": 0.0,
	"sprint": 0.0,
	"jump": 0.0,
	"mouse": 0.0
}
var _last_joy_vector := Vector2.ZERO


func initialize(p_use_mouse_input: bool, p_joypad_device: int) -> void:
	"""
	Inicializa el nodo de input. Debe ser llamado explícitamente desde el
	manager que lo crea, después de haber asignado el player_id.
	"""
	self.use_mouse_input = p_use_mouse_input
	self.joypad_device = p_joypad_device

	if player_id < 1 or player_id > 2:
		push_error("[PlayerInput] player_id inválido: %d" % player_id)
		return

	if debug_input:
		print("[PlayerInput] Inicializado para Player %d. Asignado joypad_device: %d" % [player_id, self.joypad_device])

func _can_log(type: String) -> bool:
	var now = OS.get_ticks_msec() / 1000.0
	if now - _last_log_time[type] > debug_interval:
		_last_log_time[type] = now
		return true
	return false

func get_input_vector() -> Vector2:
	"""Obtener vector de movimiento (normalizado)."""
	var actions = action_map[player_id]
	
	# Input de teclado
	var keyboard_vector = Input.get_vector(actions["right"], actions["left"], actions["backward"], actions["forward"])
	
	var joy_vector := Vector2.ZERO
	# Solo leer el joystick si el dispositivo no está explícitamente deshabilitado (-1)
	if joypad_device != -1:
		# Input de Joystick (eje izquierdo)
		var joy_x = -Input.get_joy_axis(joypad_device, JOY_AXIS_0) # Eje X izquierdo
		var joy_y = -Input.get_joy_axis(joypad_device, JOY_AXIS_1) # Eje Y izquierdo
		joy_vector = Vector2(joy_x, joy_y)

	_last_joy_vector = joy_vector # Guardar para la lógica de sprint

	# Combinar: dar prioridad al que tenga mayor magnitud
	if keyboard_vector.length_squared() > joy_vector.length_squared():
		if debug_input and keyboard_vector.length() > 0.01 and _can_log("vector"):
			print("[PlayerInput P%d] get_input_vector (KB): %s" % [player_id, keyboard_vector])
		return keyboard_vector
	else:
		if debug_input and joy_vector.length() > 0.01 and _can_log("vector"):
			print("[PlayerInput P%d] get_input_vector (Joy): %s" % [player_id, joy_vector])
		return joy_vector

func is_sprint_pressed() -> bool:
	"""Detectar si jugador presionó sprint."""
	var actions = action_map[player_id]
	var pressed = Input.is_action_pressed(actions["sprint"]) or (_last_joy_vector.length() > analog_sprint_threshold)
	if debug_input and pressed and _can_log("sprint"):
		print("[PlayerInput P%d] is_sprint_pressed: %s (Joy Mag: %.2f)" % [player_id, pressed, _last_joy_vector.length()])
	return pressed

func just_jumped() -> bool:
	"""Detectar salto ESTE FRAME."""
	var actions = action_map[player_id]
	var jumped = Input.is_action_just_pressed(actions["jump"])
	if debug_input and jumped and _can_log("jump"):
		print("[PlayerInput P%d] just_jumped: %s" % [player_id, jumped])
	return jumped

func get_mouse_motion() -> Vector2:
	"""Obtener el movimiento acumulado del mouse y resetearlo."""
	var motion = mouse_motion
	mouse_motion = Vector2.ZERO
	return motion
