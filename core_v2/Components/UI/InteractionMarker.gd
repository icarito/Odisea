extends CanvasLayer

# InteractionMarker.gd - Singleton Autoload managing screen-space markers

enum MarkerState {
	HIDDEN,
	ON_SCREEN,
	OFF_SCREEN,
	LOCKED
}

const TINY_FONT = preload("res://TinyFont.tres")
const DEBOUNCE_TIME_MS := 150.0

var _interactables := {} # Spatial -> MarkerConfig
var _states := {} # Spatial -> {state: int, was_ever_seen: bool, last_pos: Vector2, last_unprojected: Vector2, target_state: int, last_state_change: float}
var _ui_nodes := {} # Spatial -> Control
var _off_screen_arcs := [] # Array of {pos: Vector2, angle: float, color: Color}
var _cached_input_map := {} # ActionName -> DisplayString

onready var _marker_container := $Root/Markers
onready var _off_screen_container := $Root/OffScreen
onready var _arc_renderer := $Root/OffScreen/ArcRenderer

func _ready() -> void:
	_refresh_input_cache()

func register(interactable: Spatial, config: Resource) -> void:
	_interactables[interactable] = config
	_states[interactable] = {
		"state": MarkerState.HIDDEN,
		"target_state": MarkerState.HIDDEN,
		"was_ever_seen": false,
		"last_pos": Vector2.ZERO,
		"last_state_change": OS.get_ticks_msec()
	}

func unregister(interactable: Spatial) -> void:
	if _interactables.has(interactable):
		_interactables.erase(interactable)
	if _states.has(interactable):
		_states.erase(interactable)
	if _ui_nodes.has(interactable):
		_ui_nodes[interactable].queue_free()
		_ui_nodes.erase(interactable)

func update_config(interactable: Spatial, config: Resource) -> void:
	_interactables[interactable] = config

func _process(_delta: float) -> void:
	_update_markers()

func _update_markers() -> void:
	var camera := get_viewport().get_camera()
	if not camera:
		return

	var screen_size := get_viewport().get_visible_rect().size
	var now := float(OS.get_ticks_msec())
	var candidates := []

	for interactable in _interactables.keys():
		var config = _interactables[interactable]
		var state_data = _states[interactable]

		var spatial_node := interactable as Spatial
		var global_pos := spatial_node.global_transform.origin
		var dist := camera.global_transform.origin.distance_to(global_pos)

		var is_locked := false
		if config.get("is_locked") and config.get("is_locked") is FuncRef:
			is_locked = config.get("is_locked").call_func()

		var unprojected := camera.unproject_position(global_pos)
		var is_on_screen := not camera.is_position_behind(global_pos) and \
							unprojected.x >= 0 and unprojected.x <= screen_size.x and \
							unprojected.y >= 0 and unprojected.y <= screen_size.y

		var new_target_state = MarkerState.HIDDEN

		var interaction_range = config.get("interaction_range")
		if interaction_range == null: interaction_range = 5.0

		if dist <= interaction_range:
			if is_on_screen:
				new_target_state = MarkerState.ON_SCREEN
				state_data.was_ever_seen = true
			elif config.get("off_screen"):
				new_target_state = MarkerState.OFF_SCREEN
		elif state_data.was_ever_seen and is_locked:
			new_target_state = MarkerState.LOCKED

		# Debounce Logic
		if new_target_state != state_data.target_state:
			state_data.target_state = new_target_state
			state_data.last_state_change = now

		if state_data.state != state_data.target_state:
			if now - state_data.last_state_change >= DEBOUNCE_TIME_MS:
				state_data.state = state_data.target_state

		state_data.last_unprojected = unprojected

		if state_data.state != MarkerState.HIDDEN:
			var priority = config.get("priority")
			if priority == null: priority = 10
			candidates.append({
				"node": interactable,
				"priority": priority,
				"dist_to_center": unprojected.distance_to(screen_size / 2.0)
			})

	# Priority Culling: Max 3 visible
	candidates.sort_custom(self, "_compare_candidates")
	var visible_count := 0
	_off_screen_arcs.clear()

	for i in range(candidates.size()):
		var interactable = candidates[i].node
		var state_data = _states[interactable]
		var config = _interactables[interactable]

		if visible_count < 3:
			visible_count += 1
			_update_ui_node(interactable, state_data.state, state_data.last_unprojected, config)
		else:
			_hide_ui_node(interactable)

	# Clean up UI nodes for objects no longer candidates
	var candidate_nodes := []
	for c in candidates:
		candidate_nodes.append(c.node)

	for interactable in _ui_nodes.keys():
		if not candidate_nodes.has(interactable):
			_hide_ui_node(interactable)

	if _arc_renderer:
		_arc_renderer.arcs = _off_screen_arcs
		_arc_renderer.update()

func _compare_candidates(a, b) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.dist_to_center < b.dist_to_center

func _update_ui_node(interactable: Spatial, state: int, pos: Vector2, config: Resource) -> void:
	if state == MarkerState.OFF_SCREEN:
		_hide_ui_node(interactable)
		_add_off_screen_arc(pos, config)
		return

	var node: Control
	if _ui_nodes.has(interactable):
		node = _ui_nodes[interactable]
	else:
		node = _create_marker_node()
		_ui_nodes[interactable] = node
		_marker_container.add_child(node)

	node.visible = true
	node.rect_position = pos

	var label_node := node.get_node("Label") as Label
	var hint_node := node.get_node("Hint") as Label
	var icon_node := node.get_node("Icon") as TextureRect

	if state == MarkerState.ON_SCREEN:
		label_node.text = str(config.get("label"))
		hint_node.text = _format_hint(str(config.get("hint")))
		icon_node.texture = config.get("icon") as Texture
		label_node.modulate = Color.white
	elif state == MarkerState.LOCKED:
		label_node.text = str(config.get("locked_text"))
		hint_node.text = ""
		icon_node.texture = null
		label_node.modulate = Color.red

func _hide_ui_node(interactable: Spatial) -> void:
	if _ui_nodes.has(interactable):
		_ui_nodes[interactable].visible = false

func _create_marker_node() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.rect_min_size = Vector2(32, 32)
	icon.rect_position = Vector2(-16, -40)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)

	var label := Label.new()
	label.name = "Label"
	label.add_font_override("font", TINY_FONT)
	label.align = Label.ALIGN_CENTER
	label.rect_position = Vector2(-100, 0)
	label.rect_size = Vector2(200, 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.add_font_override("font", TINY_FONT)
	hint.align = Label.ALIGN_CENTER
	hint.rect_position = Vector2(-100, 20)
	hint.rect_size = Vector2(200, 20)
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)

	return root

func _add_off_screen_arc(unprojected: Vector2, config: Resource) -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var center := screen_size / 2.0
	var dir := (unprojected - center).normalized()

	var margin = config.get("screen_margin")
	if margin == null: margin = 32.0
	# Clamp unprojected to screen bounds with margin
	var pos := unprojected
	pos.x = clamp(pos.x, margin, screen_size.x - margin)
	pos.y = clamp(pos.y, margin, screen_size.y - margin)

	var angle := dir.angle()
	_off_screen_arcs.append({
		"pos": pos,
		"angle": angle,
		"color": Color(0.0, 1.0, 1.0, 0.4) # Cyan with 40% alpha
	})

func _format_hint(hint: String) -> String:
	# Replace [action_name] with corresponding key/button
	var start_idx := hint.find("[")
	while start_idx != -1:
		var end_idx := hint.find("]", start_idx)
		if end_idx == -1: break

		var action_name := hint.substr(start_idx + 1, end_idx - start_idx - 1)
		var display := _get_action_display(action_name)
		hint = hint.replace("[" + action_name + "]", display)

		start_idx = hint.find("[", start_idx + display.length())

	return hint

func _get_action_display(action: String) -> String:
	if _cached_input_map.has(action):
		return _cached_input_map[action]

	var events := InputMap.get_action_list(action)
	for event in events:
		if event is InputEventKey:
			var key_name := OS.get_scancode_string(event.scancode)
			_cached_input_map[action] = key_name
			return key_name
		elif event is InputEventJoypadButton:
			var btn_name := "Joy " + str(event.button_index)
			_cached_input_map[action] = btn_name
			return btn_name

	return action.to_upper()

func _refresh_input_cache() -> void:
	_cached_input_map.clear()
	# Pre-cache common actions if needed
