extends Node
class_name RandomLeakSeeder

# RandomLeakSeeder.gd - Deterministic random leak selector for coolant puzzles (FD-270 / FD-266).
# Selects a subset of pre-placed CoolantLeak candidates at game startup using a seeded RNG
# and Fisher-Yates shuffle. Replay compatible via "replay_sync" snapshots.

# --- EXPORTED PROPERTIES ---
export(int) var seed_value := 42
export(int) var leak_count := 2
export(Array, NodePath) var candidate_leak_paths := []

# --- INTERNAL STATE ---
var _active_leak_paths: Array = []
var _is_activated: bool = false


func _get_property_list() -> Array:
	return [
		{
			"name": "seed",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT
		}
	]


func _set(property: String, value) -> bool:
	if property == "seed":
		seed_value = int(value)
		return true
	return false


func _get(property: String):
	if property == "seed":
		return seed_value
	return null


func _ready() -> void:
	add_to_group("replay_sync")

	if _active_leak_paths.empty():
		_draw_active_leaks()

	# La escena empieza sana: ColdRuptureEvent decide cuándo liberar la selección.
	# Mantener el sorteo listo conserva el seed para una activación explícita/replay.


func activate_leaks() -> void:
	if _is_activated:
		return
	if _active_leak_paths.empty():
		_draw_active_leaks()
	_is_activated = true
	_activate_leaks()


func _draw_active_leaks() -> void:
	if candidate_leak_paths.empty():
		_active_leak_paths = []
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var shuffled := candidate_leak_paths.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	var count: int = int(min(leak_count, shuffled.size()))
	if count < 0:
		count = 0

	_active_leak_paths = []
	for idx in range(count):
		_active_leak_paths.append(shuffled[idx])


func _activate_leaks() -> void:
	for path_val in _active_leak_paths:
		var leak_node: Node = _get_target_node(path_val)
		if leak_node != null and leak_node.has_method("trigger_leak"):
			leak_node.call("trigger_leak")


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


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	var str_paths: Array = []
	for path in _active_leak_paths:
		str_paths.append(str(path))
	return {
		"seed": seed_value,
		"active_leak_paths": str_paths,
		"is_activated": _is_activated
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("seed"):
		seed_value = int(data["seed"])
	if data.has("active_leak_paths"):
		var paths_raw = data["active_leak_paths"]
		if paths_raw is Array:
			_active_leak_paths = []
			for p in paths_raw:
				_active_leak_paths.append(NodePath(str(p)))
	if data.has("is_activated"):
		_is_activated = bool(data["is_activated"])
	if _is_activated and is_inside_tree():
		_activate_leaks()
