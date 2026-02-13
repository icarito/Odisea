extends Control
class_name TerminalUI

# TerminalUI.gd - Manages the terminal UI with projected cursor support
# The cursor is a sprite rendered inside the viewport, controlled by mouse delta


signal key_pressed(event)

# Cursor configuration
export(Texture) var cursor_texture: Texture
export(Vector2) var cursor_hotspot := Vector2(7, 10) # Offset from cursor origin to click point
export(float) var cursor_sensitivity := 1.0
export(Curve) var acceleration_curve: Curve
export(float) var acceleration_ramp_time := 2.0
export(float) var base_speed := 400.0

# Internal state
var _cursor_sprite: Sprite = null
var _cursor_position := Vector2()
var _ui_mode_active := false
var _viewport_size := Vector2()
var _input_duration := 0.0

func _ready():
	_setup_cursor()
	_viewport_size = get_viewport_rect().size
	# Center cursor initially
	_cursor_position = _viewport_size / 2.0
	set_process_input(false) # Disabled until UI mode activated

func _setup_cursor():
	"""Create and configure the cursor sprite."""
	_cursor_sprite = Sprite.new()
	_cursor_sprite.name = "HoloCursor"
	_cursor_sprite.centered = false
	_cursor_sprite.offset = - cursor_hotspot
	
	# Load cursor texture
	if cursor_texture:
		_cursor_sprite.texture = cursor_texture
	else:
		# Fallback: try to load default cursor
		var default_cursor = load("res://assets/cursor_none.svg")
		if default_cursor:
			_cursor_sprite.texture = default_cursor
	
	# Add cursor as top-level child (renders on top of everything)
	add_child(_cursor_sprite)
	_cursor_sprite.visible = false
	_cursor_sprite.z_index = 100 # Ensure on top

func set_ui_mode(active: bool):
	"""Enable or disable UI interaction mode."""
	if _ui_mode_active == active:
		return
	
	_ui_mode_active = active
	
	if _cursor_sprite:
		_cursor_sprite.visible = active
	
	set_process(active) # Enable analog stick processing
	if active:
		# Center cursor when activating
		_viewport_size = get_viewport_rect().size
		_cursor_position = _viewport_size / 2.0
		_update_cursor_position()
		_input_duration = 0.0 # Reset ramp
		print("[TerminalUI] UI mode ACTIVATED, viewport size: ", _viewport_size)
	else:
		print("[TerminalUI] UI mode DEACTIVATED")

func _process(delta: float):
	if not _ui_mode_active:
		set_process(false)
		return

	# Analog Stick / Directional Action Support
	# Uses "cursor_*" actions (mapped to Right Stick / Arrows) logic
	var input_dir = Vector2(
		Input.get_action_strength("cursor_right") - Input.get_action_strength("cursor_left"),
		Input.get_action_strength("cursor_down") - Input.get_action_strength("cursor_up")
	)

	if input_dir.length() > 0.1:
		# Ramp up acceleration
		_input_duration += delta
		var speed_multiplier = 1.0
		
		if acceleration_curve:
			var t = clamp(_input_duration / acceleration_ramp_time, 0.0, 1.0)
			speed_multiplier = acceleration_curve.interpolate(t)
			
		# Analog movement
		var speed = base_speed * cursor_sensitivity * speed_multiplier # Pixels per second
		
		if Input.is_key_pressed(KEY_SHIFT): # Optional fast cursor
			speed *= 2.0
			
		_cursor_position += input_dir * speed * delta
		
		# Clamp to viewport bounds
		_cursor_position.x = clamp(_cursor_position.x, 0, _viewport_size.x)
		_cursor_position.y = clamp(_cursor_position.y, 0, _viewport_size.y)
		_update_cursor_position()
	else:
		_input_duration = 0.0


func process_mouse_motion(relative: Vector2):
	"""Process mouse motion forwarded from HoloTerminal."""
	if not _ui_mode_active:
		return
	
	_cursor_position += relative * cursor_sensitivity
	# Clamp to viewport bounds
	_cursor_position.x = clamp(_cursor_position.x, 0, _viewport_size.x)
	_cursor_position.y = clamp(_cursor_position.y, 0, _viewport_size.y)
	_update_cursor_position()

func process_mouse_click():
	"""Process mouse click forwarded from HoloTerminal."""
	if not _ui_mode_active:
		return
	# Inject a full click (Press + Release) at the current position
	# This ensures standard Button 'pressed' signals are fired by the engine.
	_inject_mouse_button(_cursor_position, true)
	_inject_mouse_button(_cursor_position, false)
	
	# Optional: Keep _handle_click if custom signals are strictly needed,
	# but for standard UI behavior, injection is preferred.
	# _handle_click() 

func _update_cursor_position():
	"""Update cursor sprite position and inject mouse motion."""
	if _cursor_sprite:
		_cursor_sprite.position = _cursor_position
	
	# Inject motion event so UI controls detect hover
	_inject_mouse_motion(_cursor_position)


func _inject_mouse_motion(pos: Vector2):
	var evt = InputEventMouseMotion.new()
	evt.position = pos
	evt.global_position = pos # In SubViewport, global usually matches local
	get_viewport().input(evt)

func _inject_mouse_button(pos: Vector2, pressed: bool):
	var evt = InputEventMouseButton.new()
	evt.button_index = BUTTON_LEFT
	evt.pressed = pressed
	evt.position = pos
	evt.global_position = pos
	get_viewport().input(evt)

func process_key_event(event: InputEventKey):
	"""Process keyboard input forwarded from HoloTerminal in focus mode."""
	if not _ui_mode_active:
		return
	
	# Emit signal for custom handling by child controls (e.g. TextEdit)
	emit_signal("key_pressed", event)
	
	if event.is_action_pressed("ui_accept"):
		# Simulate click at current cursor position
		_inject_mouse_button(_cursor_position, true)
		_inject_mouse_button(_cursor_position, false)
