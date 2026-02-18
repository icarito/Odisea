extends Node

var _optional_enabled: bool = true
var _config_loaded: bool = false

signal optional_nodes_toggled(enabled: bool)

func _ready() -> void:
	_load_config()
	_register_input_actions()
	_apply_initial_state()

func _load_config() -> void:
	var config = ProjectSettings.get_setting("application/config/optional_nodes_enabled", true)
	_optional_enabled = config
	_config_loaded = true

func _register_input_actions() -> void:
	if not InputMap.has_action("toggle_optional_nodes"):
		var event = InputEventKey.new()
		event.scancode = KEY_F10
		InputMap.add_action("toggle_optional_nodes")
		InputMap.action_add_event("toggle_optional_nodes", event)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_optional_nodes"):
		toggle_optional_nodes()

func _apply_initial_state() -> void:
	_update_all_optional_nodes()

func _update_all_optional_nodes() -> void:
	var optional_nodes = get_tree().get_nodes_in_group("optional")
	for node in optional_nodes:
		_set_node_optional_state(node, _optional_enabled)
	emit_signal("optional_nodes_toggled", _optional_enabled)

func _set_node_optional_state(node: Node, enabled: bool) -> void:
	if node is Spatial:
		node.visible = enabled
	if node is CanvasItem:
		node.visible = enabled
	if node.has_method("set_process"):
		node.set_process(enabled)
	if node.has_method("set_physics_process"):
		node.set_physics_process(enabled)
	if node is CollisionObject:
		if enabled:
			node.set_deferred("monitoring", true)
			node.set_deferred("monitorable", true)
		else:
			node.set_deferred("monitoring", false)
			node.set_deferred("monitorable", false)

func toggle_optional_nodes() -> void:
	_optional_enabled = not _optional_enabled
	_update_all_optional_nodes()
	print("[OptionalNodeManager] Optional nodes: ", "ENABLED" if _optional_enabled else "DISABLED")

func set_optional_nodes_enabled(enabled: bool) -> void:
	if _optional_enabled != enabled:
		_optional_enabled = enabled
		_update_all_optional_nodes()

func is_optional_enabled() -> bool:
	return _optional_enabled

func get_optional_node_count() -> int:
	return get_tree().get_nodes_in_group("optional").size()
