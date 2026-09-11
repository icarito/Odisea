extends Node
class_name ShipSystemBus

# ShipSystemBus.gd - Normalized query bus for the 4 ship systems (FD-296 F2)
# Read-only state aggregator. Does not implement simulation logic.

const STATE_OK := 0
const STATE_DEGRADADO := 1
const STATE_FALLO := 2
const STATE_OFFLINE := 3

signal systems_changed(summary)

export(Dictionary) var sources: Dictionary = {
	"criocoolant": NodePath(""),
	"plasma": NodePath(""),
	"atmosfera": NodePath(""),
	"energia": NodePath("")
}

var _summary: Dictionary = {}

func _ready() -> void:
	add_to_group("replay_sync")
	add_to_group("ship_system_bus")
	_bind_source_signals()
	evaluate_systems()

func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	evaluate_systems()

func set_sources(new_sources: Dictionary) -> void:
	for key in new_sources.keys():
		sources[key] = new_sources[key]
	_bind_source_signals()
	evaluate_systems()

func get_system_state(system_id: String) -> int:
	if _summary.has(system_id) and typeof(_summary[system_id]) == TYPE_DICTIONARY:
		return int(_summary[system_id].get("state", STATE_OFFLINE))
	return STATE_OFFLINE

func get_summary() -> Dictionary:
	return _summary.duplicate(true)

func evaluate_systems() -> void:
	var new_summary := {
		"criocoolant": _eval_criocoolant(),
		"plasma": _eval_plasma(),
		"atmosfera": _eval_atmosfera(),
		"energia": _eval_energia()
	}

	if not _are_summaries_equal(_summary, new_summary):
		_summary = new_summary.duplicate(true)
		emit_signal("systems_changed", get_summary())

func _resolve_node(target_val) -> Node:
	if target_val == null:
		return null
	if target_val is Node:
		return target_val
	var np: NodePath = NodePath("")
	if target_val is NodePath:
		np = target_val
	elif target_val is String:
		if (target_val as String).empty():
			return null
		np = NodePath(target_val)

	if np.is_empty():
		return null

	var resolved = get_node_or_null(np)
	if resolved != null:
		return resolved

	if is_inside_tree():
		var root = get_tree().root
		resolved = root.get_node_or_null(np)
		if resolved != null:
			return resolved

	return null

func _eval_criocoolant() -> Dictionary:
	var node = _resolve_node(sources.get("criocoolant", null))
	if node == null and is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("coolant_source")
		if not nodes.empty():
			node = nodes[0]

	if not is_instance_valid(node):
		return {"state": STATE_OFFLINE, "detail": "sin fuente"}

	var tank_level: float = 1.0
	if "tank_level" in node:
		tank_level = float(node.get("tank_level"))
	elif node.has_method("get_pressure"):
		tank_level = float(node.call("get_pressure"))

	var flow_active: bool = true
	if node.has_method("is_flow_active"):
		flow_active = bool(node.call("is_flow_active"))

	if tank_level <= 0.0:
		return {"state": STATE_FALLO, "detail": "Tanque vacío"}
	elif tank_level < 0.5 or not flow_active:
		return {"state": STATE_DEGRADADO, "detail": "Nivel o flujo bajo"}
	else:
		return {"state": STATE_OK, "detail": "Operativo"}

func _eval_plasma() -> Dictionary:
	var node = _resolve_node(sources.get("plasma", null))
	if node == null and is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("plasma_conduit")
		if nodes.empty():
			nodes = get_tree().get_nodes_in_group("plasma_route")
		if not nodes.empty():
			node = nodes[0]

	if not is_instance_valid(node):
		return {"state": STATE_OFFLINE, "detail": "sin fuente"}

	if node.has_method("get_state"):
		var st: int = int(node.call("get_state"))
		match st:
			0: return {"state": STATE_OK, "detail": "Nominal"}
			1: return {"state": STATE_DEGRADADO, "detail": "Sobrecalentamiento"}
			2: return {"state": STATE_FALLO, "detail": "Fuga de plasma"}
			3: return {"state": STATE_OK, "detail": "Redirigido"}
	elif node.has_method("is_solved"):
		if bool(node.call("is_solved")):
			return {"state": STATE_OK, "detail": "Ruta resuelta"}
		else:
			return {"state": STATE_DEGRADADO, "detail": "Ruta inactiva"}

	return {"state": STATE_OK, "detail": "Operativo"}

func _eval_atmosfera() -> Dictionary:
	var node = _resolve_node(sources.get("atmosfera", null))
	if node == null and is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("pressure_section")
		if not nodes.empty():
			node = nodes[0]

	if not is_instance_valid(node):
		return {"state": STATE_OFFLINE, "detail": "sin fuente"}

	if node.has_method("get_state"):
		var st: int = int(node.call("get_state"))
		match st:
			0: return {"state": STATE_OK, "detail": "Presión estable"}
			1: return {"state": STATE_DEGRADADO, "detail": "Sobrepresión"}
			2, 3: return {"state": STATE_FALLO, "detail": "Descompresión crítica"}

	return {"state": STATE_OK, "detail": "Estable"}

func _eval_energia() -> Dictionary:
	var node = _resolve_node(sources.get("energia", null))
	if node == null and is_inside_tree():
		var nodes = get_tree().get_nodes_in_group("aux_power")
		if not nodes.empty():
			node = nodes[0]

	if not is_instance_valid(node):
		return {"state": STATE_OFFLINE, "detail": "sin fuente"}

	if node.has_method("is_powered") and node.has_method("get_state"):
		var st: int = int(node.call("get_state"))
		match st:
			0: return {"state": STATE_OK, "detail": "Alimentación nominal"}
			2: return {"state": STATE_DEGRADADO, "detail": "Restableciendo"}
			1: return {"state": STATE_FALLO, "detail": "Sin energía"}

	if node.has_method("is_powered"):
		if bool(node.call("is_powered")):
			return {"state": STATE_OK, "detail": "Alimentación nominal"}
		else:
			return {"state": STATE_FALLO, "detail": "Sin energía"}

	return {"state": STATE_OK, "detail": "Energizado"}

func _bind_source_signals() -> void:
	for sys in sources.keys():
		var node = _resolve_node(sources[sys])
		if is_instance_valid(node):
			if node.has_signal("state_changed") and not node.is_connected("state_changed", self, "_on_source_state_changed"):
				node.connect("state_changed", self, "_on_source_state_changed")
			if node.has_signal("level_changed") and not node.is_connected("level_changed", self, "_on_source_state_changed"):
				node.connect("level_changed", self, "_on_source_state_changed")

func _on_source_state_changed(_arg = null) -> void:
	evaluate_systems()

func _are_summaries_equal(s1: Dictionary, s2: Dictionary) -> bool:
	if s1.size() != s2.size():
		return false
	for k in s1.keys():
		if not s2.has(k):
			return false
		var d1 = s1[k]
		var d2 = s2[k]
		if typeof(d1) != typeof(d2):
			return false
		if typeof(d1) == TYPE_DICTIONARY:
			if int(d1.get("state", -1)) != int(d2.get("state", -1)) or String(d1.get("detail", "")) != String(d2.get("detail", "")):
				return false
		elif d1 != d2:
			return false
	return true

func get_snapshot() -> Dictionary:
	var sources_snap: Dictionary = {}
	for k in sources.keys():
		var val = sources[k]
		if val is NodePath or val is String:
			sources_snap[k] = String(val)
		elif val is Node and is_instance_valid(val):
			sources_snap[k] = String(get_path_to(val))

	return {
		"sources": sources_snap,
		"summary": _summary.duplicate(true)
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("sources") and typeof(data["sources"]) == TYPE_DICTIONARY:
		var snap_srcs: Dictionary = data["sources"]
		for k in snap_srcs.keys():
			sources[k] = NodePath(String(snap_srcs[k]))
		_bind_source_signals()

	if data.has("summary") and typeof(data["summary"]) == TYPE_DICTIONARY:
		_summary = data["summary"].duplicate(true)
		emit_signal("systems_changed", get_summary())
	else:
		evaluate_systems()
