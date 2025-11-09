extends OmniLight3D
## Mantiene la luz siempre encima del objeto objetivo en coordenadas de mundo

@export var target_path: NodePath = NodePath("../Nota")
@export var height: float = 0.12

var _target: Node3D

func _ready():
	if target_path != NodePath():
		_target = get_node_or_null(target_path)
	if _target == null:
		# Intento fallback buscando por nombre exacto
		_target = get_parent().get_node_or_null("Nota")

func _process(_dt: float) -> void:
	if _target:
		global_position = _target.global_position + Vector3(0.0, height, 0.0)
