extends Node

signal mouse_captured
signal mouse_released

#--- JOYSTICK CONTROL ---
export (float, 0.0, 1.0) var joystick_deadzone = 0.02
export (float) var joystick_sensitivity = 650.0

enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL

# This MUST be a var, not const, to avoid errors in Godot 3.5+
var CURVE_RESOURCES = [
	load("res://data/Curves/Linear.tres"),
	load("res://data/Curves/Exponential.tres"),
	load("res://data/Curves/Inverse_S.tres")
]

var _joy_vector = Vector2.ZERO
#-------------------------

var cursor_sprite: Sprite
var canvas_layer: CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var viewport = get_viewport()
	
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	cursor_sprite = Sprite.new()
	canvas_layer.add_child(cursor_sprite)
	
	cursor_sprite.position = viewport.size / 2
	
	get_viewport().connect("size_changed", self, "_on_viewport_size_changed")
	clamp_cursor_to_screen()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	_process_joystick_input(delta)

func _input(event):
	# If the real mouse moves, the virtual cursor follows.
	# We do this in _input() to capture the event BEFORE the UI consumes it.
	if event is InputEventMouseMotion:
		cursor_sprite.position = event.position
		clamp_cursor_to_screen()
	
	# Handle touch events for consistency on touch devices
	if event is InputEventScreenTouch:
		if event.pressed:
			cursor_sprite.position = event.position
			clamp_cursor_to_screen()
	elif event is InputEventScreenDrag:
		cursor_sprite.position = event.position
		clamp_cursor_to_screen()
	
	# Gestionar los clics de joystick (izquierdo y derecho)
	# Usamos _input() to que tenga prioridad sobre la UI.
	if event is InputEventJoypadButton:
		var mouse_button_index = 0
		# Mapeamos botones del joystick a botones del ratón.
		# Es mejor usar Input Actions para esto, pero por ahora usamos los índices.
		if event.button_index == JOY_BUTTON_0: # Botón A (normalmente)
			mouse_button_index = BUTTON_LEFT
		elif event.button_index == JOY_BUTTON_1: # Botón B (normalmente)
			mouse_button_index = BUTTON_RIGHT
		
		if mouse_button_index != 0:
			var click_event = InputEventMouseButton.new()
			click_event.button_index = mouse_button_index
			click_event.pressed = event.is_pressed()
			click_event.position = cursor_sprite.position
			get_tree().input_event(click_event)

func _process_joystick_input(delta):
	# We use Input Actions to make it configurable.
	# Inverted axes as requested.
	_joy_vector.x = Input.get_action_strength("cursor_left") - Input.get_action_strength("cursor_right")
	_joy_vector.y = Input.get_action_strength("cursor_up") - Input.get_action_strength("cursor_down")
	
	if _joy_vector.length() < joystick_deadzone:
		return

	var processed_vector = _joy_vector.normalized()
	# Get the selected curve from our loaded resources
	var curve: Curve = CURVE_RESOURCES[joystick_curve_type]
	# Apply the curve to the input magnitude
	var curve_val = curve.interpolate(_joy_vector.length())
	
	processed_vector *= curve_val * joystick_sensitivity * delta
	
	cursor_sprite.position += processed_vector
	clamp_cursor_to_screen()
	
	# 1. We warp only when the joystick is active.
	Input.warp_mouse_position(cursor_sprite.position)

func clamp_cursor_to_screen():
	# We clamp so that the center of the cursor can reach the edges.
	var viewport_size = get_viewport().size
	cursor_sprite.position.x = clamp(cursor_sprite.position.x, 0, viewport_size.x)
	cursor_sprite.position.y = clamp(cursor_sprite.position.y, 0, viewport_size.y)

func _on_viewport_size_changed():
	# When the window is resized, we make sure the cursor stays inside.
	clamp_cursor_to_screen()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Si el mouse está capturado, liberarlo.
		# Esto asegura que ESC siempre nos devuelva el cursor.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			capture_mouse(false)
			get_tree().set_input_as_handled()

func show_cursor(show: bool):
	if show:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor_sprite.hide()
	else:
		# Al ocultar el cursor, capturarlo para el juego.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		cursor_sprite.hide()



func capture_mouse(is_captured: bool):
	if is_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		cursor_sprite.hide()
		emit_signal("mouse_captured")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		cursor_sprite.show()
		emit_signal("mouse_released")
		# Centramos el cursor virtual cuando liberamos el mouse real
		# para que no aparezca en una esquina al volver a mostrarse.
		if get_viewport() != null:
			cursor_sprite.position = get_viewport().size / 2
