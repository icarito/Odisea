extends Spatial
class_name PlasmaRoute

# PlasmaRoute.gd - Valve sequence puzzle logic for plasma redirection (FD-257 / FD-255).
# Evaluates valve state pattern and triggers reroute on target PlasmaConduit.

# --- EXPORTED PROPERTIES ---
# NodePaths to PipeValve nodes or interactables emitting valve_state_changed(is_open)
export(Array, NodePath) var valve_paths: Array = []
# Required pattern of states (1 for open/active, 0 for closed/inactive) matching valve_paths order
export(PoolIntArray) var required_pattern: PoolIntArray = PoolIntArray()
# NodePath to the target PlasmaConduit instance
export(NodePath) var conduit_path: NodePath

# --- SIGNALS ---
signal route_solved()
signal route_broken()

# --- INTERNAL STATE ---
var _is_solved: bool = false
var _valve_nodes: Array = []


func _ready() -> void:
	add_to_group("replay_sync")
	call_deferred("_bind_valves")


func _bind_valves() -> void:
	_valve_nodes.clear()
	for path in valve_paths:
		if path == null or path.is_empty():
			_valve_nodes.append(null)
			continue
		var valve = get_node_or_null(path)
		if valve:
			_valve_nodes.append(valve)
			if valve.has_signal("valve_state_changed") and not valve.is_connected("valve_state_changed", self, "_on_valve_state_changed"):
				valve.connect("valve_state_changed", self, "_on_valve_state_changed")
		else:
			_valve_nodes.append(null)

	_check_route_state()


func _physics_process(_delta: float) -> void:
	# Included for replay_sync consistency if needed, logic is signal-driven
	pass


func _on_valve_state_changed(_is_open: bool) -> void:
	_check_route_state()


func _check_route_state() -> void:
	var matches_pattern: bool = _eval_pattern()

	if matches_pattern and not _is_solved:
		_is_solved = true
		emit_signal("route_solved")
		var conduit = get_conduit()
		if conduit and conduit.has_method("reroute"):
			conduit.reroute()
	elif not matches_pattern and _is_solved:
		_is_solved = false
		emit_signal("route_broken")
		var conduit = get_conduit()
		if conduit and conduit.has_method("trigger_overheat"):
			conduit.trigger_overheat()


func _eval_pattern() -> bool:
	if required_pattern.size() == 0:
		return false
	if valve_paths.size() != required_pattern.size():
		return false

	for i in range(required_pattern.size()):
		var expected: int = required_pattern[i]
		var actual: int = 0
		var valve = null
		if i < _valve_nodes.size():
			valve = _valve_nodes[i]

		if valve != null:
			if "is_active" in valve:
				actual = 1 if valve.is_active else 0
			elif valve.has_method("is_open"):
				actual = 1 if valve.is_open() else 0
			else:
				actual = 0
		else:
			actual = 0

		if actual != expected:
			return false

	return true


func get_conduit() -> Node:
	if conduit_path == null or conduit_path.is_empty():
		return null
	return get_node_or_null(conduit_path)


func is_solved() -> bool:
	return _is_solved


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"is_solved": _is_solved
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("is_solved"):
		_is_solved = bool(data["is_solved"])
	_check_route_state()
