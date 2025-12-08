extends Control

class_name Joystick

# --- Public Properties ---
# A flag to enable debug printing to the console.
var debug_mode = false

# If the joystick is receiving inputs.
var is_working := false

# The joystick output.
var output := Vector2.ZERO

# --- Exportable Properties ---
# FIXED: The joystick doesn't move.
# DYNAMIC: Every time the joystick area is pressed, the joystick position is set on the touched position.
# FOLLOWING: If the finger moves outside the joystick background, the joystick follows it.
enum JoystickMode {FIXED, DYNAMIC, FOLLOWING}
export(JoystickMode) var joystick_mode := JoystickMode.FIXED

# REAL: return a vector with a lenght beetween 0 (deadzone) and 1; useful for implementing different velocity or acceleration.
# NORMALIZED: return a normalized vector.
enum VectorMode {REAL, NORMALIZED}
export(VectorMode) var vector_mode := VectorMode.REAL

# The color of the button when the joystick is in use.
export(Color) var _pressed_color := Color.gray

# The number of directions, e.g. a D-pad is joystick with 4 directions, keep 0 for a free joystick.
export(int, 0, 12) var directions := 0

# It changes the angle of symmetry of the directions.
export var symmetry_angle := 90

#If the handle is inside this range, in proportion to the background size, the output is zero.
export(float, 0, 0.5) var dead_zone := 0.1

#The max distance the handle can reach, in proportion to the background size.
export(float, 0.5, 2) var clamp_zone := 1.0

#VISIBILITY_ALWAYS = Always visible.
#VISIBILITY_TOUCHSCREEN_ONLY = Visible on touch screens only.
enum VisibilityMode {ALWAYS , TOUCHSCREEN_ONLY }
export(VisibilityMode) var visibility_mode := VisibilityMode.ALWAYS

# --- Private Properties ---
onready var _background := $Background
onready var _handle := $Background/Handle
onready var _original_color : Color = _handle.self_modulate
onready var _original_position : Vector2 = _background.rect_position

var _touch_index :int = -1


func _ready() -> void:
	self.mouse_filter = MOUSE_FILTER_STOP
	if not OS.has_touchscreen_ui_hint() and visibility_mode == VisibilityMode.TOUCHSCREEN_ONLY:
		hide()

func _touch_started(event: InputEventScreenTouch) -> bool:
	return event.pressed and _touch_index == -1

func _touch_ended(event: InputEventScreenTouch) -> bool:
	return not event.pressed and _touch_index == event.index

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return

	# EXPERIMENTAL FIX: Instead of event.position, which seems to be in a wrong
	# coordinate space, get the position directly from the root viewport.
	var pointer_pos = get_viewport().get_mouse_position()

	# The joystick is on a CanvasLayer, so we transform the coordinate from
	# the root viewport space to the local canvas space.
	var transformed_pos = get_canvas_transform().affine_inverse().xform(pointer_pos)

	if debug_mode:
		print("Joystick '%s' input: %s | event_pos: %s | viewport_pos: %s | transformed_pos: %s" % [name, event.as_text().strip_edges(), event.position.round(), pointer_pos.round(), transformed_pos.round()])

	if event is InputEventScreenTouch:
		if _touch_started(event):
			# A new touch has started within the control's rect.
			# Accept the event immediately to stop it from propagating.
			accept_event()
			
			if (joystick_mode == JoystickMode.DYNAMIC or joystick_mode == JoystickMode.FOLLOWING):
				_center_control(_background, transformed_pos)
			
			# Activate the joystick if the touch is within the circular area.
			if _is_inside_control_circle(transformed_pos, _background):
				if debug_mode: print("  - Touch is INSIDE circle, activating joystick.")
				_touch_index = event.index
				_handle.self_modulate = _pressed_color
				_update_joystick(transformed_pos)
			else:
				if debug_mode: print("  - Touch is OUTSIDE circle, ignoring activation.")

		elif _touch_ended(event):
			if debug_mode: print("  - Touch ended. Resetting joystick.")
			_reset()
			accept_event()

	elif event is InputEventScreenDrag:
		if _touch_index == event.index:
			if debug_mode: print("  - Dragging joystick with correct touch_index.")
			_update_joystick(transformed_pos)
			accept_event()
		else:
			if debug_mode: print("  - Ignoring drag event, touch_index %s != event.index %s" % [_touch_index, event.index])

func _center_control(control: Control, new_global_position: Vector2) -> void:
	control.rect_global_position = new_global_position - (control.rect_size / 2)

func _reset_handle():
	_center_control(_handle, _background.rect_global_position + (_background.rect_size / 2))

func _reset():
	_touch_index = -1
	is_working = false
	output = Vector2.ZERO
	_handle.self_modulate = _original_color
	_background.rect_position = _original_position
	_reset_handle()

func _is_inside_control_rect(global_position: Vector2, control: Control) -> bool:
	var x: bool = global_position.x > control.rect_global_position.x and global_position.x < control.rect_global_position.x + (control.rect_size.x * control.rect_scale.x)
	var y: bool = global_position.y > control.rect_global_position.y and global_position.y < control.rect_global_position.y + (control.rect_size.y * control.rect_scale.y)
	return x and y

func _is_inside_control_circle(global_position: Vector2, control: Control) -> bool:
	var global_scale = control.get_global_transform().get_scale()
	var ray = control.rect_size.x * global_scale.x / 2
	var center := control.rect_global_position + Vector2(ray, ray)
	var ray_position := global_position - center
	var is_inside = ray_position.length_squared() < ray * ray
	
	if debug_mode:
		print("    - Circle Check: touch_pos=%s | circle_center=%s | ray=%s | is_inside=%s" % [global_position.round(), center.round(), stepify(ray, 0.01), is_inside])
	
	return is_inside

func _following(vector: Vector2):
	var clamp_size :float = clamp_zone * _background.rect_size.x / 2
	if vector.length() > clamp_size:
		var radius := vector.normalized() * clamp_size
		var delta := vector - radius
		var new_pos :Vector2 = _background.rect_position + delta
		new_pos.x = clamp(new_pos.x, -_background.rect_size.x / 2, rect_size.x - _background.rect_size.x / 2)
		new_pos.y = clamp(new_pos.y, -_background.rect_size.y / 2, rect_size.y - _background.rect_size.y / 2)
		_background.rect_position = new_pos

func _directional_vector(vector: Vector2, n_directions: int, _symmetry_angle := PI/2) -> Vector2:
	var angle := (vector.angle() + _symmetry_angle) / (PI / n_directions)
	angle = floor(angle) if angle >= 0 else ceil(angle)
	if abs(angle) as int % 2 == 1:
		angle = angle + 1 if angle >= 0 else angle - 1
	angle *= PI / n_directions
	angle -= _symmetry_angle
	return Vector2(cos(angle), sin(angle)) * vector.length()

func _update_joystick(event_position: Vector2):
	var global_scale = _background.get_global_transform().get_scale()
	var ray : float = _background.rect_size.x * global_scale.x / 2
	var dead_size := dead_zone * ray
	var clamp_size := clamp_zone * ray

	var center : Vector2 = _background.rect_global_position + Vector2(ray, ray)
	var vector : Vector2 = event_position - center

	if vector.length() > dead_size:
		if directions > 0:
			vector = _directional_vector(vector, directions, deg2rad(symmetry_angle))

		if vector_mode == VectorMode.NORMALIZED:
			output = vector.normalized()
			_center_control(_handle, output * clamp_size + center)
		elif vector_mode == VectorMode.REAL:
			var clamped_vector := vector.clamped(clamp_size)
			output = vector.normalized() * (clamped_vector.length() - dead_size) / (clamp_size - dead_size)
			_center_control(_handle, clamped_vector + center)

		is_working = true
		if joystick_mode == JoystickMode.FOLLOWING:
			_following(vector)
	else:
		is_working = false
		output = Vector2.ZERO
		_reset_handle()
