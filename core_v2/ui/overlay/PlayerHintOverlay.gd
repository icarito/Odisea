extends Control

const FALLBACK_FONT = preload("res://TinyFont.tres")

export(float) var hint_margin_left := 24.0
export(float) var hint_margin_top := 18.0
export(float) var max_width_ratio := 0.55
export(int, 10, 36) var font_size := 18
export(Color) var font_color := Color(0.85, 1.0, 0.95)

var _cached_font: DynamicFont = null
var _hint_mode := "hint"

onready var _label: Label = $HintLabel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label:
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.visible = false
		_label.text = ""
		_label.autowrap = true
		_label.add_color_override("font_color", font_color)
		_label.add_font_override("font", _get_font())
	_reflow()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reflow()

func set_hint_text(text: String) -> void:
	if not _label:
		return
	_label.text = text
	_label.visible = text.strip_edges() != ""
	_reflow()

func clear_hint_text() -> void:
	set_hint_text("")

func set_hint_mode(mode: String) -> void:
	var normalized := mode.strip_edges().to_lower()
	_hint_mode = "status" if normalized == "status" else "hint"
	_reflow()

func _reflow() -> void:
	if not _label:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0:
		viewport_size = Vector2(1024, 600)
	var safe_margins := _get_safe_margins()
	var max_width := max(180.0, viewport_size.x * max_width_ratio)
	var left := float(safe_margins.get("left", 0.0)) + hint_margin_left
	var top := float(safe_margins.get("top", 0.0)) + hint_margin_top
	if _hint_mode == "status":
		var usable_width := viewport_size.x - float(safe_margins.get("left", 0.0)) - float(safe_margins.get("right", 0.0))
		max_width = max(220.0, min(usable_width, viewport_size.x * 0.5))
		left = (viewport_size.x - max_width) * 0.5
		top = viewport_size.y * 0.38
		_label.align = Label.ALIGN_CENTER
	else:
		var usable_width := viewport_size.x - left - float(safe_margins.get("right", 0.0)) - hint_margin_left
		max_width = max(180.0, min(usable_width, viewport_size.x * max_width_ratio))
		_label.align = Label.ALIGN_LEFT
	_label.rect_position = Vector2(left, top)
	_label.rect_min_size = Vector2(max_width, 0.0)
	_label.rect_size = Vector2(max_width, max(_label.rect_size.y, 32.0))

func _get_safe_margins() -> Dictionary:
	var overlay_ui = get_node_or_null("/root/OverlayUIManager")
	if overlay_ui and overlay_ui.has_method("get_safe_margins"):
		return overlay_ui.get_safe_margins(0.0)
	return {
		"left": 0.0,
		"top": 0.0,
		"right": 0.0,
		"bottom": 0.0
	}

func _get_font() -> DynamicFont:
	if _cached_font:
		return _cached_font
	_cached_font = DynamicFont.new()
	if FALLBACK_FONT and FALLBACK_FONT.font_data:
		_cached_font.font_data = FALLBACK_FONT.font_data
	_cached_font.size = font_size
	_cached_font.use_filter = false
	_cached_font.use_mipmaps = false
	return _cached_font
