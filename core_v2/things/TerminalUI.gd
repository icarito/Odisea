extends Control
class_name TerminalUIV2

# TerminalUI.gd - Manages the terminal UI with projected cursor support
# The cursor is a sprite rendered inside the viewport, controlled by mouse delta

signal button_pressed(button_name)
signal key_pressed(event)

# Cursor configuration
export(Texture) var cursor_texture: Texture
export(Vector2) var cursor_hotspot := Vector2(7, 10) # Offset from cursor origin to click point
export(float) var cursor_sensitivity := 1.0

# Internal state
var _cursor_sprite: Sprite = null
var _cursor_position := Vector2()
var _ui_mode_active := false
var _viewport_size := Vector2()

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
	
	if active:
		# Center cursor when activating
		_viewport_size = get_viewport_rect().size
		_cursor_position = _viewport_size / 2.0
		_update_cursor_position()
		print("[TerminalUI] UI mode ACTIVATED, viewport size: ", _viewport_size)
	else:
		print("[TerminalUI] UI mode DEACTIVATED")

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
	_handle_click()

func _update_cursor_position():
	"""Update cursor sprite position."""
	if _cursor_sprite:
		_cursor_sprite.position = _cursor_position

func _handle_click():
	"""Process a click at the current cursor position."""
	# Find clickable control at cursor position
	var clicked_control = _find_control_at_position(_cursor_position)
	
	if clicked_control:
		# Emit signal for external handling
		if clicked_control.name:
			emit_signal("button_pressed", clicked_control.name)
		
		# Trigger button press if it's a Button
		if clicked_control is BaseButton:
			clicked_control.emit_signal("pressed")

func _find_control_at_position(pos: Vector2) -> Control:
	"""Find the topmost clickable control at the given position."""
	return _find_control_recursive(self, pos)

func _find_control_recursive(node: Node, pos: Vector2) -> Control:
	"""Recursively search for control under position (reverse child order = topmost first)."""
	# Check children in reverse order (last added = rendered on top)
	for i in range(node.get_child_count() - 1, -1, -1):
		var child = node.get_child(i)
		if child == _cursor_sprite:
			continue # Skip cursor itself
		
		var result = _find_control_recursive(child, pos)
		if result:
			return result
	
	# Check this node if it's a Control
	if node is Control and node != self:
		var control = node as Control
		if control.visible and _is_point_in_control(control, pos):
			# Check if it's clickable (Button, etc)
			if control is BaseButton:
				return control
	
	return null

func _is_point_in_control(control: Control, global_pos: Vector2) -> bool:
	"""Check if a point is within a control's rect."""
	var rect = control.get_global_rect()
	return rect.has_point(global_pos)

func get_cursor_position() -> Vector2:
	"""Get current cursor position for external use."""
	return _cursor_position

func set_cursor_position(pos: Vector2):
	"""Set cursor position programmatically."""
	_cursor_position = pos
	_update_cursor_position()


func process_key_event(event: InputEventKey):
	"""Process keyboard input forwarded from HoloTerminal in focus mode."""
	if not _ui_mode_active:
		return
	
	# Emit signal for custom handling by child controls
	emit_signal("key_pressed", event)
	
	# WASD navigation: move cursor in discrete steps
	if event.pressed:
		var cursor_step := 20.0
		match event.scancode:
			KEY_W, KEY_UP:
				_cursor_position.y -= cursor_step
			KEY_S, KEY_DOWN:
				_cursor_position.y += cursor_step
			KEY_A, KEY_LEFT:
				_cursor_position.x -= cursor_step
			KEY_D, KEY_RIGHT:
				_cursor_position.x += cursor_step
			KEY_ENTER, KEY_SPACE:
				# Simulate click at current cursor position
				_handle_click()
		
		# Clamp cursor after movement
		_cursor_position.x = clamp(_cursor_position.x, 0, _viewport_size.x)
		_cursor_position.y = clamp(_cursor_position.y, 0, _viewport_size.y)
		_update_cursor_position()


func _on_Button_pressed():
	print("Hello from terminal")
