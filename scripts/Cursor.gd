extends Sprite

export var debug = false

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

# Called when the node enters the scene tree for the first time.
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var viewport = get_viewport()
	position = viewport.size / 2
	
	get_viewport().connect("size_changed", self, "_on_viewport_size_changed")
	clamp_cursor_to_screen()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	_process_joystick_input(delta)
	# If debug mode is active, request a redraw to show our debug point.
	if debug:
		update()


# Called whenever the node needs to be redrawn (when we call update())
func _draw():
	# If debug mode is active, draw the red dot.
	if debug:
		# Draws a small red circle at the exact position of the virtual cursor.
		draw_circle(Vector2.ZERO, 3, Color.red)


func _input(event):
	# If the real mouse moves, the virtual cursor follows.
	# We do this in _input() to capture the event BEFORE the UI consumes it.
	if event is InputEventMouseMotion:
		position = event.position
		clamp_cursor_to_screen()
	
	# Handle joystick clicks (left and right) using Input Actions for flexibility.
	# We check for the actions themselves, which works for both press and release events.
	if event.is_action("cursor_click_primary") or event.is_action("cursor_click_secondary"):
		var mouse_button_index = 0
		if event.is_action("cursor_click_primary"):
			mouse_button_index = BUTTON_LEFT
		else: # It must be the secondary action
			mouse_button_index = BUTTON_RIGHT
		
		# Create a new mouse button event and dispatch it
		var click_event = InputEventMouseButton.new()
		click_event.button_index = mouse_button_index
		click_event.pressed = event.is_pressed()
		click_event.position = position
		get_tree().input_event(click_event)
		
		# We accept the event to prevent it from being processed further,
		# avoiding potential double inputs if the same button is mapped elsewhere.
		get_tree().set_input_as_handled()


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
	
	position += processed_vector
	clamp_cursor_to_screen()
	
	# 1. We warp only when the joystick is active.
	Input.warp_mouse_position(position)

func clamp_cursor_to_screen():
	# We clamp so that the center of the cursor can reach the edges.
	var viewport_size = get_viewport().size
	position.x = clamp(position.x, 0, viewport_size.x)
	position.y = clamp(position.y, 0, viewport_size.y)

func _on_viewport_size_changed():
	# When the window is resized, we make sure the cursor stays inside.
	clamp_cursor_to_screen()
