extends PanelContainer
class_name RetroWindow

signal window_focused(window)
signal close_requested(window)

export(String) var window_title := "Window" setget set_window_title

var _dragging := false
var _drag_offset := Vector2.ZERO
var _is_focused := false
var _is_maximized := false
var _restore_position := Vector2.ZERO
var _restore_size := Vector2.ZERO

onready var _title_bar: Panel = $VBox/TitleBar
onready var _title_label: Label = $VBox/TitleBar/TitleRow/TitleLabel
onready var _max_button: Button = $VBox/TitleBar/TitleRow/BtnMax
onready var _close_button: Button = $VBox/TitleBar/TitleRow/BtnClose

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _title_bar:
		_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
		_title_bar.connect("gui_input", self, "_on_title_bar_gui_input")
	connect("gui_input", self, "_on_window_gui_input")
	if _max_button:
		_max_button.connect("pressed", self, "_on_max_pressed")
	if _close_button:
		_close_button.connect("pressed", self, "_on_close_pressed")
	set_window_title(window_title)
	set_focused(false)

func set_window_title(value: String) -> void:
	window_title = value
	if _title_label:
		_title_label.text = window_title

func set_focused(active: bool) -> void:
	_is_focused = active
	if _title_bar:
		_title_bar.add_stylebox_override("panel", _build_title_style(active))
	if _title_label:
		_title_label.add_color_override("font_color", Color(1, 1, 1) if active else Color(0, 0, 0))

func _focus_window() -> void:
	raise()
	emit_signal("window_focused", self)

func _on_close_pressed() -> void:
	hide()
	emit_signal("close_requested", self)

func _on_max_pressed() -> void:
	_toggle_maximize()

func _toggle_maximize() -> void:
	var parent_ctrl = get_parent() as Control
	if not parent_ctrl:
		return
	if not _is_maximized:
		_restore_position = rect_position
		_restore_size = rect_size
		rect_position = Vector2.ZERO
		rect_size = parent_ctrl.rect_size
		_is_maximized = true
		if _max_button:
			_max_button.text = "R"
		return

	rect_position = _restore_position
	rect_size = _restore_size
	_is_maximized = false
	if _max_button:
		_max_button.text = "+"

func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		_focus_window()

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			_focus_window()
			if _is_maximized:
				_dragging = false
				return
			_dragging = true
			_drag_offset = get_global_mouse_position() - rect_global_position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		rect_global_position = get_global_mouse_position() - _drag_offset

func _build_title_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("000080") if active else Color("7a7a7a")
	# Standard Win95 title bars don't usually have borders on all sides, 
	# but we use them for clarity in 3D.
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color("dfdfdf") if active else Color("a0a0a0")
	s.expand_margin_top = 1
	s.expand_margin_bottom = 1
	return s
