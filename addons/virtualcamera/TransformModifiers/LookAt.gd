tool
extends "res://addons/virtualcamera/TransformModifiers/TransformModifier.gd"

class_name LookAt

export var look_at_target : NodePath
export var look_at_lerp_t : float = 1.0
export var look_at_offset : Vector3 = Vector3.ZERO

var rotation_internal : Quat = Quat.IDENTITY

# Cache del perfilador: buscar el autoload por path en cada tick cuesta, y ese costo
# alcanza para que un replay pierda pasos de fisica y derive. Se resuelve una vez.
var _pm_perfil = null
var _pm_perfil_buscado := false

func has_look_at_target() -> bool:
	return not look_at_target.is_empty()

func _physics_process(delta : float):
	# Envoltorio de perfilado (ver PerformanceMonitor.perfil_corrida_iniciar): el cuerpo
	# puede tener varios return, asi que se mide desde afuera y no por dentro.
	if not _pm_perfil_buscado:
		_pm_perfil_buscado = true
		_pm_perfil = get_node_or_null("/root/PerformanceMonitor")
	if _pm_perfil != null and _pm_perfil._perfil_corrida_on:
		_pm_perfil.perfil_inicio("LookAt")
		_paso_fisica(delta)
		_pm_perfil.perfil_fin("LookAt")
		return
	_paso_fisica(delta)

func _paso_fisica(delta : float):
	if has_look_at_target():
		var target = get_node_or_null(self.look_at_target)
		if target != null:
			var target_dist = global_transform.origin - target.global_transform.origin
			if target_dist.length_squared() > 0 and target_dist.normalized().abs() != Vector3.UP:
				rotation = rotation_internal.get_euler()
				look_at(target.global_transform.origin + self.look_at_offset, Vector3.UP)
				rotation_internal = rotation_internal.slerp(Quat(rotation), self.look_at_lerp_t)
				rotation = rotation_internal.get_euler()
		else:
			self.look_at_target = NodePath()
