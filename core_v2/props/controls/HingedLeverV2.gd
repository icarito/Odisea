extends InteractableBaseV2
class_name HingedLeverV2

# HingedLeverV2.gd - Palanca de un modelo importado.
#
# Rota un nodo cualquiera del modelo alrededor de una bisagra dada, sin reparentarlo:
# los .glb de Sketchfab traen la geometria con el pivote en el origen del modelo, asi
# que rotar el nodo directamente lo haria girar alrededor del piso. La bisagra se
# declara en metros y en el espacio del prop (lo que se mide en el editor) y se
# convierte una sola vez al espacio del padre del nodo.
#
# La pose es funcion pura de anim_progress: nada de AnimationPlayer ni de tiempo real,
# para que el replay determinista siga valiendo.

export(NodePath) var handle_path := NodePath()
export(Vector3) var hinge_origin := Vector3.ZERO
export(Vector3) var hinge_axis := Vector3(1, 0, 0)
export(float) var angle_off_deg := 0.0
export(float) var angle_on_deg := -55.0

signal lever_toggled(is_on)

var _handle: Spatial = null
var _rest: Transform
var _pivot: Vector3
var _axis: Vector3

func _ready() -> void:
	_handle = get_node_or_null(handle_path) as Spatial
	if _handle != null:
		_rest = _handle.transform
		# Del espacio del prop al espacio del padre del nodo que rota.
		var to_parent: Transform = _handle.get_parent().global_transform.affine_inverse() * global_transform
		_pivot = to_parent.xform(hinge_origin)
		_axis = to_parent.basis.xform(hinge_axis).normalized()
		if _axis.length_squared() < 0.0001:
			_axis = Vector3(1, 0, 0)
	._ready()

func _update_visuals() -> void:
	if _handle == null:
		return
	var deg: float = lerp(angle_off_deg, angle_on_deg, _ease_in_out(anim_progress))
	var basis := Basis(_axis, deg2rad(deg))
	_handle.transform = Transform(basis, _pivot - basis.xform(_pivot)) * _rest

func _on_animation_completed() -> void:
	._on_animation_completed()
	emit_signal("lever_toggled", is_active)
