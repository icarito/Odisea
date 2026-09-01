extends Node
class_name LightGroup

# LightGroup.gd - Declarative switch-to-lights binding component.
# Connects a switch (or any node emitting activated/deactivated) to a set of light props
# specified by NodePaths and/or a scene group name.

export(NodePath) var switch_path
export(Array, NodePath) var light_paths = []
export(String) var scene_group := ""

var _switch_node: Node = null
var _target_lights: Array = []

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	add_to_group("replay_sync")
	if switch_path:
		_switch_node = get_node_or_null(switch_path)
		if _switch_node:
			_connect_switch_signals(_switch_node)

	_resolve_targets()
	call_deferred("_apply_initial")

func _connect_switch_signals(node: Node) -> void:
	if node.has_signal("activated") and not node.is_connected("activated", self, "_on_switch_activated"):
		node.connect("activated", self, "_on_switch_activated")
	if node.has_signal("deactivated") and not node.is_connected("deactivated", self, "_on_switch_deactivated"):
		node.connect("deactivated", self, "_on_switch_deactivated")

func _on_switch_activated() -> void:
	_set_all(true)

func _on_switch_deactivated() -> void:
	_set_all(false)

func _resolve_targets() -> void:
	_target_lights.clear()

	# Resolve light_paths
	for path in light_paths:
		if path:
			var target = get_node_or_null(path)
			if is_instance_valid(target) and not _target_lights.has(target):
				_target_lights.append(target)

	# Resolve scene_group
	if scene_group != "" and is_inside_tree():
		var group_nodes = get_tree().get_nodes_in_group(scene_group)
		for node in group_nodes:
			if is_instance_valid(node) and not _target_lights.has(node):
				_target_lights.append(node)

func _apply_initial() -> void:
	_resolve_targets()
	if is_instance_valid(_switch_node):
		var active_state := false
		if "is_active" in _switch_node:
			active_state = bool(_switch_node.get("is_active"))
		_set_all(active_state)

func _set_all(value: bool) -> void:
	for target in _target_lights:
		if not is_instance_valid(target):
			continue

		if target.has_method("set_active"):
			target.call("set_active", value)
		elif "is_active" in target:
			target.set("is_active", value)
		elif target is Light:
			target.visible = value

# --- REPLAY SYSTEM (Snapshot Serialization) ---

func get_snapshot() -> Dictionary:
	var active_state := false
	if is_instance_valid(_switch_node) and "is_active" in _switch_node:
		active_state = bool(_switch_node.get("is_active"))

	return {
		"switch_active": active_state
	}

func restore_snapshot(data: Dictionary) -> void:
	var active_state: bool = data.get("switch_active", false)
	if is_instance_valid(_switch_node):
		if _switch_node.has_method("set_active"):
			_switch_node.call("set_active", active_state, true)
		elif "is_active" in _switch_node:
			_switch_node.set("is_active", active_state)

	_resolve_targets()
	_set_all(active_state)
