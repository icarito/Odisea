extends Viewport

export(float) var cursor_sensitivity := 1.0

var _ui_mode_active := false
var _cursor_position := Vector2.ZERO

func _ready() -> void:
	_cursor_position = get_visible_rect().size * 0.5

func set_ui_mode(active: bool) -> void:
	_ui_mode_active = active
	if active:
		_cursor_position = get_visible_rect().size * 0.5
		call_deferred("focus_command_input")

func process_mouse_motion(relative: Vector2) -> void:
	if not _ui_mode_active:
		return
	_cursor_position += relative * cursor_sensitivity
	var size = get_visible_rect().size
	_cursor_position.x = clamp(_cursor_position.x, 0.0, size.x)
	_cursor_position.y = clamp(_cursor_position.y, 0.0, size.y)

	var evt = InputEventMouseMotion.new()
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	evt.relative = relative * cursor_sensitivity
	input(evt)

func process_mouse_click(button_index: int = BUTTON_LEFT, pressed: bool = true) -> void:
	if not _ui_mode_active:
		return
	var evt = InputEventMouseButton.new()
	evt.button_index = button_index
	evt.pressed = pressed
	evt.position = _cursor_position
	evt.global_position = _cursor_position
	input(evt)

func process_key_event(event: InputEventKey) -> void:
	if not _ui_mode_active:
		return
	if not event.pressed or event.echo:
		return
	focus_command_input()
	input(event)

func focus_command_input() -> void:
	var shell = find_node("OYSShell", true, false)
	if shell and shell.has_method("focus_command_input"):
		shell.call_deferred("focus_command_input")
		return
	var line = find_node("CommandInput", true, false)
	if line and line is LineEdit:
		(line as LineEdit).call_deferred("grab_focus")
