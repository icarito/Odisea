# scripts/multiplayer/PlayerInput.gd

extends Node

class_name PlayerInput

# ===== CONFIG =====
export var player_id := 1  # 1 o 2
export var deadzone := 0.5
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

var joypad_device := -1  # -1 = auto-detect, 0+ = específico
var mouse_motion := Vector2.ZERO # Almacenar movimiento relativo del mouse
var networked_inputs = {}
var _last_log_time := {
	"vector": 0.0,
	"sprint": 0.0,
	"jump": 0.0,
	"mouse": 0.0
}

func _unhandled_input(event: InputEvent) -> void:
	if player_id == 1 and event is InputEventMouseMotion:
		mouse_motion += event.relative
		if debug_input and mouse_motion.length_squared() > 0 and _can_log("mouse"):
			print("[PlayerInput P%d] mouse_motion: %s" % [player_id, mouse_motion])

func _ready() -> void:
	"""Inicializar input."""
	if player_id < 1 or player_id > 2:
		push_error("[PlayerInput] player_id inválido: %d" % player_id)
		return

	# Autodetectar joypad para P2
	if player_id == 2:
		joypad_device = 1  # Asumir que P2 usa joypad 2 (si existe)

	if debug_input:
		print("[PlayerInput] Inicializado para Player %d" % player_id)

func _can_log(type: String) -> bool:
	var now = OS.get_ticks_msec() / 1000.0
	if now - _last_log_time[type] > debug_interval:
		_last_log_time[type] = now
		return true
	return false

func get_input_vector() -> Vector2:
	"""Obtener vector de movimiento (normalizado)."""
	var actions = action_map[player_id]
	# Corregir orden para coincidir con la implementación de single-player (left-right, forward-backward)
	var vector = Input.get_vector(actions["right"], actions["left"], actions["backward"], actions["forward"])
	if debug_input and vector.length() > 0.01 and _can_log("vector"):
		print("[PlayerInput P%d] get_input_vector: %s" % [player_id, vector])
	return vector

func is_sprint_pressed() -> bool:
	"""Detectar si jugador presionó sprint."""
	var actions = action_map[player_id]
	var pressed = Input.is_action_pressed(actions["sprint"])
	if debug_input and pressed and _can_log("sprint"):
		print("[PlayerInput P%d] is_sprint_pressed: %s" % [player_id, pressed])
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

func set_inputs(inputs):
	networked_inputs = inputs

func get_input_vector() -> Vector2:
	if networked_inputs:
		var vector = Vector2.ZERO
		if networked_inputs.get("right"): vector.x += 1
		if networked_inputs.get("left"): vector.x -= 1
		if networked_inputs.get("backward"): vector.y += 1
		if networked_inputs.get("forward"): vector.y -= 1
		return vector.normalized()

	var actions = action_map[player_id]
	var vector = Input.get_vector(actions["right"], actions["left"], actions["backward"], actions["forward"])
	if debug_input and vector.length() > 0.01 and _can_log("vector"):
		print("[PlayerInput P%d] get_input_vector: %s" % [player_id, vector])
	return vector

func is_sprint_pressed() -> bool:
	if networked_inputs:
		return networked_inputs.get("sprint", false)

	var actions = action_map[player_id]
	var pressed = Input.is_action_pressed(actions["sprint"])
	if debug_input and pressed and _can_log("sprint"):
		print("[PlayerInput P%d] is_sprint_pressed: %s" % [player_id, pressed])
	return pressed

func just_jumped() -> bool:
	if networked_inputs:
		return networked_inputs.get("jump", false)

	var actions = action_map[player_id]
	var jumped = Input.is_action_just_pressed(actions["jump"])
	if debug_input and jumped and _can_log("jump"):
		print("[PlayerInput P%d] just_jumped: %s" % [player_id, jumped])
	return jumped
