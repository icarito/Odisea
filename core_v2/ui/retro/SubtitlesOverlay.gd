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
export(float) var safe_area_padding := 20.0
export(int, 1, 8) var max_visible_lines := 4
export(int, 10, 48) var font_size := 20

var _entries := []
var _layout_tween: Tween = null
var _cached_font: DynamicFont = null
var _expiry_timer: Timer = null

onready var _layer: Control = $Layer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(_layer):
		_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.anchor_right = 1.0
		_layer.anchor_bottom = 1.0
	_ensure_expiry_timer()
	_reflow(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(_layer):
		_reflow(false)

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
	_trim_excess_lines()
	line.modulate.a = 0.0
	_tween_alpha(line, 0.0, 1.0, fade_in_sec)
	_reflow(true)
	_schedule_next_expiry()

func clear_subtitles(immediate: bool = false) -> void:
	if immediate:
		_kill_all()
		return
	var copied = _entries.duplicate()
	for entry in copied:
		_start_fade_out(entry, clear_fade_out_sec)
	_schedule_next_expiry()

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
	var font = _get_subtitle_font()
	label.add_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	# Calculate required width based on text
	var text_w = font.get_string_size(text).x
	if text_w <= 10.0: text_w = text.length() * 12.0 # Fallback
	
	var v_size = _layer.get_viewport_rect().size
	if v_size.x <= 0: v_size = Vector2(1024, 600)
	var safe_margins = _get_safe_margins()
	var usable_width = max(
		240.0,
		v_size.x - float(safe_margins.get("left", 0.0)) - float(safe_margins.get("right", 0.0)) - (horizontal_margin * 2.0)
	)
	var max_w = min(usable_width, v_size.x * max_width_ratio)
	var req_w = clamp(text_w + 64.0, 240.0, max_w)
	
	panel.rect_min_size = Vector2(req_w, 0.0)
	panel.rect_size = panel.rect_min_size
	
	label.rect_min_size = Vector2(req_w - 48.0, 0.0)
	label.rect_size = label.rect_min_size
	
	var min_h = max(40.0, label.get_combined_minimum_size().y + 24.0)
	panel.rect_min_size = Vector2(req_w, min_h)
	panel.rect_size = panel.rect_min_size
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

func _get_subtitle_font() -> DynamicFont:
	if _cached_font:
		return _cached_font
	_cached_font = DynamicFont.new()
	var font_data = load("res://assets/fonts/SyneMono-Regular.ttf")
	if not font_data: font_data = load("res://core_v2/ui/fonts/SyneMono-Regular.ttf")
	if font_data: _cached_font.font_data = font_data
	_cached_font.size = font_size
	_cached_font.use_filter = false
	_cached_font.use_mipmaps = false
	return _cached_font

func _build_font() -> DynamicFont:
	return _get_subtitle_font()

func _reflow(animated: bool) -> void:
	if not is_instance_valid(_layer):
		return
	_cleanup_stale_entries()
	var v_size = _layer.get_viewport_rect().size
	if v_size.x <= 0.0: v_size = Vector2(1024, 600)

	var safe_margins = _get_safe_margins()
	var cursor_y = v_size.y - bottom_margin - float(safe_margins.get("bottom", 0.0))
	for i in range(_entries.size() - 1, -1, -1):
		var entry = _entries[i]
		var node = entry.get("node", null)
		if not is_instance_valid(node):
			continue
		var node_size = node.rect_min_size
		var usable_width = v_size.x - float(safe_margins.get("left", 0.0)) - float(safe_margins.get("right", 0.0))
		var pos_x = float(safe_margins.get("left", 0.0)) + max(0.0, (usable_width - node_size.x) * 0.5)
		var pos = Vector2(pos_x, cursor_y - node_size.y)
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
	_schedule_next_expiry()

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
	_schedule_next_expiry()

func _remove_entry(entry: Dictionary) -> void:
	var target_node = entry.get("node", null)
	for i in range(_entries.size() - 1, -1, -1):
		var node = _entries[i].get("node", null)
		if node == target_node:
			_entries.remove(i)
			return
	_cleanup_stale_entries()

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
	if is_instance_valid(_expiry_timer):
		_expiry_timer.stop()

func _ensure_expiry_timer() -> void:
	if is_instance_valid(_expiry_timer):
		return
	_expiry_timer = Timer.new()
	_expiry_timer.name = "ExpiryTimer"
	_expiry_timer.one_shot = true
	_expiry_timer.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(_expiry_timer)
	_expiry_timer.connect("timeout", self, "_on_expiry_timeout")

func _on_expiry_timeout() -> void:
	var now = OS.get_ticks_msec() / 1000.0
	var copied = _entries.duplicate()
	for entry in copied:
		if bool(entry.get("fading", false)):
			continue
		if now >= float(entry.get("expires_at", 0.0)):
			_start_fade_out(entry, fade_out_sec)
	_schedule_next_expiry()

func _schedule_next_expiry() -> void:
	if not is_instance_valid(_expiry_timer):
		return
	var now = OS.get_ticks_msec() / 1000.0
	var next_expire := -1.0
	for entry in _entries:
		if bool(entry.get("fading", false)):
			continue
		var expires_at = float(entry.get("expires_at", 0.0))
		if next_expire < 0.0 or expires_at < next_expire:
			next_expire = expires_at
	if next_expire < 0.0:
		_expiry_timer.stop()
		return
	_expiry_timer.start(max(0.01, next_expire - now))

func _trim_excess_lines() -> void:
	if max_visible_lines <= 0:
		return
	var active_count := 0
	for i in range(_entries.size() - 1, -1, -1):
		var entry = _entries[i]
		if bool(entry.get("fading", false)):
			continue
		active_count += 1
		if active_count > max_visible_lines:
			_start_fade_out(entry, clear_fade_out_sec)

func _get_safe_margins() -> Dictionary:
	var margins = {
		"left": 0.0,
		"top": 0.0,
		"right": 0.0,
		"bottom": 0.0
	}
	var overlay_ui = get_node_or_null("/root/OverlayUIManager")
	if overlay_ui and overlay_ui.has_method("get_safe_margins"):
		margins = overlay_ui.get_safe_margins(safe_area_padding)
	return margins
