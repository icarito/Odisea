tool
extends Spatial
class_name PipeManometer

# PipeManometer.gd - Dial manometer prop reading circuit pressure (FD-264 §4).
# Displays circuit pressure = f(flow_intensity, tank_level, leak_factor) via needle rotation.

export(NodePath) var flow_adapter_path: NodePath
export(NodePath) var tank_path: NodePath
export(NodePath) var leak_path: NodePath

export(float, 0.0, 10.0) var max_pressure: float = 5.0
export(float, 0.0, 180.0) var needle_max_angle_deg: float = 140.0
export(int) var segment_index: int = 1

var _flow_adapter = null
var _tank = null
var _leak = null

var _current_pressure: float = 0.0
var _needle: Spatial = null


func _ready() -> void:
	add_to_group("replay_sync")
	_needle = get_node_or_null("Needle")
	_resolve_references()
	_update_pressure()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_update_pressure()


func _resolve_references() -> void:
	if flow_adapter_path != null and not flow_adapter_path.is_empty():
		_flow_adapter = get_node_or_null(flow_adapter_path)
	if tank_path != null and not tank_path.is_empty():
		_tank = get_node_or_null(tank_path)
	if leak_path != null and not leak_path.is_empty():
		_leak = get_node_or_null(leak_path)


func _update_pressure() -> void:
	_resolve_references()

	var tank_level := 1.0
	if _tank != null:
		tank_level = _tank.tank_level

	var flow_intensity := 1.0
	if _flow_adapter != null and _flow_adapter.has_method("get_segment_inflow"):
		flow_intensity = _flow_adapter.get_segment_inflow(segment_index)
	elif _flow_adapter != null:
		flow_intensity = _flow_adapter.get_computed_intensity()

	var leak_factor := 0.0
	if _leak != null:
		leak_factor = _leak.get_leak_intensity()

	# Pressure formula: f(flow, level, leak)
	var pressure := flow_intensity * tank_level * max(0.0, 1.0 - leak_factor * 0.6) * max_pressure
	_current_pressure = max(0.0, pressure)

	_update_visuals()


func get_pressure() -> float:
	return _current_pressure


var _manometer = null

func _update_visuals() -> void:
	if _manometer == null:
		_manometer = get_node_or_null("Manometer")
	if _needle == null:
		_needle = get_node_or_null("Needle")

	var ratio := clamp(_current_pressure / max(0.001, max_pressure), 0.0, 1.0)

	if _manometer and _manometer.has_method("set_pressure_value"):
		_manometer.set_pressure_value(ratio)

	if _needle:
		var angle_rad := deg2rad(ratio * needle_max_angle_deg)
		_needle.rotation.z = -angle_rad


func get_snapshot() -> Dictionary:
	return {
		"current_pressure": _current_pressure
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("current_pressure"):
		_current_pressure = float(data["current_pressure"])
	_update_visuals()
