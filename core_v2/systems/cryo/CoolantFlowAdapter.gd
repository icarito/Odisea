extends Node
class_name CoolantFlowAdapter

# CoolantFlowAdapter.gd - Visual-Logical adapter for cryocoolant flow per segment (FD-270 / FD-266).
# Computes branch flow per segment using PipeNetworkResource topology, applies speed/intensity
# to individual PipeCoolantRun nodes, and drains the tank based on active topology leaks.

export(Resource) var network
export(String) var branch_id: String = ""

export(float, 0.0, 4.0) var normal_flow_speed: float = 0.7
export(float, 0.0, 3.0) var normal_flow_intensity: float = 1.0

var _tank: Node = null
var _resolved_segments: Array = [] # Array of Dictionary {pipe_run, valve, leak, leak_path, valve_path, pipe_run_path}
var _segment_flows: Array = [] # Array of float 0..1


func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("coolant_adapter")
	_resolve_references()
	compute_flow()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	# Tank drain calculation for active leaks in this branch
	var tank_level := 1.0
	if _tank != null and "tank_level" in _tank:
		tank_level = float(_tank.tank_level)

	if delta > 0.0 and _tank != null and tank_level > 0.0:
		var total_leak_drain := 0.0
		var carrying := 1.0 if tank_level > 0.0 else 0.0

		for i in range(_resolved_segments.size()):
			var seg = _resolved_segments[i]
			var valve = seg.get("valve")
			if valve != null and not _is_valve_open(valve):
				carrying = 0.0

			var leak = seg.get("leak")
			var leak_intensity := 0.0
			if leak != null and leak.has_method("get_leak_intensity"):
				leak_intensity = float(leak.call("get_leak_intensity"))

			if carrying > 0.0 and leak_intensity > 0.0:
				total_leak_drain += carrying * leak_intensity

			carrying = carrying * (1.0 - leak_intensity)

		if total_leak_drain > 0.0 and "drain_rate" in _tank:
			var drain_rate: float = float(_tank.get("drain_rate"))
			var drain: float = total_leak_drain * drain_rate * delta
			_tank.set_tank_level(max(0.0, tank_level - drain))

	# Recompute flow if leaks are ramping up/down or tank drained
	if _has_active_leaks() or (_tank != null and "tank_level" in _tank and float(_tank.tank_level) != tank_level):
		compute_flow()


func _get_target_node(path_val) -> Node:
	if path_val == null:
		return null
	var np: NodePath
	if path_val is NodePath:
		np = path_val
	elif path_val is String:
		if path_val == "":
			return null
		np = NodePath(path_val)
	else:
		return null
	if np.is_empty():
		return null

	var n = get_node_or_null(np)
	if n != null:
		return n
	var parent = get_parent()
	if parent != null:
		n = parent.get_node_or_null(np)
		if n != null:
			return n
	return null


func _resolve_references() -> void:
	_resolved_segments.clear()
	_segment_flows.clear()
	_tank = null

	if network == null or not (network is Resource):
		return

	var branches_raw = network.get("branches")
	if not (branches_raw is Dictionary):
		return
	var branches: Dictionary = branches_raw
	if not branches.has(branch_id):
		return

	var branch_data: Dictionary = branches[branch_id]

	# Resolve tank
	var tank_path = branch_data.get("tank", null)
	_tank = _get_target_node(tank_path)

	# Resolve segments
	var segments = branch_data.get("segments", [])
	if not (segments is Array):
		return

	for idx in range(segments.size()):
		var seg_data = segments[idx]
		if not (seg_data is Dictionary):
			continue

		var pipe_run_path = seg_data.get("pipe_run", null)
		var valve_path = seg_data.get("valve", null)
		var leak_path = seg_data.get("leak", null)

		var pipe_run_node: Node = _get_target_node(pipe_run_path)
		var valve_node: Node = _get_target_node(valve_path)
		var leak_node: Node = _get_target_node(leak_path)

		if valve_node != null and valve_node.has_signal("valve_state_changed"):
			if not valve_node.is_connected("valve_state_changed", self, "_on_valve_state_changed"):
				valve_node.connect("valve_state_changed", self, "_on_valve_state_changed")

		if leak_node != null and leak_node.has_signal("state_changed"):
			if not leak_node.is_connected("state_changed", self, "_on_leak_state_changed"):
				leak_node.connect("state_changed", self, "_on_leak_state_changed")

		_resolved_segments.append({
			"pipe_run": pipe_run_node,
			"valve": valve_node,
			"leak": leak_node,
			"pipe_run_path": pipe_run_path,
			"valve_path": valve_path,
			"leak_path": leak_path
		})
		_segment_flows.append(0.0)


func compute_flow() -> void:
	var num_segments := _resolved_segments.size()
	if _segment_flows.size() != num_segments:
		_segment_flows.resize(num_segments)

	var tank_level := 1.0
	if _tank != null and "tank_level" in _tank:
		tank_level = float(_tank.tank_level)

	var carrying := 1.0 if tank_level > 0.0 else 0.0

	for i in range(num_segments):
		var seg = _resolved_segments[i]
		var valve = seg.get("valve")
		if valve != null and not _is_valve_open(valve):
			carrying = 0.0

		var f := carrying
		var leak = seg.get("leak")
		if leak != null and leak.has_method("get_leak_intensity"):
			var leak_intensity: float = float(leak.call("get_leak_intensity"))
			f = carrying * (1.0 - leak_intensity)

		_segment_flows[i] = f
		carrying = f

		var pr = seg.get("pipe_run")
		if pr != null:
			if pr.has_method("set_flow_speed"):
				pr.call("set_flow_speed", normal_flow_speed * f)
			if pr.has_method("set_flow_intensity"):
				pr.call("set_flow_intensity", normal_flow_intensity * f)


func get_segment_flow(index: int) -> float:
	if index >= 0 and index < _segment_flows.size():
		return float(_segment_flows[index])
	return 0.0


func is_pressurized_at(node: Node) -> bool:
	if node == null:
		return false

	for i in range(_resolved_segments.size()):
		var seg = _resolved_segments[i]
		if seg.get("leak") == node or seg.get("pipe_run") == node or seg.get("valve") == node:
			return get_segment_flow(i) > 0.0

		# Check by resolved node path
		var leak_path = seg.get("leak_path")
		if leak_path != null and (leak_path is NodePath or leak_path is String):
			if _get_target_node(leak_path) == node:
				return get_segment_flow(i) > 0.0

	return false


func is_flow_active() -> bool:
	return get_segment_flow(0) > 0.0


func get_computed_speed() -> float:
	return normal_flow_speed * get_segment_flow(0)


func get_computed_intensity() -> float:
	return normal_flow_intensity * get_segment_flow(0)


func _on_valve_state_changed(_is_open: bool = false) -> void:
	compute_flow()


func _on_leak_state_changed(_new_state: int = 0) -> void:
	compute_flow()


func _is_valve_open(valve: Node) -> bool:
	if valve == null:
		return true
	if valve.has_method("is_open"):
		return bool(valve.call("is_open"))
	if "is_active" in valve:
		return bool(valve.get("is_active"))
	if "starts_active" in valve:
		return bool(valve.get("starts_active"))
	return true


func _has_active_leaks() -> bool:
	for seg in _resolved_segments:
		var leak = seg.get("leak")
		if leak != null and leak.has_method("get_leak_intensity"):
			if float(leak.call("get_leak_intensity")) > 0.0:
				return true
	return false


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"segment_flows": _segment_flows.duplicate()
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("segment_flows"):
		var flows: Array = data["segment_flows"]
		_segment_flows = flows.duplicate()
		for i in range(min(_segment_flows.size(), _resolved_segments.size())):
			var f: float = float(_segment_flows[i])
			var pr = _resolved_segments[i].get("pipe_run")
			if pr != null:
				if pr.has_method("set_flow_speed"):
					pr.call("set_flow_speed", normal_flow_speed * f)
				if pr.has_method("set_flow_intensity"):
					pr.call("set_flow_intensity", normal_flow_intensity * f)
