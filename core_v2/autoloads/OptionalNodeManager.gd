extends Node

const SWITCH_PLATFORM_NAME := "Switch"
const SWITCH_KEEP_GROUP := "switch_keep"
const SWITCH_PRUNE_CLASSES := [
	"DirectionalLight",
	"GIProbe",
	"ReflectionProbe",
	"Particles",
	"CPUParticles"
]

var _optional_enabled: bool = true
var _config_loaded: bool = false
var _is_switch_platform := false

signal optional_nodes_toggled(enabled)

func _ready() -> void:
	_is_switch_platform = OS.get_name() == SWITCH_PLATFORM_NAME
	_load_config()
	_register_input_actions()
	_connect_tree_signals()
	_apply_initial_state()

func _load_config() -> void:
	if _is_switch_platform:
		# On Switch optional content is forced off for performance.
		_optional_enabled = false
		_config_loaded = true
		return
	if ProjectSettings.has_setting("application/config/optional_nodes_enabled"):
		_optional_enabled = ProjectSettings.get_setting("application/config/optional_nodes_enabled")
	else:
		_optional_enabled = true
	_config_loaded = true

func _connect_tree_signals() -> void:
	var tree := get_tree()
	if not tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.connect("node_added", self, "_on_tree_node_added")

func _register_input_actions() -> void:
	if not InputMap.has_action("toggle_optional_nodes"):
		var event = InputEventKey.new()
		event.scancode = KEY_F10
		InputMap.add_action("toggle_optional_nodes")
		InputMap.action_add_event("toggle_optional_nodes", event)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_optional_nodes"):
		if _is_switch_platform:
			# Keep F10 behavior on other platforms, but lock low-spec mode on Switch.
			return
		toggle_optional_nodes()

func _apply_initial_state() -> void:
	_update_all_optional_nodes()

func _update_all_optional_nodes() -> void:
	var optional_nodes = get_tree().get_nodes_in_group("optional")
	for node in optional_nodes:
		if not is_instance_valid(node):
			continue
		if _is_switch_platform and not _optional_enabled:
			if node.is_in_group(SWITCH_KEEP_GROUP):
				_apply_switch_runtime_optimizations(node)
				continue
			_prune_node(node)
			continue
		_set_node_optional_state(node, _optional_enabled)
	emit_signal("optional_nodes_toggled", _optional_enabled)

func _on_tree_node_added(node: Node) -> void:
	call_deferred("_apply_node_policy", node)

func _apply_node_policy(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if _is_switch_platform:
		if _should_prune_on_switch(node):
			_prune_node(node)
			return
		_apply_switch_runtime_optimizations(node)
		return

	if _is_optional_or_under_optional(node):
		_set_node_optional_state(node, _optional_enabled)

func _should_prune_on_switch(node: Node) -> bool:
	if node.is_in_group(SWITCH_KEEP_GROUP):
		return false
	if _is_optional_or_under_optional(node):
		return true
	return node.get_class() in SWITCH_PRUNE_CLASSES

func _is_optional_or_under_optional(node: Node) -> bool:
	if node.is_in_group("optional"):
		return true
	var current := node.get_parent()
	while current != null:
		if current.is_in_group("optional"):
			return true
		current = current.get_parent()
	return false

func _prune_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group(SWITCH_KEEP_GROUP):
		return
	if node.is_queued_for_deletion():
		return
	node.queue_free()

func _apply_switch_runtime_optimizations(node: Node) -> void:
	if node is Light:
		node.shadow_enabled = false
	if node is Particles:
		node.emitting = false
	if node is CPUParticles:
		node.emitting = false
	if node is WorldEnvironment and node.environment:
		node.environment.glow_enabled = false
		node.environment.ssao_enabled = false
		node.environment.dof_blur_near_enabled = false
		node.environment.dof_blur_far_enabled = false
		node.environment.adjustment_enabled = false

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
	if _is_switch_platform:
		return
	_optional_enabled = not _optional_enabled
	_update_all_optional_nodes()
	print("[OptionalNodeManager] Optional nodes: ", "ENABLED" if _optional_enabled else "DISABLED")

func set_optional_nodes_enabled(enabled: bool) -> void:
	if _is_switch_platform:
		_optional_enabled = false
		return
	if _optional_enabled != enabled:
		_optional_enabled = enabled
		_update_all_optional_nodes()

func is_optional_enabled() -> bool:
	return _optional_enabled

func get_optional_node_count() -> int:
	return get_tree().get_nodes_in_group("optional").size()
