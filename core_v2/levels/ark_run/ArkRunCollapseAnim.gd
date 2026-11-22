extends Reference

# FD-324 F5 — helper determinista de fallas y colapso cinematico (decision #9).
#
# Concentra el plan de fallas estatico por hash(seed, indice), el colapso
# cinematico de 1 s sin RigidBody (interpola con el helper puro de
# ArkRunTerraceConversion) y el estado de cada pieza. ArkRunEngineIgnition lo usa
# y re-emite sus señales; los tests de F5 siguen viendo la misma API publica.
# Sin randf()/randomize(): mismo seed e indices => mismas decisiones y poses.

const ConversionScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceConversion.gd")
const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const COLLAPSE_DURATION := 1.0
const FAIL_PERCENT := 380

var _collapses: Array = []

static func should_fail_index(p_seed: int, index: int, percent: int = FAIL_PERCENT) -> bool:
	return (_hash_index(p_seed, index) % 1000) < int(clamp(percent, 0, 1000))

static func _hash_index(p_seed: int, index: int) -> int:
	var h := (p_seed * 2654435761 + index * 40503 + 0x9E3779B1) & 0x7fffffff
	h = (h ^ (h >> 13)) & 0x7fffffff
	h = (h * 1274126177 + 12345) & 0x7fffffff
	return (h ^ (h >> 16)) & 0x7fffffff

# Aplica fallas a ascensores y compuertas; devuelve el resumen y las claves de
# los colapsos que arrancaron (para que el dueno emita sus señales).
func plan_failures(elevators: Array, streamer, p_seed: int, percent: int = FAIL_PERCENT) -> Dictionary:
	var started: Array = []
	if streamer != null and is_instance_valid(streamer) and streamer.has_method("apply_gravity_mode"):
		streamer.apply_gravity_mode(Catalog.GRAVITY_AXIAL)
	var sorted: Array = _sorted_elevators(elevators)
	var decisions: Array = []
	var failed := 0
	for index in range(sorted.size()):
		var elevator = sorted[index]["node"]
		var fails: bool = should_fail_index(p_seed, index, percent)
		if elevator.has_method("set_operational"):
			elevator.set_operational(not fails)
		if fails:
			failed += 1
			if _start(elevator, "elevator:" + str(sorted[index]["key"]), index, p_seed):
				started.append("elevator:" + str(sorted[index]["key"]))
		decisions.append({
			"key": str(sorted[index]["key"]), "index": index, "failed": fails, "operational": not fails,
		})
	for gate in _blocked_connections(streamer):
		if _start(gate["node"], gate["key"], gate["index"], p_seed):
			started.append(gate["key"])
	var summary := {
		"mode": Catalog.GRAVITY_AXIAL, "elevators": decisions.size(), "failed": failed,
		"hash": ((p_seed * 31 + decisions.size() * 7919 + failed * 104729) ^ (decisions.size() * 17)) & 0x7fffffff,
		"decisions": decisions,
	}
	return {"summary": summary, "started": started}

# Compuertas de conexion bloqueadas por AXIAL: cada una colapsa.
func _blocked_connections(streamer) -> Array:
	var gates = []
	if streamer == null or not is_instance_valid(streamer):
		return gates
	var gate_shapes = streamer.get("_gate_shapes")
	var route = streamer.get("_route_state")
	if typeof(gate_shapes) != TYPE_DICTIONARY or typeof(route) != TYPE_DICTIONARY:
		return gates
	var keys: Array = gate_shapes.keys()
	keys.sort()
	for i in range(keys.size()):
		var gkey := str(keys[i])
		var decision: Dictionary = route.get(gkey, {})
		if decision.empty() or bool(decision.get("relinked", false)):
			continue
		gates.append({"node": gate_shapes[keys[i]], "key": "conn:" + gkey, "index": 1000 + i})
	return gates

func advance(delta: float) -> Array:
	var completed: Array = []
	var dt := max(delta, 0.0)
	for entry in _collapses:
		if bool(entry["done"]):
			continue
		entry["elapsed"] = float(entry["elapsed"]) + dt
		var u: float = ConversionScript.collapse_progress(float(entry["elapsed"]), COLLAPSE_DURATION)
		entry["u"] = u
		_set_world_xf(entry["node"], ConversionScript.sample_collapse(
			entry["base"], u, entry["direction"], entry["angle"], entry["drop"]))
		if u >= 1.0:
			entry["done"] = true
			completed.append(entry["key"])
	return completed

func get_keys() -> Array:
	var keys := []
	for entry in _collapses:
		keys.append(str(entry["key"]))
	return keys

func get_state(key: String) -> Dictionary:
	for entry in _collapses:
		if str(entry["key"]) == key:
			return {
				"node": entry["node"], "base": entry["base"], "direction": entry["direction"],
				"angle": entry["angle"], "drop": entry["drop"], "u": entry["u"], "done": entry["done"],
			}
	return {}

func _start(node, key: String, hash_index: int, p_seed: int) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for entry in _collapses:
		if entry["node"] == node:
			return false
	var h := _hash_index(p_seed, hash_index)
	_collapses.append({
		"node": node, "key": key, "base": _world_xf(node),
		"direction": Vector3(0.0, 0.0, -1.0 if (h & 1) == 0 else 1.0),
		"angle": deg2rad(8.0 + float(h % 7)), "drop": 0.4 + float((h >> 3) % 5) * 0.1,
		"elapsed": 0.0, "u": 0.0, "done": false,
	})
	return true

func _sorted_elevators(elevators: Array) -> Array:
	var entries := []
	for index in range(elevators.size()):
		var elevator = elevators[index]
		if elevator == null or not is_instance_valid(elevator):
			continue
		var parent = elevator.get_parent()
		var key := ("%s/%s" % [str(parent.name), str(elevator.name)]) if parent != null else ("e%03d" % index)
		entries.append({"key": key, "node": elevator})
	entries.sort_custom(self, "_sort_entry")
	return entries

func _sort_entry(a, b) -> bool: return str(a["key"]) < str(b["key"])

func _world_xf(node) -> Transform:
	return node.global_transform if node.is_inside_tree() else node.transform

func _set_world_xf(node, xform: Transform) -> void:
	if node.is_inside_tree():
		node.global_transform = xform
	else:
		node.transform = xform
