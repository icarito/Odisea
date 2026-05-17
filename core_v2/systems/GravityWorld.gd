extends Node

# GravityWorld — autoload que centraliza el estado de gravedad del nivel.
#
# Primera pasada (FD-036): registra el WorldRotator activo del nivel y expone
# una API global para que cualquier sistema pueda cambiar la plataforma activa
# sin necesidad de conocer la jerarquia de escenas.
#
# Uso desde OYS o GDScript:
#   GravityWorld.navigate_to(my_platform_node)
#   GravityWorld.set_spiral_blend(0.5)

signal world_rotator_registered(rotator)
signal world_rotator_unregistered()
signal platform_changed(platform_node)

var _rotator: Spatial = null  # WorldRotator activo

export(Vector3) var ship_axis_origin := Vector3.ZERO
export(Vector3) var ship_axis_direction := Vector3.UP
export(float) var one_g_strength := 9.81
export(float) var centrifugal_reference_radius := 460.0
export(float) var ship_angular_velocity_rad_s := 0.0
export(float, 0.0, 1.0) var gravity_blend := 0.0

# API publica

# Registra el WorldRotator del nivel actual. Lo llama WorldRotator en _ready().
func register_rotator(rotator: Spatial) -> void:
	_rotator = rotator
	if _rotator.has_signal("platform_changed"):
		if not _rotator.is_connected("platform_changed", self, "_on_platform_changed"):
			_rotator.connect("platform_changed", self, "_on_platform_changed")
	emit_signal("world_rotator_registered", rotator)

# Elimina el WorldRotator registrado (llamado en _exit_tree del WorldRotator).
func unregister_rotator(rotator: Spatial) -> void:
	if _rotator == rotator:
		if _rotator.has_signal("platform_changed"):
			if _rotator.is_connected("platform_changed", self, "_on_platform_changed"):
				_rotator.disconnect("platform_changed", self, "_on_platform_changed")
		_rotator = null
		emit_signal("world_rotator_unregistered")

# Cambia la plataforma activa. Delega al WorldRotator registrado.
func navigate_to(platform_node: Spatial) -> void:
	if _rotator and _rotator.has_method("navigate_to"):
		_rotator.navigate_to(platform_node)

# Cicla a la siguiente plataforma registrada.
func navigate_next() -> void:
	if _rotator and _rotator.has_method("navigate_next"):
		_rotator.navigate_next()

# Cicla a la plataforma anterior.
func navigate_prev() -> void:
	if _rotator and _rotator.has_method("navigate_prev"):
		_rotator.navigate_prev()

# Ajusta el blend visual de las espiras (0=axial, 1=centrifugo).
func set_spiral_blend(value: float) -> void:
	gravity_blend = clamp(value, 0.0, 1.0)
	if _rotator and is_instance_valid(_rotator):
		_rotator.spiral_blend = value

func get_spiral_blend() -> float:
	if _rotator and is_instance_valid(_rotator):
		return _rotator.spiral_blend
	return gravity_blend

func set_gravity_blend(value: float) -> void:
	set_spiral_blend(value)

func get_gravity_blend() -> float:
	return get_spiral_blend()

func is_centrifugal_mode() -> bool:
	return get_gravity_blend() > 0.001

func set_ship_axis(origin: Vector3, direction: Vector3) -> void:
	ship_axis_origin = origin
	if direction.length_squared() > 0.001:
		ship_axis_direction = direction.normalized()

func set_centrifugal_reference_radius(radius: float) -> void:
	centrifugal_reference_radius = max(radius, 0.001)

func set_ship_angular_velocity(value: float) -> void:
	ship_angular_velocity_rad_s = max(value, 0.0)

func get_default_angular_velocity_for_one_g(radius: float = -1.0) -> float:
	var r: float = radius if radius > 0.001 else centrifugal_reference_radius
	return sqrt(one_g_strength / max(r, 0.001))

func get_canonical_gravity_direction(canonical_position: Vector3) -> Vector3:
	if not is_centrifugal_mode():
		return Vector3.DOWN
	var radial: Vector3 = get_axis_radial_vector(canonical_position)
	if radial.length_squared() <= 0.001:
		return Vector3.DOWN
	return radial.normalized()

func get_canonical_up_direction(canonical_position: Vector3) -> Vector3:
	return -get_canonical_gravity_direction(canonical_position)

func get_gravity_strength(canonical_position: Vector3) -> float:
	if not is_centrifugal_mode():
		return one_g_strength
	var radius: float = get_axis_radius(canonical_position)
	if ship_angular_velocity_rad_s > 0.0:
		return ship_angular_velocity_rad_s * ship_angular_velocity_rad_s * radius
	return one_g_strength * (radius / max(centrifugal_reference_radius, 0.001))

func get_canonical_gravity(canonical_position: Vector3) -> Vector3:
	return get_canonical_gravity_direction(canonical_position) * get_gravity_strength(canonical_position)

func get_physical_gravity(global_position: Vector3) -> Vector3:
	var canonical_position: Vector3 = global_position
	if _rotator and _rotator.has_method("to_canonical"):
		canonical_position = _rotator.to_canonical(global_position)
	var canonical_gravity: Vector3 = get_canonical_gravity(canonical_position)
	if _rotator:
		return _rotator.global_transform.basis.xform(canonical_gravity)
	return canonical_gravity

func get_axis_radius(canonical_position: Vector3) -> float:
	return get_axis_radial_vector(canonical_position).length()

func get_axis_radial_vector(canonical_position: Vector3) -> Vector3:
	var axis_dir: Vector3 = ship_axis_direction.normalized()
	if axis_dir.length_squared() <= 0.001:
		axis_dir = Vector3.UP
	var rel: Vector3 = canonical_position - ship_axis_origin
	return rel - axis_dir * rel.dot(axis_dir)

# Devuelve el WorldRotator activo, o null si no hay ninguno registrado.
func get_rotator() -> Spatial:
	if _rotator and not is_instance_valid(_rotator):
		_rotator = null
	return _rotator

# Devuelve true si hay un WorldRotator activo.
func has_rotator() -> bool:
	return _rotator != null

# Callbacks internos

func _on_platform_changed(platform_node) -> void:
	emit_signal("platform_changed", platform_node)
