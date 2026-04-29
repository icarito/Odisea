extends PanelContainer
class_name RetroWindow

const TitleFontData = preload("res://assets/fonts/SixtyFour-Regular-FontData.tres")

signal window_focused(window)
signal close_requested(window)
signal window_clicked(window, event)

export(String) var window_title := "Window" setget set_window_title

var _dragging := false
var _drag_offset := Vector2.ZERO
var _is_focused := false
var _is_maximized := false
var _restore_position := Vector2.ZERO
var _restore_size := Vector2.ZERO

onready var _title_bar: Panel = $VBox/TitleBar
onready var _title_row: HBoxContainer = $VBox/TitleBar/TitleRow
onready var _title_label: Label = $VBox/TitleBar/TitleRow/TitleLabel
onready var _max_button: Button = $VBox/TitleBar/TitleRow/BtnMax
onready var _close_button: Button = $VBox/TitleBar/TitleRow/BtnClose

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Apply holo window background
	var win_style = StyleBoxFlat.new()
	win_style.bg_color = Color(0.04, 0.08, 0.05, 0.88)
	win_style.anti_aliasing = false
	win_style.border_width_left = 1
	win_style.border_width_top = 1
	win_style.border_width_right = 1
	win_style.border_width_bottom = 1
	win_style.border_color = Color(0.34, 0.46, 0.36, 0.8)
	add_stylebox_override("panel", win_style)
	
	if _title_bar:
		_title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title_row:
		_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("gui_input", self , "_on_window_gui_input")
	if _max_button:
		_max_button.connect("pressed", self , "_on_max_pressed")
	if _close_button:
		_close_button.connect("pressed", self , "_on_close_pressed")
	if _title_label:
		_title_label.align = Label.ALIGN_CENTER
		_title_label.valign = Label.VALIGN_CENTER
		_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_title_label.add_font_override("font", _build_title_font())
	set_window_title(window_title)
	set_focused(false)

func _build_title_font() -> DynamicFont:
	var font := DynamicFont.new()
	font.font_data = TitleFontData
	font.size = 12
	font.use_filter = false
	font.use_mipmaps = false
	return font

func set_window_title(value: String) -> void:
	window_title = value
	if _title_label:
		_title_label.text = window_title

func set_focused(active: bool) -> void:
	_is_focused = active
	if _title_bar:
		_title_bar.add_stylebox_override("panel", _build_title_style(active))
	if _title_label:
		_title_label.add_color_override("font_color", Color(0.95, 1.0, 1.0) if active else Color(0.72, 0.72, 0.72))

func _focus_window() -> void:
	raise()
	emit_signal("window_focused", self )

func _on_close_pressed() -> void:
	hide()
	emit_signal("close_requested", self )

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
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			emit_signal("window_clicked", self , event)
			_focus_window()
			if _is_click_on_title_bar(event.global_position):
				if event.doubleclick:
					_toggle_maximize()
					_dragging = false
					return
				if not _is_maximized and not _is_click_on_title_button(event.global_position):
					_dragging = true
					_drag_offset = event.global_position - rect_global_position
					return
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		rect_global_position = event.global_position - _drag_offset

func _is_click_on_title_bar(global_pos: Vector2) -> bool:
	var in_bar = false
	var in_row = false
	if _title_bar:
		in_bar = _title_bar.get_global_rect().has_point(global_pos)
	if _title_row:
		in_row = _title_row.get_global_rect().has_point(global_pos)
	return in_bar or in_row

func _is_click_on_title_button(global_pos: Vector2) -> bool:
	if _max_button and _max_button.get_global_rect().has_point(global_pos):
		return true
	if _close_button and _close_button.get_global_rect().has_point(global_pos):
		return true
	return false

func _build_title_style(active: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	# Holo-green if active, semi-transparent dark if not
	s.anti_aliasing = false
	s.bg_color = Color(0.08, 0.22, 0.12, 0.8) if active else Color(0.04, 0.04, 0.04, 0.6)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.border_color = Color("9bfa94") if active else Color(0.34, 0.46, 0.36, 0.4)
	s.expand_margin_top = 1
	s.expand_margin_bottom = 1
	return s
