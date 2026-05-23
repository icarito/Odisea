extends Node

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

# GravityWorld — autoload que centraliza el estado de gravedad del nivel.
#
# FD-040 formaliza tres caminos:
#   - STANDARD_1G/SPIN_WALKABLE: PlayerControllerV2 + WorldRotator.
#   - ZERO_G: ControllerManager cambia a ZeroGravityController.
#   - SPIN_DYNAMIC: opt-in para props via DynamicGravityProxy.
#
# Uso desde OYS o GDScript:
#   GravityWorld.navigate_to(my_platform_node)
#   GravityWorld.set_spiral_blend(0.5)
#   GravityWorld.set_gravity_mode(GravityModes.Mode.ZERO_G)

signal world_rotator_registered(rotator)
signal world_rotator_unregistered()
signal platform_changed(platform_node)
signal gravity_mode_changed(mode, previous_mode)
signal gravity_zone_registered(zone)
signal gravity_zone_unregistered(zone)

var _rotator: Spatial = null  # WorldRotator activo
var _zones: Array = []
var _current_mode: int = GravityModes.Mode.STANDARD_1G

export(int, "STANDARD_1G", "SPIN_WALKABLE", "ZERO_G", "SPIN_DYNAMIC") var default_mode := 0
export(Vector3) var ship_axis_origin := Vector3.ZERO
export(Vector3) var ship_axis_direction := Vector3.UP
export(float) var one_g_strength := 9.81
export(float) var centrifugal_reference_radius := 460.0
export(float) var ship_angular_velocity_rad_s := 0.0
export(float, 0.0, 1.0) var gravity_blend := 0.0

# API publica

func _ready() -> void:
	if GravityModes.is_valid_mode(default_mode):
		_current_mode = default_mode

# Registra el WorldRotator del nivel actual. Lo llama WorldRotator en _ready().
func register_rotator(rotator: Spatial) -> void:
	_rotator = rotator
	if _rotator.has_signal("platform_changed"):
		if not _rotator.is_connected("platform_changed", self, "_on_platform_changed"):
			_rotator.connect("platform_changed", self, "_on_platform_changed")
	if "spiral_blend" in _rotator:
		gravity_blend = clamp(_rotator.spiral_blend, 0.0, 1.0)
		_update_walkable_mode_from_blend()
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
	_update_walkable_mode_from_blend()

func get_spiral_blend() -> float:
	if _rotator and is_instance_valid(_rotator):
		return _rotator.spiral_blend
	return gravity_blend

func set_gravity_blend(value: float) -> void:
	set_spiral_blend(value)

func get_gravity_blend() -> float:
	return get_spiral_blend()

func is_centrifugal_mode() -> bool:
	if _current_mode == GravityModes.Mode.ZERO_G:
		return false
	return GravityModes.is_spin(_current_mode) or get_gravity_blend() > 0.001

func set_gravity_mode(mode: int) -> void:
	if not GravityModes.is_valid_mode(mode):
		push_error("[GravityWorld] Invalid gravity mode: %s" % str(mode))
		return
	if mode == _current_mode:
		return
	var previous_mode: int = _current_mode
	_current_mode = mode
	emit_signal("gravity_mode_changed", _current_mode, previous_mode)

func get_current_gravity_mode() -> int:
	return _current_mode

func get_gravity_mode_name(mode: int = -1) -> String:
	if mode < 0:
		mode = _current_mode
	return GravityModes.mode_name(mode)

func register_zone(zone: Node) -> void:
	if zone == null or _zones.has(zone):
		return
	_zones.append(zone)
	emit_signal("gravity_zone_registered", zone)

func unregister_zone(zone: Node) -> void:
	if _zones.has(zone):
		_zones.erase(zone)
		emit_signal("gravity_zone_unregistered", zone)

func get_registered_zones() -> Array:
	return _zones.duplicate()

func get_active_zone_at(global_position: Vector3) -> Node:
	var best_zone: Node = null
	var best_priority: int = -2147483648
	var best_volume: float = INF

	for zone in _zones:
		if not is_instance_valid(zone):
			continue
		if not _zone_contains_position(zone, global_position):
			continue
		var priority: int = _get_zone_priority(zone)
		var volume: float = _get_zone_volume(zone)
		if best_zone == null or priority > best_priority or (priority == best_priority and volume < best_volume):
			best_zone = zone
			best_priority = priority
			best_volume = volume

	return best_zone

func get_gravity_mode_at(global_position: Vector3) -> int:
	var zone: Node = get_active_zone_at(global_position)
	if zone:
		return _get_zone_mode(zone)
	return _current_mode

func should_use_zero_g_controller(global_position: Vector3) -> bool:
	return get_gravity_mode_at(global_position) == GravityModes.Mode.ZERO_G

func get_target_basis_for_player(global_position: Vector3) -> Basis:
	var zone: Node = get_active_zone_at(global_position)
	if zone:
		if zone.has_method("get_target_basis"):
			var zone_basis = zone.call("get_target_basis", global_position)
			if zone_basis is Basis:
				return zone_basis
		if "target_basis" in zone and zone.get("target_basis") is Basis:
			return zone.get("target_basis")
	if _rotator and is_instance_valid(_rotator):
		if _rotator.has_method("get_selected_plate_global_transform"):
			return _rotator.get_selected_plate_global_transform().basis
		return _rotator.global_transform.basis
	return Basis.IDENTITY

func get_dynamic_gravity_for_body(body: Node) -> Dictionary:
	var global_position := Vector3.ZERO
	if body is Spatial:
		global_position = (body as Spatial).global_transform.origin
	var mode: int = get_gravity_mode_at(global_position)
	var gravity: Vector3 = Vector3.ZERO
	if mode != GravityModes.Mode.ZERO_G:
		gravity = get_physical_gravity(global_position)
	var zone: Node = get_active_zone_at(global_position)
	return {
		"mode": mode,
		"mode_name": GravityModes.mode_name(mode),
		"gravity": gravity,
		"down": gravity.normalized() if gravity.length_squared() > 0.000001 else Vector3.ZERO,
		"strength": gravity.length(),
		"allow_coriolis": _zone_allows_coriolis(zone),
		"affect_props": _zone_affects_props(zone),
		"zone": zone
	}

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
	var gravity: Vector3 = get_canonical_gravity(canonical_position)
	if gravity.length_squared() <= 0.000001:
		return Vector3.DOWN
	return gravity.normalized()

func get_canonical_gravity_direction_for_mode(canonical_position: Vector3, mode: int) -> Vector3:
	var gravity: Vector3 = get_canonical_gravity_for_mode(canonical_position, mode)
	if gravity.length_squared() <= 0.000001:
		return Vector3.DOWN
	return gravity.normalized()

func _get_canonical_gravity_direction_for_mode(canonical_position: Vector3, mode: int, include_blend: bool) -> Vector3:
	if not _uses_radial_gravity(mode, include_blend):
		return Vector3.DOWN
	var radial: Vector3 = get_axis_radial_vector(canonical_position)
	if radial.length_squared() <= 0.001:
		return Vector3.DOWN
	return radial.normalized()

func get_canonical_up_direction(canonical_position: Vector3) -> Vector3:
	return -get_canonical_gravity_direction(canonical_position)

func get_gravity_strength(canonical_position: Vector3) -> float:
	return get_canonical_gravity(canonical_position).length()

func get_gravity_strength_for_mode(canonical_position: Vector3, mode: int) -> float:
	return get_canonical_gravity_for_mode(canonical_position, mode).length()

func _get_gravity_strength_for_mode(canonical_position: Vector3, mode: int, include_blend: bool) -> float:
	if not _uses_radial_gravity(mode, include_blend):
		return one_g_strength
	var radius: float = get_axis_radius(canonical_position)
	if ship_angular_velocity_rad_s > 0.0:
		return ship_angular_velocity_rad_s * ship_angular_velocity_rad_s * radius
	return one_g_strength * (radius / max(centrifugal_reference_radius, 0.001))

func get_canonical_gravity(canonical_position: Vector3) -> Vector3:
	return _get_canonical_gravity_for_mode(canonical_position, _current_mode, true)

func get_canonical_gravity_for_mode(canonical_position: Vector3, mode: int) -> Vector3:
	return _get_canonical_gravity_for_mode(canonical_position, mode, true)

func _get_canonical_gravity_for_mode(canonical_position: Vector3, mode: int, include_blend: bool) -> Vector3:
	if mode == GravityModes.Mode.ZERO_G:
		return Vector3.ZERO
	var standard_gravity: Vector3 = Vector3.DOWN * one_g_strength
	if mode == GravityModes.Mode.SPIN_DYNAMIC:
		return _get_centrifugal_gravity(canonical_position)
	if mode == GravityModes.Mode.SPIN_WALKABLE and not include_blend:
		return _get_centrifugal_gravity(canonical_position)
	if not include_blend:
		return standard_gravity
	var blend: float = clamp(get_gravity_blend(), 0.0, 1.0)
	if blend <= 0.001:
		return standard_gravity
	var centrifugal_gravity: Vector3 = _get_centrifugal_gravity(canonical_position)
	if blend >= 0.999:
		return centrifugal_gravity
	return standard_gravity.linear_interpolate(centrifugal_gravity, blend)

func _get_centrifugal_gravity(canonical_position: Vector3) -> Vector3:
	var radial: Vector3 = get_axis_radial_vector(canonical_position)
	if radial.length_squared() <= 0.001:
		return Vector3.DOWN * one_g_strength
	var strength: float = _get_gravity_strength_for_mode(canonical_position, GravityModes.Mode.SPIN_WALKABLE, false)
	return radial.normalized() * strength

func get_physical_gravity(global_position: Vector3) -> Vector3:
	var zone: Node = get_active_zone_at(global_position)
	var mode: int = _get_zone_mode(zone) if zone else _current_mode
	if mode == GravityModes.Mode.ZERO_G:
		return Vector3.ZERO
	var canonical_position: Vector3 = global_position
	if _rotator and _rotator.has_method("to_canonical"):
		canonical_position = _rotator.to_canonical(global_position)
	var include_blend: bool = zone == null
	var canonical_gravity: Vector3 = _get_canonical_gravity_for_mode(canonical_position, mode, include_blend)
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

func get_snapshot() -> Dictionary:
	return {
		"gravity_mode": _current_mode,
		"gravity_blend": gravity_blend,
		"ship_axis_origin": [ship_axis_origin.x, ship_axis_origin.y, ship_axis_origin.z],
		"ship_axis_direction": [ship_axis_direction.x, ship_axis_direction.y, ship_axis_direction.z],
		"centrifugal_reference_radius": centrifugal_reference_radius,
		"ship_angular_velocity_rad_s": ship_angular_velocity_rad_s
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("gravity_mode"):
		set_gravity_mode(int(data["gravity_mode"]))
	if data.has("gravity_blend"):
		gravity_blend = clamp(float(data["gravity_blend"]), 0.0, 1.0)
	if data.has("ship_axis_origin"):
		var origin = data["ship_axis_origin"]
		if origin is Array and origin.size() >= 3:
			ship_axis_origin = Vector3(origin[0], origin[1], origin[2])
	if data.has("ship_axis_direction"):
		var direction = data["ship_axis_direction"]
		if direction is Array and direction.size() >= 3:
			set_ship_axis(ship_axis_origin, Vector3(direction[0], direction[1], direction[2]))
	if data.has("centrifugal_reference_radius"):
		set_centrifugal_reference_radius(float(data["centrifugal_reference_radius"]))
	if data.has("ship_angular_velocity_rad_s"):
		set_ship_angular_velocity(float(data["ship_angular_velocity_rad_s"]))

# Callbacks internos

func _on_platform_changed(platform_node) -> void:
	emit_signal("platform_changed", platform_node)

func _update_walkable_mode_from_blend() -> void:
	if _current_mode == GravityModes.Mode.ZERO_G or _current_mode == GravityModes.Mode.SPIN_DYNAMIC:
		return
	if gravity_blend > 0.001:
		set_gravity_mode(GravityModes.Mode.SPIN_WALKABLE)
	else:
		set_gravity_mode(GravityModes.Mode.STANDARD_1G)

func _uses_radial_gravity(mode: int, include_blend: bool) -> bool:
	if mode == GravityModes.Mode.ZERO_G:
		return false
	if GravityModes.is_spin(mode):
		return true
	return include_blend and get_gravity_blend() > 0.001

func _zone_contains_position(zone: Node, global_position: Vector3) -> bool:
	if zone.has_method("contains_global_point"):
		return bool(zone.call("contains_global_point", global_position))
	if zone is Area:
		return _area_contains_position(zone as Area, global_position)
	return false

func _area_contains_position(area: Area, global_position: Vector3) -> bool:
	for child in area.get_children():
		if not child is CollisionShape:
			continue
		var shape_node: CollisionShape = child as CollisionShape
		if shape_node.disabled or shape_node.shape == null:
			continue
		var local: Vector3 = shape_node.global_transform.affine_inverse().xform(global_position)
		var shape: Shape = shape_node.shape
		if shape is BoxShape:
			var e: Vector3 = (shape as BoxShape).extents
			if abs(local.x) <= e.x and abs(local.y) <= e.y and abs(local.z) <= e.z:
				return true
		elif shape is SphereShape:
			if local.length() <= (shape as SphereShape).radius:
				return true
		elif shape is CapsuleShape:
			var capsule: CapsuleShape = shape as CapsuleShape
			var half_height: float = max(0.0, capsule.height * 0.5)
			var y: float = clamp(local.y, -half_height, half_height)
			if Vector3(local.x, local.y - y, local.z).length() <= capsule.radius:
				return true
	return false

func _get_zone_priority(zone: Node) -> int:
	if zone.has_method("get_gravity_priority"):
		return int(zone.call("get_gravity_priority"))
	if "gravity_priority" in zone:
		return int(zone.get("gravity_priority"))
	if "priority" in zone:
		return int(zone.get("priority"))
	return 0

func _get_zone_volume(zone: Node) -> float:
	if zone.has_method("get_volume"):
		return float(zone.call("get_volume"))
	return INF

func _get_zone_mode(zone: Node) -> int:
	if zone.has_method("get_gravity_mode"):
		return int(zone.call("get_gravity_mode"))
	if "gravity_mode" in zone:
		return int(zone.get("gravity_mode"))
	return _current_mode

func _zone_allows_coriolis(zone: Node) -> bool:
	if zone == null:
		return false
	if "allow_coriolis" in zone:
		return bool(zone.get("allow_coriolis"))
	if zone.has_method("allows_coriolis"):
		return bool(zone.call("allows_coriolis"))
	return false

func _zone_affects_props(zone: Node) -> bool:
	if zone == null:
		return false
	if "affect_props" in zone:
		return bool(zone.get("affect_props"))
	if zone.has_method("affects_props"):
		return bool(zone.call("affects_props"))
	return false
