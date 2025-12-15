extends Node

signal capture_changed(is_captured)

var is_captured := false

#--- JOYSTICK CONTROL ---
export (float, 0.0, 1.0) var joystick_deadzone = 0.02
export (float) var joystick_sensitivity = 650.0

enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL

var CURVE_RESOURCES = [
	load("res://data/Curves/Linear.tres"),
	load("res://data/Curves/Exponential.tres"),
	load("res://data/Curves/Inverse_S.tres")
]

var _joy_vector = Vector2.ZERO
#-------------------------

var cursor_sprite: Sprite
var canvas_layer: CanvasLayer

func _ready():
	var viewport = get_viewport()
	
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	cursor_sprite = Sprite.new()
	canvas_layer.add_child(cursor_sprite)
	
	cursor_sprite.position = viewport.size / 2
	
	get_viewport().connect("size_changed", self, "_on_viewport_size_changed")
	clamp_cursor_to_screen()
	
	# Start with mouse captured
	set_capture(true)

func _process(delta):
	_process_joystick_input(delta)

func _input(event):
	if event is InputEventMouseMotion:
		cursor_sprite.position = event.position
		clamp_cursor_to_screen()
	
	if event is InputEventScreenTouch:
		if event.pressed:
			cursor_sprite.position = event.position
			clamp_cursor_to_screen()
	elif event is InputEventScreenDrag:
		cursor_sprite.position = event.position
		clamp_cursor_to_screen()
	
	if event is InputEventJoypadButton:
		var mouse_button_index = 0
		if event.button_index == JOY_BUTTON_0: # 'A' button
			mouse_button_index = BUTTON_LEFT
		elif event.button_index == JOY_BUTTON_1: # 'B' button
			mouse_button_index = BUTTON_RIGHT
		
		if mouse_button_index != 0:
			var click_event = InputEventMouseButton.new()
			click_event.button_index = mouse_button_index
			click_event.pressed = event.is_pressed()
			click_event.position = cursor_sprite.position
			get_tree().input_event(click_event)

func _process_joystick_input(delta):
	_joy_vector.x = Input.get_action_strength("cursor_left") - Input.get_action_strength("cursor_right")
	_joy_vector.y = Input.get_action_strength("cursor_up") - Input.get_action_strength("cursor_down")
	
	if _joy_vector.length() < joystick_deadzone:
		return

	var processed_vector = _joy_vector.normalized()
	var curve: Curve = CURVE_RESOURCES[joystick_curve_type]
	var curve_val = curve.interpolate(_joy_vector.length())
	
	processed_vector *= curve_val * joystick_sensitivity * delta
	
	cursor_sprite.position += processed_vector
	clamp_cursor_to_screen()
	
	Input.warp_mouse_position(cursor_sprite.position)

func clamp_cursor_to_screen():
	var viewport_size = get_viewport().size
	cursor_sprite.position.x = clamp(cursor_sprite.position.x, 0, viewport_size.x)
	cursor_sprite.position.y = clamp(cursor_sprite.position.y, 0, viewport_size.y)

func _on_viewport_size_changed():
	clamp_cursor_to_screen()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# This is handled by ReplayManagementPanel when it is visible.
		# When it's not, ui_cancel toggles mouse capture.
		set_capture(!is_captured)
		get_tree().set_input_as_handled()

# --- Public API ---

func set_capture(capture: bool):
	if capture == is_captured:
		return
	
	is_captured = capture
	
	if is_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if cursor_sprite: cursor_sprite.hide()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		if cursor_sprite:
			cursor_sprite.show()
			if get_viewport():
				cursor_sprite.position = get_viewport().size / 2
			
	emit_signal("capture_changed", is_captured)

# Kept for compatibility with existing code that might use it
func show_cursor(show: bool):
	set_capture(!show)

# Kept for compatibility with existing code that might use it
func capture_mouse(capture: bool):
	set_capture(capture)