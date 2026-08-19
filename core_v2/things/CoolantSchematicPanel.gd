extends Control
class_name CoolantSchematicPanel

# CoolantSchematicPanel.gd - Schematic pipe diagram displaying real-time status
# of coolant valves and pipe fissures/leaks (FD-270).
# Designed for read-only rendering within holographic display viewports.

const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")

# Color palette
const COLOR_VALVE_OPEN := Color(0.1, 1.0, 0.3)
const COLOR_VALVE_CLOSED := Color(1.0, 0.15, 0.1)

const COLOR_PIPE_HEALTHY := Color(0.2, 0.7, 0.9, 0.8)
const COLOR_PIPE_WARNING := Color(1.0, 0.8, 0.1, 0.9)
const COLOR_PIPE_LEAKING := Color(1.0, 0.2, 0.8, 1.0)
const COLOR_PIPE_DEPRESSURIZED := Color(0.4, 0.4, 0.4, 0.6)

const COLOR_OFFLINE_VALVE := Color(0.5, 0.5, 0.5, 0.8)
const COLOR_OFFLINE_PIPE := Color(0.35, 0.35, 0.35, 0.5)
const COLOR_TEXT := Color(0.8, 0.9, 1.0, 0.85)

const NUM_FLOORS := 6
const X_WEST := 80.0
const X_EAST := 220.0
const Y_BOTTOM := 270.0
const Y_STEP := 40.0
const X_INTERLINK := 150.0
const Y_INTERLINK := 190.0 # Height of Floor 2

var _connected_valves := []
var _last_state_hash := 0


func _ready() -> void:
	_setup_valve_connections()
	update()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	var current_hash: int = _compute_state_hash()
	if current_hash != _last_state_hash:
		_last_state_hash = current_hash
		update()
		_request_redraw()


func _setup_valve_connections() -> void:
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	for valve in valves:
		if is_instance_valid(valve) and valve.has_signal("valve_state_changed"):
			if not valve.is_connected("valve_state_changed", self, "_on_valve_state_changed"):
				valve.connect("valve_state_changed", self, "_on_valve_state_changed")
				_connected_valves.append(valve)


func _on_valve_state_changed(_is_open: bool = false) -> void:
	_last_state_hash = _compute_state_hash()
	update()
	_request_redraw()


func _draw() -> void:
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	var patch_points: Array = get_tree().get_nodes_in_group("gloo_patchable")

	var is_live: bool = (not valves.empty()) or (not patch_points.empty())

	# Map valves to layout nodes
	var layout: Dictionary = _map_valves_to_layout(valves)
	var west_valves = layout.get("west", [])
	var east_valves = layout.get("east", [])
	var interlink_valve = layout.get("interlink", null)

	# Map fissures to pipe segment states
	var segment_states: Dictionary = _map_fissures_to_segments(patch_points)
	var west_states = segment_states.get("west", [])
	var east_states = segment_states.get("east", [])
	var interlink_state = segment_states.get("interlink", CoolantLeak.State.HEALTHY)

	# Draw Header / Side text if font is available
	var font = get_font("font")
	if font != null:
		draw_string(font, Vector2(X_WEST - 18, 25), "WEST", COLOR_TEXT)
		draw_string(font, Vector2(X_EAST - 14, 25), "EAST", COLOR_TEXT)
		draw_string(font, Vector2(X_INTERLINK - 16, Y_INTERLINK - 12), "LINK", COLOR_TEXT)

	# 1. Draw West Column vertical pipe segments
	for i in range(NUM_FLOORS - 1):
		var pos_a := Vector2(X_WEST, Y_BOTTOM - float(i) * Y_STEP)
		var pos_b := Vector2(X_WEST, Y_BOTTOM - float(i + 1) * Y_STEP)
		var seg_state = west_states[i] if i < west_states.size() else CoolantLeak.State.HEALTHY
		var col: Color = _get_pipe_color(int(seg_state), is_live)
		draw_line(pos_a, pos_b, col, 3.5, true)

	# 2. Draw East Column vertical pipe segments
	for i in range(NUM_FLOORS - 1):
		var pos_a := Vector2(X_EAST, Y_BOTTOM - float(i) * Y_STEP)
		var pos_b := Vector2(X_EAST, Y_BOTTOM - float(i + 1) * Y_STEP)
		var seg_state = east_states[i] if i < east_states.size() else CoolantLeak.State.HEALTHY
		var col: Color = _get_pipe_color(int(seg_state), is_live)
		draw_line(pos_a, pos_b, col, 3.5, true)

	# 3. Draw Interlink horizontal bridge segments
	var pos_west_bridge := Vector2(X_WEST, Y_INTERLINK)
	var pos_east_bridge := Vector2(X_EAST, Y_INTERLINK)
	var pos_interlink := Vector2(X_INTERLINK, Y_INTERLINK)
	var bridge_col: Color = _get_pipe_color(int(interlink_state), is_live)
	draw_line(pos_west_bridge, pos_interlink, bridge_col, 3.0, true)
	draw_line(pos_interlink, pos_east_bridge, bridge_col, 3.0, true)

	# 4. Draw West Column valve points
	for i in range(NUM_FLOORS):
		var pos := Vector2(X_WEST, Y_BOTTOM - float(i) * Y_STEP)
		var valve_node = west_valves[i] if i < west_valves.size() else null
		var v_col: Color = _get_valve_color(valve_node, is_live)
		draw_circle(pos, 6.5, v_col)
		if font != null:
			draw_string(font, Vector2(X_WEST - 32, pos.y + 4), "P%d" % i, COLOR_TEXT)

	# 5. Draw East Column valve points
	for i in range(NUM_FLOORS):
		var pos := Vector2(X_EAST, Y_BOTTOM - float(i) * Y_STEP)
		var valve_node = east_valves[i] if i < east_valves.size() else null
		var v_col: Color = _get_valve_color(valve_node, is_live)
		draw_circle(pos, 6.5, v_col)
		if font != null:
			draw_string(font, Vector2(X_EAST + 12, pos.y + 4), "P%d" % i, COLOR_TEXT)

	# 6. Draw Interlink valve point
	var il_col: Color = _get_valve_color(interlink_valve, is_live)
	draw_circle(pos_interlink, 7.5, il_col)


func _map_valves_to_layout(valves: Array) -> Dictionary:
	var west_valves := []
	var east_valves := []
	var interlink_valve = null

	var sorted_valves := valves.duplicate()
	sorted_valves.sort_custom(self, "_sort_by_floor_name")

	var unclassified := []

	for valve in sorted_valves:
		if not is_instance_valid(valve):
			continue
		var v_name: String = valve.name.to_lower()
		var p_name: String = _floor_label(valve).to_lower()

		if "interlink" in v_name or "interlink" in p_name:
			if interlink_valve == null:
				interlink_valve = valve
		elif "west" in v_name or "west" in p_name:
			west_valves.append(valve)
		elif "east" in v_name or "east" in p_name:
			east_valves.append(valve)
		else:
			unclassified.append(valve)

	# Distribute unclassified valves if explicit West/East names were not present
	for valve in unclassified:
		if west_valves.size() < NUM_FLOORS:
			west_valves.append(valve)
		elif east_valves.size() < NUM_FLOORS:
			east_valves.append(valve)
		elif interlink_valve == null:
			interlink_valve = valve

	return {
		"west": west_valves,
		"east": east_valves,
		"interlink": interlink_valve
	}


func _map_fissures_to_segments(patch_points: Array) -> Dictionary:
	var west_states := []
	var east_states := []
	for i in range(NUM_FLOORS - 1):
		west_states.append(CoolantLeak.State.HEALTHY)
		east_states.append(CoolantLeak.State.HEALTHY)
	var interlink_state = CoolantLeak.State.HEALTHY

	for patch_point in patch_points:
		if not is_instance_valid(patch_point):
			continue

		var is_patched: bool = patch_point.call("is_patched") if patch_point.has_method("is_patched") else false
		var is_firm: bool = patch_point.call("is_firmly_patched") if patch_point.has_method("is_firmly_patched") else false
		var leak_node = patch_point.get("_leak") if "_leak" in patch_point else null
		var leak_state = CoolantLeak.State.HEALTHY

		if leak_node and is_instance_valid(leak_node) and leak_node.has_method("get_state"):
			leak_state = leak_node.call("get_state")

		var effective_state = leak_state
		if is_patched:
			if is_firm:
				effective_state = CoolantLeak.State.HEALTHY
			else:
				effective_state = CoolantLeak.State.WARNING

		var label_str: String = _floor_label(patch_point).to_lower() + " " + patch_point.name.to_lower()
		var floor_idx: int = _extract_floor_index(label_str)

		if "interlink" in label_str:
			interlink_state = _more_severe_state(int(interlink_state), int(effective_state))
		elif "east" in label_str:
			var seg_idx: int = int(clamp(floor_idx, 0, NUM_FLOORS - 2))
			east_states[seg_idx] = _more_severe_state(int(east_states[seg_idx]), int(effective_state))
		else:
			# Default to West circuit or matched floor
			var seg_idx: int = int(clamp(floor_idx, 0, NUM_FLOORS - 2))
			west_states[seg_idx] = _more_severe_state(int(west_states[seg_idx]), int(effective_state))

	return {
		"west": west_states,
		"east": east_states,
		"interlink": interlink_state
	}


func _extract_floor_index(text: String) -> int:
	for i in range(NUM_FLOORS):
		if ("floor_" + str(i)) in text or ("floor" + str(i)) in text or ("piso_" + str(i)) in text or ("piso" + str(i)) in text:
			return i
	return 0


func _more_severe_state(state_a: int, state_b: int) -> int:
	var priority := {
		CoolantLeak.State.LEAKING: 4,
		CoolantLeak.State.WARNING: 3,
		CoolantLeak.State.DEPRESSURIZED: 2,
		CoolantLeak.State.HEALTHY: 1,
		CoolantLeak.State.SEALED: 0
	}
	var prio_a = priority.get(state_a, 0)
	var prio_b = priority.get(state_b, 0)
	if int(prio_b) > int(prio_a):
		return state_b
	return state_a


func _get_pipe_color(leak_state: int, is_live: bool) -> Color:
	if not is_live:
		return COLOR_OFFLINE_PIPE

	match leak_state:
		CoolantLeak.State.LEAKING:
			return COLOR_PIPE_LEAKING
		CoolantLeak.State.WARNING:
			return COLOR_PIPE_WARNING
		CoolantLeak.State.DEPRESSURIZED:
			return COLOR_PIPE_DEPRESSURIZED
		_:
			return COLOR_PIPE_HEALTHY


func _get_valve_color(valve_node: Node, is_live: bool) -> Color:
	if not is_live or valve_node == null or not is_instance_valid(valve_node):
		return COLOR_OFFLINE_VALVE

	var is_open: bool = bool(valve_node.get("is_active")) if "is_active" in valve_node else false
	if is_open:
		return COLOR_VALVE_OPEN
	else:
		return COLOR_VALVE_CLOSED


func _compute_state_hash() -> int:
	var h := 0
	var valves: Array = get_tree().get_nodes_in_group("coolant_valve")
	for v in valves:
		if is_instance_valid(v):
			var active: bool = bool(v.get("is_active")) if "is_active" in v else false
			h = h * 31 + (1 if active else 0)

	var patch_points: Array = get_tree().get_nodes_in_group("gloo_patchable")
	for p in patch_points:
		if is_instance_valid(p):
			var patched: bool = p.call("is_patched") if p.has_method("is_patched") else false
			var firm: bool = p.call("is_firmly_patched") if p.has_method("is_firmly_patched") else false
			var leak = p.get("_leak") if "_leak" in p else null
			var st: int = int(leak.call("get_state")) if (leak and is_instance_valid(leak) and leak.has_method("get_state")) else 0
			h = h * 31 + (1 if patched else 0) + (2 if firm else 0) + st * 10
	return h


func _sort_by_floor_name(a: Node, b: Node) -> bool:
	return _floor_label(a) < _floor_label(b)


func _floor_label(node: Node) -> String:
	var parent: Node = node.get_parent()
	if parent != null and parent.name.begins_with("Floor_"):
		return parent.name
	return node.name


func _request_redraw() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()
