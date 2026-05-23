extends Node
class_name DynamicGravityProxy

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

export(NodePath) var body_path := NodePath("")
export(NodePath) var reference_body_path := NodePath("")
export(bool) var enabled := true
export(bool) var affect_only_spin_modes := true
export(float) var gravity_strength := 9.81
export(bool) var use_radial := true
export(Vector3) var axis_origin := Vector3.ZERO
export(Vector3) var axis_direction := Vector3.UP
export(bool) var use_coriolis := false
export(float) var angular_velocity_rad_s := 0.0
export(float) var coriolis_scale := 1.0
export(float) var coriolis_max_accel := 25.0
export(float) var max_effect_distance := 80.0
export(bool) var sleep_when_far := true

var last_applied_acceleration := Vector3.ZERO
var last_effect_active := false

func _ready() -> void:
	set_physics_process(enabled)

func _physics_process(_delta: float) -> void:
	if not enabled:
		last_effect_active = false
		last_applied_acceleration = Vector3.ZERO
		return

	var body: Node = _resolve_body()
	if body == null:
		last_effect_active = false
		last_applied_acceleration = Vector3.ZERO
		return

	if not _is_effect_active_for_body(body):
		last_effect_active = false
		last_applied_acceleration = Vector3.ZERO
		return

	var velocity: Vector3 = _get_body_velocity(body)
	var accel: Vector3 = calculate_acceleration_at(_get_body_position(body), velocity)
	last_applied_acceleration = accel
	last_effect_active = accel.length_squared() > 0.000001

	if body is RigidBody:
		var rb: RigidBody = body as RigidBody
		rb.add_central_force(accel * max(0.001, rb.mass))

func calculate_acceleration_at(global_position: Vector3, velocity: Vector3 = Vector3.ZERO, gravity_mode: int = -1) -> Vector3:
	var mode: int = gravity_mode
	if mode < 0:
		mode = _get_gravity_mode_at(global_position)

	if mode == GravityModes.Mode.ZERO_G:
		return Vector3.ZERO
	if affect_only_spin_modes and not GravityModes.is_spin(mode):
		return Vector3.ZERO

	var gravity: Vector3
	if use_radial:
		gravity = get_radial_gravity(global_position, gravity_strength)
	else:
		gravity = Vector3.DOWN * gravity_strength

	if use_coriolis:
		gravity += get_coriolis_acceleration(velocity)

	return gravity

func get_radial_gravity(global_position: Vector3, strength: float = -1.0) -> Vector3:
	var axis_dir: Vector3 = _get_axis_direction()
	var rel: Vector3 = global_position - axis_origin
	var radial: Vector3 = rel - axis_dir * rel.dot(axis_dir)
	if radial.length_squared() <= 0.000001:
		return Vector3.DOWN * _resolve_strength(strength)
	return radial.normalized() * _resolve_strength(strength)

func get_coriolis_acceleration(velocity: Vector3) -> Vector3:
	if not use_coriolis:
		return Vector3.ZERO
	var omega_mag: float = angular_velocity_rad_s
	if omega_mag <= 0.0 and has_node("/root/GravityWorld"):
		var gw = get_node("/root/GravityWorld")
		if gw and "ship_angular_velocity_rad_s" in gw:
			omega_mag = gw.ship_angular_velocity_rad_s
	if omega_mag <= 0.0:
		return Vector3.ZERO

	var omega: Vector3 = _get_axis_direction() * omega_mag
	var accel: Vector3 = -2.0 * omega.cross(velocity) * coriolis_scale
	if coriolis_max_accel > 0.0 and accel.length() > coriolis_max_accel:
		accel = accel.normalized() * coriolis_max_accel
	return accel

func is_effect_active() -> bool:
	var body: Node = _resolve_body()
	return body != null and _is_effect_active_for_body(body)

func get_last_acceleration() -> Vector3:
	return last_applied_acceleration

func _resolve_body() -> Node:
	if not body_path.is_empty():
		var node: Node = get_node_or_null(body_path)
		if node:
			return node
	var parent: Node = get_parent()
	if parent:
		return parent
	return null

func _resolve_reference_body() -> Spatial:
	if not reference_body_path.is_empty():
		var node: Node = get_node_or_null(reference_body_path)
		if node is Spatial:
			return node as Spatial
	var players: Array = get_tree().get_nodes_in_group("player") if is_inside_tree() else []
	for player in players:
		if player is Spatial and is_instance_valid(player):
			return player as Spatial
	return null

func _is_effect_active_for_body(body: Node) -> bool:
	if sleep_when_far and max_effect_distance > 0.0:
		var reference: Spatial = _resolve_reference_body()
		if reference:
			var distance: float = reference.global_transform.origin.distance_to(_get_body_position(body))
			if distance > max_effect_distance:
				return false
	return true

func _get_body_position(body: Node) -> Vector3:
	if body is Spatial:
		return (body as Spatial).global_transform.origin
	return Vector3.ZERO

func _get_body_velocity(body: Node) -> Vector3:
	if body is RigidBody:
		return (body as RigidBody).linear_velocity
	if "velocity" in body:
		var value = body.get("velocity")
		if value is Vector3:
			return value
	return Vector3.ZERO

func _get_gravity_mode_at(global_position: Vector3) -> int:
	if has_node("/root/GravityWorld"):
		var gw = get_node("/root/GravityWorld")
		if gw and gw.has_method("get_gravity_mode_at"):
			return int(gw.get_gravity_mode_at(global_position))
	return GravityModes.Mode.SPIN_DYNAMIC

func _get_axis_direction() -> Vector3:
	var dir: Vector3 = axis_direction
	if dir.length_squared() <= 0.000001 and has_node("/root/GravityWorld"):
		var gw = get_node("/root/GravityWorld")
		if gw and "ship_axis_direction" in gw:
			dir = gw.ship_axis_direction
	if dir.length_squared() <= 0.000001:
		dir = Vector3.UP
	return dir.normalized()

func _resolve_strength(strength: float) -> float:
	if strength >= 0.0:
		return strength
	return gravity_strength
