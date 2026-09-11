extends Area
class_name InteractableEntity

# InteractableEntity.gd - Component for 3D interactables that supports UI Markers & HUDable OdiseaOS screens

export(Resource) var marker_config: Resource = null # Expected to be MarkerConfig
export(NodePath) var hudable_component_path: NodePath = ""

var _hudable_node: Node = null

func _ready() -> void:
	_register_marker()
	_setup_hudable()

func _exit_tree() -> void:
	_unregister_marker()

func set_marker_config(new_config: Resource) -> void:
	marker_config = new_config
	if is_inside_tree():
		_register_marker()

func get_hudable() -> Node:
	if is_instance_valid(_hudable_node):
		return _hudable_node
	_setup_hudable()
	return _hudable_node

func set_hudable_component(node: Node) -> void:
	_hudable_node = node

func _setup_hudable() -> void:
	if not hudable_component_path.is_empty():
		var node = get_node_or_null(hudable_component_path)
		if is_instance_valid(node):
			_hudable_node = node
			return

	for child in get_children():
		if child is HUDableComponent or child.has_method("screen_id"):
			_hudable_node = child
			break

func _register_marker() -> void:
	if marker_config and has_node("/root/InteractionMarker"):
		var marker_system = get_node("/root/InteractionMarker")
		if marker_system.has_method("register"):
			marker_system.register(self, marker_config)

func _unregister_marker() -> void:
	if has_node("/root/InteractionMarker"):
		var marker_system = get_node("/root/InteractionMarker")
		if marker_system.has_method("unregister"):
			marker_system.unregister(self)
