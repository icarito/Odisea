extends Node
class_name CoolantFlowAdapter

# CoolantFlowAdapter.gd - Visual-Logical adapter for cryocoolant flow (FD-264 §2 / FD-266).
# Reads OCLS circuit state, valve states, and tank supply to compute branch flow,
# write speed/intensity to PipeCoolantRun nodes, and drain the tank based on active leaks.

export(NodePath) var circuit_manager_path: NodePath
export(NodePath) var tank_path: NodePath
export(Array, NodePath) var valves: Array = []
export(Array, NodePath) var leaks: Array = []
export(Array, NodePath) var pipe_runs: Array = []

export(float, 0.0, 4.0) var normal_flow_speed: float = 0.7
export(float, 0.0, 3.0) var normal_flow_intensity: float = 1.0

var _manager = null
var _tank = null
var _last_computed_flow: bool = false
var _last_computed_speed: float = 0.0
var _last_computed_intensity: float = 0.0


func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("coolant_adapter")
	_resolve_references()
	update_flow(0.0)


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return
	update_flow(delta)


func _resolve_references() -> void:
	if circuit_manager_path != null and not circuit_manager_path.is_empty():
		_manager = get_node_or_null(circuit_manager_path)
	if tank_path != null and not tank_path.is_empty():
		_tank = get_node_or_null(tank_path)


func update_flow(delta: float = 0.0) -> void:
	_resolve_references()

	var tank_level := 1.0
	if _tank != null:
		tank_level = _tank.tank_level

	var all_valves_open := true
	for valve_path in valves:
		var valve = get_node_or_null(valve_path)
		if valve != null:
			if "is_active" in valve:
				if not bool(valve.get("is_active")):
					all_valves_open = false
					break
			elif "starts_active" in valve:
				if not bool(valve.get("starts_active")):
					all_valves_open = false
					break

	var flow_active := (all_valves_open) and (tank_level > 0.0)

	var active_leak_factor := 0.0
	var total_leak_intensity := 0.0

	if flow_active:
		for leak_path in leaks:
			var leak_node = get_node_or_null(leak_path)
			if leak_node != null:
				if leak_node.has_method("get_leak_intensity"):
					var intensity: float = float(leak_node.call("get_leak_intensity"))
					if intensity > active_leak_factor:
						active_leak_factor = intensity
					total_leak_intensity += intensity

		if delta > 0.0 and _tank != null and total_leak_intensity > 0.0:
			var drain: float = total_leak_intensity * float(_tank.get("drain_rate")) * delta
			_tank.set_tank_level(max(0.0, _tank.tank_level - drain))

	var target_speed := normal_flow_speed if flow_active else 0.0
	var target_intensity := (normal_flow_intensity * tank_level) if flow_active else 0.0

	if active_leak_factor > 0.0 and flow_active:
		target_intensity = max(0.1, target_intensity * (1.0 - active_leak_factor * 0.4))

	_last_computed_flow = flow_active
	_last_computed_speed = target_speed
	_last_computed_intensity = target_intensity

	for pr_path in pipe_runs:
		var pr = get_node_or_null(pr_path)
		if pr != null and pr.has_method("set_flow_speed") and pr.has_method("set_flow_intensity"):
			pr.call("set_flow_speed", target_speed)
			pr.call("set_flow_intensity", target_intensity)


func is_flow_active() -> bool:
	return _last_computed_flow


func get_computed_speed() -> float:
	return _last_computed_speed


func get_computed_intensity() -> float:
	return _last_computed_intensity


func get_snapshot() -> Dictionary:
	return {
		"flow": _last_computed_flow,
		"speed": _last_computed_speed,
		"intensity": _last_computed_intensity
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("flow"):
		_last_computed_flow = bool(data["flow"])
	if data.has("speed"):
		_last_computed_speed = float(data["speed"])
	if data.has("intensity"):
		_last_computed_intensity = float(data["intensity"])
	update_flow(0.0)
