extends Control

export(float) var default_duration := 2.5
export(float) var fade_in_sec := 0.2
export(float) var fade_out_sec := 0.2
export(float) var clear_fade_out_sec := 0.14
export(float) var stack_shift_sec := 0.12
export(float) var bottom_margin := 36.0
export(float) var horizontal_margin := 32.0
export(float) var line_spacing := 8.0
export(float) var max_width_ratio := 0.86
export(float) var panel_alpha := 0.62

var _entries := []
var _layout_tween: Tween = null

onready var _layer: Control = $Layer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	if is_instance_valid(_layer):
		_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	var now = OS.get_ticks_msec() / 1000.0
	for entry in _entries:
		if bool(entry.get("fading", false)):
			continue
		var expires_at = float(entry.get("expires_at", 0.0))
		if now >= expires_at:
			_start_fade_out(entry, fade_out_sec)

func show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	if text.strip_edges() == "":
		return
	var line = _build_line(text, color)
	_layer.add_child(line)
	var now = OS.get_ticks_msec() / 1000.0
	var entry = {
		"node": line,
		"fading": false,
		"expires_at": now + max(0.05, duration if duration > 0.0 else default_duration),
		"target_pos": Vector2.ZERO
	}
	_entries.append(entry)
	line.modulate.a = 0.0
	_tween_alpha(line, 0.0, 1.0, fade_in_sec)
	_reflow(true)

func clear_subtitles(immediate: bool = false) -> void:
	if immediate:
		_kill_all()
		return
	var copied = _entries.duplicate()
	for entry in copied:
		_start_fade_out(entry, clear_fade_out_sec)

func _build_line(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 1.0
	panel.rect_pivot_offset = Vector2.ZERO
	panel.add_stylebox_override("panel", _build_stylebox())

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", 18)
	margin.add_constant_override("margin_right", 18)
	margin.add_constant_override("margin_top", 10)
	margin.add_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var label := Label.new()
	label.name = "Label"
	label.autowrap = true
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.text = text
	label.add_color_override("font_color", color)
	label.add_font_override("font", _build_font())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	var max_width = max(240.0, rect_size.x * max_width_ratio)
	panel.rect_size = Vector2(max_width, 0.0)
	margin.rect_size = panel.rect_size
	label.rect_size = Vector2(max_width - 36.0, 0.0)
	var min_h = max(36.0, label.get_minimum_size().y + 20.0)
	panel.rect_size = Vector2(max_width, min_h)
	margin.rect_size = panel.rect_size
	label.rect_size = Vector2(max_width - 36.0, min_h - 20.0)
	return panel

func _build_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, panel_alpha)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 1)
	return sb

func _build_font() -> DynamicFont:
	var font := DynamicFont.new()
	var font_data := load("res://assets/fonts/SyneMono-Regular.ttf")
	if font_data:
		font.font_data = font_data
	font.size = 20
	font.use_filter = true
	font.use_mipmaps = true
	return font

func _reflow(animated: bool) -> void:
	_cleanup_stale_entries()
	var viewport_size = rect_size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var cursor_y = viewport_size.y - bottom_margin
	for i in range(_entries.size() - 1, -1, -1):
		var entry = _entries[i]
		var node = entry.get("node", null)
		if not is_instance_valid(node):
			continue
		var pos = Vector2((viewport_size.x - node.rect_size.x) * 0.5, cursor_y - node.rect_size.y)
		entry["target_pos"] = pos
		_entries[i] = entry
		cursor_y = pos.y - line_spacing

	if is_instance_valid(_layout_tween):
		_layout_tween.stop_all()
		_layout_tween.queue_free()
	_layout_tween = Tween.new()
	add_child(_layout_tween)

	for entry in _entries:
		var node = entry.get("node", null)
		if not is_instance_valid(node):
			continue
		var target_pos = entry.get("target_pos", node.rect_position)
		if animated:
			_layout_tween.interpolate_property(node, "rect_position", node.rect_position, target_pos, stack_shift_sec, Tween.TRANS_QUAD, Tween.EASE_OUT)
		else:
			node.rect_position = target_pos
	_layout_tween.start()

func _start_fade_out(entry: Dictionary, duration_sec: float) -> void:
	var node = entry.get("node", null)
	if not is_instance_valid(node):
		_remove_entry(entry)
		return
	if bool(entry.get("fading", false)):
		return
	entry["fading"] = true
	_tween_alpha(node, node.modulate.a, 0.0, max(0.05, duration_sec), true, entry)

func _tween_alpha(node: CanvasItem, from_a: float, to_a: float, duration_sec: float, remove_on_complete: bool = false, entry: Dictionary = {}) -> void:
	if not is_instance_valid(node):
		return
	var tw := Tween.new()
	node.add_child(tw)
	var c_from = node.modulate
	c_from.a = from_a
	var c_to = node.modulate
	c_to.a = to_a
	node.modulate = c_from
	tw.interpolate_property(node, "modulate", c_from, c_to, duration_sec, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	tw.start()
	if remove_on_complete:
		tw.connect("tween_all_completed", self, "_on_fade_out_completed", [entry, tw], CONNECT_ONESHOT)
	else:
		tw.connect("tween_all_completed", self, "_on_tween_done", [tw], CONNECT_ONESHOT)

func _on_tween_done(tw: Tween) -> void:
	if is_instance_valid(tw):
		tw.queue_free()

func _on_fade_out_completed(entry: Dictionary, tw: Tween) -> void:
	if is_instance_valid(tw):
		tw.queue_free()
	var node = entry.get("node", null)
	if is_instance_valid(node):
		node.queue_free()
	_remove_entry(entry)
	_reflow(false)

func _remove_entry(entry: Dictionary) -> void:
	var target_node = entry.get("node", null)
	for i in range(_entries.size() - 1, -1, -1):
		var node = _entries[i].get("node", null)
		if node == target_node:
			_entries.remove(i)
			return

func _cleanup_stale_entries() -> void:
	for i in range(_entries.size() - 1, -1, -1):
		var node = _entries[i].get("node", null)
		if not is_instance_valid(node):
			_entries.remove(i)

func _kill_all() -> void:
	for entry in _entries:
		var node = entry.get("node", null)
		if is_instance_valid(node):
			node.queue_free()
	_entries.clear()
