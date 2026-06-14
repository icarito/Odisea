extends Area
class_name InteractableEntity

# InteractableEntity.gd - Component for interaction markers

export(Resource) var marker_config = null # Expects MarkerConfig

func _ready() -> void:
	add_to_group("interactable_entity")
	if marker_config:
		_register_with_system()

func _exit_tree() -> void:
	if Engine.has_singleton("InteractionMarker") or has_node("/root/InteractionMarker"):
		get_node("/root/InteractionMarker").unregister(self)

func _register_with_system() -> void:
	if Engine.has_singleton("InteractionMarker") or has_node("/root/InteractionMarker"):
		get_node("/root/InteractionMarker").register(self, marker_config)

func set_marker_config(new_config) -> void:
	marker_config = new_config
	if is_inside_tree():
		if Engine.has_singleton("InteractionMarker") or has_node("/root/InteractionMarker"):
			get_node("/root/InteractionMarker").update_config(self, marker_config)
