extends CanvasLayer

# InteractionMarker.gd - System for screen-space interactable markers

enum State {
	HIDDEN,
	ON_SCREEN,
	OFF_SCREEN,
	LOCKED
}

class MarkerEntry:
	var interactable: Spatial
	var config: Resource # MarkerConfig
	var state: int = State.HIDDEN
	var last_state: int = State.HIDDEN
	var was_ever_seen: bool = false
	var screen_pos: Vector2
	var distance_to_camera: float
	var distance_to_center: float
	var priority: int
	var debounce_timer: float = 0.0

	func _init(i: Spatial, c: Resource):
		interactable = i
		config = c
		priority = c.priority

var _entries: Array = []
var _ui_pool: Array = []
var _active_ui: Array = []
var _arc_draw_data: Array = []

onready var _ui_root: Control = $UI
onready var _arc_overlay: Control = $UI/ArcOverlay
onready var _font: Font = preload("res://TinyFont.tres")

const MAX_VISIBLE_MARKERS = 3
const FOCUS_DEBOUNCE_SEC = 0.15
const ARC_RADIUS = 24.0
const ARC_STROKE = 12.0

func _ready() -> void:
	_arc_overlay.connect("draw", self, "_on_arc_overlay_draw")
	# Initialize pool
	for i in range(MAX_VISIBLE_MARKERS):
		var ui = _create_marker_ui()
		_ui_pool.append(ui)
		_ui_root.add_child(ui)
		ui.visible = false

func register(interactable: Spatial, config: Resource) -> void:
	for entry in _entries:
		if entry.interactable == interactable:
			entry.config = config
			return
	_entries.append(MarkerEntry.new(interactable, config))

func unregister(interactable: Spatial) -> void:
	for i in range(_entries.size()):
		if _entries[i].interactable == interactable:
			_entries.remove(i)
			return

func get_targets_in_range(origin: Vector3, p_range: float) -> Array:
	var results = []
	for entry in _entries:
		if not is_instance_valid(entry.interactable):
			continue
		var pos = entry.interactable.global_transform.origin
		var dist = origin.distance_to(pos)
		if dist <= p_range:
			results.append({
				"spatial": entry.interactable,
				"config": entry.config,
				"distance": dist,
				"state": entry.state,
				"priority": entry.priority
			})

	results.sort_custom(self, "_sort_targets")

	# Strip internal priority from final dictionaries to match spec
	var final_results = []
	for res in results:
		final_results.append({
			"spatial": res.spatial,
			"config": res.config,
			"distance": res.distance,
			"state": res.state
		})
	return final_results

func _sort_targets(a, b) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.distance < b.distance

func get_named_target(p_label: String) -> Spatial:
	for entry in _entries:
		if is_instance_valid(entry.interactable) and entry.config.label == p_label:
			return entry.interactable
	return null

func get_registered_count() -> int:
	return _entries.size()

func update_config(interactable: Spatial, config: Resource) -> void:
	register(interactable, config)

func _process(delta: float) -> void:
	var camera = get_viewport().get_camera()
	if not camera:
		_hide_all()
		return

	var viewport_size = get_viewport().size
	var center = viewport_size / 2.0
	var candidates = []

	for entry in _entries:
		if not is_instance_valid(entry.interactable):
			continue

		var pos = entry.interactable.global_transform.origin
		entry.distance_to_camera = pos.distance_to(camera.global_transform.origin)

		var is_in_range = entry.distance_to_camera <= entry.config.interaction_range
		var is_behind = camera.is_position_behind(pos)
		entry.screen_pos = camera.unproject_position(pos)

		var viewport_rect = Rect2(Vector2.ZERO, viewport_size)
		var is_in_viewport = not is_behind and viewport_rect.has_point(entry.screen_pos)

		var locked = false
		if entry.config.is_locked != null:
			locked = bool(entry.config.is_locked.call_func())

		var next_state = State.HIDDEN
		if is_in_range:
			if is_in_viewport:
				next_state = State.ON_SCREEN
				entry.was_ever_seen = true
			elif entry.config.off_screen:
				next_state = State.OFF_SCREEN
		else:
			if entry.was_ever_seen and locked:
				if is_in_viewport:
					next_state = State.LOCKED
				elif entry.config.off_screen:
					# Spec: "Si está fuera de viewport pero en rango, muestra un arco"
					# It doesn't explicitly say arcs for locked-out-of-range,
					# but we'll show it if off_screen is enabled.
					next_state = State.OFF_SCREEN

		# Debounce state transitions (150ms)
		if next_state != entry.state:
			entry.debounce_timer += delta
			if entry.debounce_timer >= FOCUS_DEBOUNCE_SEC:
				entry.state = next_state
				entry.debounce_timer = 0.0
		else:
			entry.debounce_timer = 0.0

		if entry.state != State.HIDDEN:
			entry.distance_to_center = entry.screen_pos.distance_to(center)
			candidates.append(entry)

	# Priority culling: Max 3, sort by priority (0=high), then center distance
	candidates.sort_custom(self, "_sort_markers")

	var visible_markers = candidates.slice(0, MAX_VISIBLE_MARKERS)
	_update_visuals(visible_markers, viewport_size)

func _sort_markers(a, b) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.distance_to_center < b.distance_to_center

func _update_visuals(visible_markers: Array, viewport_size: Vector2) -> void:
	_arc_draw_data.clear()

	# Recycle all active UI
	for ui in _active_ui:
		ui.visible = false
		_ui_pool.append(ui)
	_active_ui.clear()

	for entry in visible_markers:
		if entry.state == State.ON_SCREEN or entry.state == State.LOCKED:
			var ui = _get_ui_from_pool()
			if ui:
				_setup_ui(ui, entry)
				_active_ui.append(ui)
		elif entry.state == State.OFF_SCREEN:
			_arc_draw_data.append({
				"pos": entry.screen_pos,
				"color": entry.config.accent_color,
				"is_behind": get_viewport().get_camera().is_position_behind(entry.interactable.global_transform.origin)
			})

	_arc_overlay.update()

func _get_ui_from_pool() -> Control:
	if _ui_pool.empty(): return null
	return _ui_pool.pop_back()

func _setup_ui(ui: Control, entry: MarkerEntry) -> void:
	ui.visible = true

	var label = ui.get_node("VBox/Label")
	var hint = ui.get_node("VBox/Hint")
	var icon = ui.get_node("Icon")

	label.text = entry.config.label
	if entry.state == State.LOCKED:
		hint.text = _format_hint(entry.config.locked_text)
		hint.add_color_override("font_color", Color.orange) # Visual feedback for locked
	else:
		hint.text = _format_hint(entry.config.hint)
		hint.add_color_override("font_color", Color(0.8, 0.8, 0.8))

	icon.texture = entry.config.icon
	icon.modulate = entry.config.accent_color

	# Center UI on screen_pos (approx)
	var margin = entry.config.screen_margin
	var vs = get_viewport().size
	var target_pos = entry.screen_pos - Vector2(20, 16) # Offset to align icon/vbox roughly center

	ui.rect_position.x = clamp(target_pos.x, margin, vs.x - margin - 150) # Approx width
	ui.rect_position.y = clamp(target_pos.y, margin, vs.y - margin - 40)  # Approx height

func _format_hint(text: String) -> String:
	if text.find("{") == -1: return text
	var actions = ["interact", "focus", "ui_cancel"]
	for action in actions:
		var placeholder = "{" + action + "}"
		if text.find(placeholder) != -1:
			text = text.replace(placeholder, _get_action_text(action))
	return text

func _get_action_text(action: String) -> String:
	var events = InputMap.get_action_list(action)
	for event in events:
		if event is InputEventKey:
			return "[" + OS.get_scancode_string(event.scancode) + "]"
	return "[" + action.to_upper() + "]"

func _hide_all() -> void:
	for ui in _active_ui:
		ui.visible = false
		_ui_pool.append(ui)
	_active_ui.clear()
	_arc_draw_data.clear()
	_arc_overlay.update()

func _create_marker_ui() -> Control:
	var root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon = TextureRect.new()
	icon.name = "Icon"
	icon.rect_min_size = Vector2(32, 32)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.rect_position = Vector2(40, 0)
	root.add_child(vbox)

	var label = Label.new()
	label.name = "Label"
	label.add_font_override("font", _font)
	vbox.add_child(label)

	var hint = Label.new()
	hint.name = "Hint"
	hint.add_font_override("font", _font)
	vbox.add_child(hint)

	return root

func _on_arc_overlay_draw() -> void:
	var vs = get_viewport().size
	var margin = 32.0
	var rect = Rect2(margin, margin, vs.x - margin*2, vs.y - margin*2)

	for data in _arc_draw_data:
		var target_pos = data.pos
		if data.is_behind:
			# If behind, project it to the opposite side
			target_pos = (vs / 2.0) + (vs / 2.0 - target_pos).normalized() * 2000.0

		var edge_pos = _get_rect_edge_intersection(rect, vs / 2.0, target_pos)
		var angle = (target_pos - vs/2.0).angle()
		_draw_minimalist_arc(edge_pos, angle, data.color)

func _get_rect_edge_intersection(rect: Rect2, center: Vector2, target: Vector2) -> Vector2:
	var dir = (target - center).normalized()
	if dir.length_squared() < 0.0001: return center
	var t_min = 1e10
	if dir.x > 0: t_min = min(t_min, (rect.end.x - center.x) / dir.x)
	elif dir.x < 0: t_min = min(t_min, (rect.position.x - center.x) / dir.x)
	if dir.y > 0: t_min = min(t_min, (rect.end.y - center.y) / dir.y)
	elif dir.y < 0: t_min = min(t_min, (rect.position.y - center.y) / dir.y)
	return center + dir * t_min

func _draw_minimalist_arc(pos: Vector2, angle: float, color: Color) -> void:
	var arc_color = color
	arc_color.a = 0.4
	var points = PoolVector2Array()
	var steps = 16
	var arc_span = PI / 3.0
	var start_angle = angle - arc_span / 2.0
	for i in range(steps + 1):
		var a = start_angle + (float(i) / steps) * arc_span
		points.append(pos + Vector2(cos(a), sin(a)) * ARC_RADIUS)
	_arc_overlay.draw_polyline(points, arc_color, ARC_STROKE, true)
