extends Control

const FALLBACK_SUBTITLE_FONT = preload("res://TinyFont.tres")
# FD-316 (tarea GG): en tier LOW los subtitulos no pagan la sombra dinamica del panel (blur
# de StyleBoxFlat por cuadro). El A/B es ODISEA_LOW_UI_OPT.
const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")
# El proyecto dibuja la UI en el viewport reducido por render_scale; a < 1 lo medido en
# pixeles fijos crece relativo a la pantalla. Compensamos con la misma escala que el resto
# de la UI para que el subtitulo mida igual en 16:9, en el handheld y en tactil.
const UIScaleCompensatorScript = preload("res://core_v2/ui/UIScaleCompensator.gd")

export(float) var default_duration := 2.5
export(float) var fade_in_sec := 0.2
export(float) var fade_out_sec := 0.2
export(float) var clear_fade_out_sec := 0.14
export(float) var stack_shift_sec := 0.12
export(float) var bottom_margin := 36.0
export(float) var horizontal_margin := 32.0
export(float) var line_spacing := 6.0
# Ancho maximo del subtitulo como fraccion de la pantalla: angosto para no tapar la accion.
export(float) var max_width_ratio := 0.60
# El fondo solo sostiene el texto; la legibilidad la da el contorno de la fuente.
export(float) var panel_alpha := 0.28
export(float) var safe_area_padding := 20.0
# Como maximo dos frases en pantalla a la vez; la mas vieja sale y encadena la que sigue.
export(int, 1, 8) var max_visible_lines := 2
export(int, 10, 48) var font_size := 20
# Duracion proporcional al largo del texto: base + caracteres * por_caracter, acotada al tope.
export(float) var reading_base_sec := 0.9
export(float) var reading_per_char_sec := 0.045
export(float) var min_duration := 1.4
export(float) var max_duration := 5.0
export(float) var panel_corner_radius := 4.0
export(int, 0, 4) var text_outline_size := 2

var _entries := []
# Frases que llegan cuando ya hay max_visible_lines en pantalla: se encadenan en vez de
# apilarse cuatro a la vez. Cada una mide su duracion desde que se monta, no desde que llega.
var _pending := []
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

# Rect (coordenadas de viewport) del stack visible de subtitulos. Lo consulta el HUD
# para colocar el contexto del pie por encima en vez de superponerlo. Read-only.
func get_visible_stack_rect() -> Rect2:
	if not is_instance_valid(_layer) or not is_visible_in_tree():
		return Rect2()
	var out := Rect2()
	var found := false
	for entry in _entries:
		var node = entry.get("node", null)
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		if node.modulate.a <= 0.01:
			continue
		var size: Vector2 = node.rect_size
		if size.x <= 0.0 or size.y <= 0.0:
			size = node.rect_min_size
		var rect := Rect2(node.rect_position + _layer.rect_position, size)
		if found:
			out = out.merge(rect)
		else:
			out = rect
			found = true
	return out if found else Rect2()

func show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	_show_entry(text, color, duration, false)

func show_hint(text: String, color: Color = Color(0.85, 1.0, 0.95), duration: float = 1.75) -> void:
	_show_entry(text, color, duration, true)

func _show_entry(text: String, color: Color, duration: float, is_hint: bool) -> void:
	var clean := text.strip_edges()
	if clean == "":
		return
	var entry := {
		"text": clean,
		"color": color,
		"is_hint": is_hint,
		"duration": _resolve_duration(clean, duration),
		"node": null,
		"fading": false,
		"expires_at": 0.0,
		"target_pos": Vector2.ZERO,
	}
	if _occupied_count() >= max_visible_lines:
		_pending.append(entry)
		return
	_mount_entry(entry)

func _mount_entry(entry: Dictionary) -> void:
	if not is_instance_valid(_layer):
		return
	var line := _build_line(entry.get("text", ""), entry.get("color", Color.white), bool(entry.get("is_hint", false)))
	_layer.add_child(line)
	entry["node"] = line
	entry["fading"] = false
	entry["expires_at"] = _now() + float(entry.get("duration", default_duration))
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
	_pending.clear()
	var copied = _entries.duplicate()
	for entry in copied:
		_start_fade_out(entry, clear_fade_out_sec)
	_schedule_next_expiry()

# Duracion proporcional al largo del texto con tope. Si el productor pide una duracion, se
# respeta pero nunca por encima de lo que el texto necesita (asi una frase corta no se queda
# cinco segundos en pantalla).
func _resolve_duration(text: String, requested: float) -> float:
	var auto := default_duration
	if reading_per_char_sec > 0.0 or reading_base_sec > 0.0:
		auto = clamp(
			reading_base_sec + float(text.length()) * reading_per_char_sec,
			min_duration,
			max_duration
		)
	if requested <= 0.0:
		return auto
	return clamp(min(requested, auto), 0.05, max_duration)

func _now() -> float:
	return OS.get_ticks_msec() / 1000.0

func _ui_scale() -> float:
	return clamp(UIScaleCompensatorScript.scale_for(self), 0.5, 1.0)

func _build_line(text: String, color: Color, is_hint: bool = false) -> PanelContainer:
	var k := _ui_scale()
	var pad_x := round(12.0 * k)
	var pad_y := round(6.0 * k)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 1.0
	panel.rect_pivot_offset = Vector2.ZERO
	panel.add_stylebox_override("panel", _build_stylebox(is_hint))

	var margin := MarginContainer.new()
	margin.add_constant_override("margin_left", pad_x)
	margin.add_constant_override("margin_right", pad_x)
	margin.add_constant_override("margin_top", pad_y)
	margin.add_constant_override("margin_bottom", pad_y)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var label := Label.new()
	label.name = "Label"
	label.autowrap = true
	label.align = Label.ALIGN_CENTER
	label.valign = Label.VALIGN_CENTER
	label.text = text
	label.add_color_override("font_color", color)
	var font := _get_subtitle_font()
	label.add_font_override("font", font)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	# Ancho requerido segun el texto en una sola linea.
	var text_w := font.get_string_size(text).x
	if text_w <= 10.0:
		text_w = float(text.length()) * float(font_size) * 0.6 * k

	var v_size := _layer.get_viewport_rect().size
	if v_size.x <= 0.0:
		v_size = Vector2(1024.0, 600.0)
	var safe_margins := _get_safe_margins()
	var min_w: float = 180.0 * k
	var usable_width: float = max(
		min_w,
		v_size.x - float(safe_margins.get("left", 0.0)) - float(safe_margins.get("right", 0.0)) - (horizontal_margin * k * 2.0)
	)
	var max_w: float = min(usable_width, v_size.x * max_width_ratio)
	var req_w: float = clamp(text_w + pad_x * 2.0, min_w, max_w)

	panel.rect_min_size = Vector2(req_w, 0.0)
	panel.rect_size = panel.rect_min_size

	label.rect_min_size = Vector2(max(1.0, req_w - pad_x * 2.0), 0.0)
	label.rect_size = label.rect_min_size

	var min_h: float = max(28.0 * k, label.get_combined_minimum_size().y + pad_y * 2.0)
	panel.rect_min_size = Vector2(req_w, min_h)
	panel.rect_size = panel.rect_min_size
	return panel

func _build_stylebox(is_hint: bool = false) -> StyleBoxFlat:
	var k := _ui_scale()
	var radius: int = int(round(panel_corner_radius * k))
	var sb := StyleBoxFlat.new()
	if is_hint:
		sb.bg_color = Color(0.01, 0.08, 0.09, 0.55)
		sb.border_color = Color(0.0, 0.9, 0.78, 0.55)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
	else:
		sb.bg_color = Color(0.0, 0.0, 0.0, panel_alpha)
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 0 if LowUiOptScript.enabled() else 4
	sb.shadow_offset = Vector2(0, 1)
	return sb

func _get_subtitle_font() -> DynamicFont:
	var k := _ui_scale()
	var wanted: int = int(max(10, round(float(font_size) * k)))
	if _cached_font == null:
		_cached_font = DynamicFont.new()
		if FALLBACK_SUBTITLE_FONT and FALLBACK_SUBTITLE_FONT.font_data:
			_cached_font.font_data = FALLBACK_SUBTITLE_FONT.font_data
		_cached_font.use_filter = false
		_cached_font.use_mipmaps = false
	_cached_font.size = wanted
	# Contorno oscuro: el texto se lee sobre fondos claros y oscuros sin panel opaco.
	_cached_font.outline_size = int(round(float(text_outline_size) * k))
	_cached_font.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	return _cached_font

func _build_font() -> DynamicFont:
	return _get_subtitle_font()

func _reflow(animated: bool) -> void:
	if not is_instance_valid(_layer):
		return
	_cleanup_stale_entries()
	var k := _ui_scale()
	var v_size = _layer.get_viewport_rect().size
	if v_size.x <= 0.0: v_size = Vector2(1024, 600)

	var safe_margins = _get_safe_margins()
	var cursor_y = v_size.y - bottom_margin * k - float(safe_margins.get("bottom", 0.0))
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
		cursor_y = pos.y - line_spacing * k

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
	_promote_pending()
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
	_pending.clear()
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
	var now = _now()
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
	var now = _now()
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

# Entradas montadas (visibles o desvaneciendose): ocupan lugar hasta que terminan de salir.
func _occupied_count() -> int:
	_cleanup_stale_entries()
	var count := 0
	for entry in _entries:
		if is_instance_valid(entry.get("node", null)):
			count += 1
	return count

# Monta las frases encoladas apenas se libera un lugar, encadenandolas en vez de apilarlas.
func _promote_pending() -> void:
	while not _pending.empty() and _occupied_count() < max_visible_lines:
		_mount_entry(_pending.pop_front())

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
