extends Area
class_name InteractableEntity

# InteractableEntity.gd - Component for 3D interactables that supports UI Markers

export(Resource) var marker_config: Resource = null # Expected to be MarkerConfig

func _ready() -> void:
	_register_marker()

func _exit_tree() -> void:
	_unregister_marker()

func set_marker_config(new_config: Resource) -> void:
	marker_config = new_config
	if is_inside_tree():
		_register_marker()

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
