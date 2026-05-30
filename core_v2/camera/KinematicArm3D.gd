# A GTA style arm for cameras
# Will only shorten the arm if the end is intersecting an obstacle
# So the arm can intersect small obstacles without shortening
# NOTE, the end of the arm extends out from the - z axis
class_name KinematicArm3D
extends Spatial

const LATCH_POSE_TRANSLATION_EPSILON := 0.025
const LATCH_POSE_DIRECTION_DOT_EPSILON := 0.00015

# The shape of the end of the arm (the "rolling ball")
export var collider_shape: Shape setget set_collider_shape

# the initial length of the arm
export var current_length := 7.0

# the closest the end of the arm can be to the origin of this node
export var min_length := 0.5

# the length the arm will try to extend to
export var spring_length := 7.0 # Renamed target_length to spring_length for compatibility with SpringArm
export var target_length := 7.0 # Keeping this for internal use or alias, but spring_length is the primary property manipulated by the player controller.

# Smoothing speed while extending back to target length (lower = smoother).
export var extend_weight := 6.0

# Smoothing speed while retracting on obstacle hit (higher = less clipping).
export var retract_weight := 18.0

# Legacy single-weight control kept for backward compatibility with old scenes.
export var weight := -1.0

# Small safety margin so camera stays slightly away from colliders.
export var collision_padding := 0.12

# Ignore tiny hit-length fluctuations to reduce wall jitter on dense geometry.
export var collision_jitter_epsilon := 0.035

# Keep contact with the same obstacle latched until the hit meaningfully changes.
export var collision_hold_epsilon := 0.08

# Require a clearly farther hit before releasing a collision latch around corners.
export var collision_release_hysteresis := 0.18

# Farther hits must persist briefly before we let the arm extend again.
export var collision_release_delay := 0.1

# Briefly keep the last stable hit when the cast flickers to "no collision".
export var collision_miss_grace := 0.22

# Moving doors can clear while the camera/player are idle, so release a stale
# latch after a short grace even if the pivot and direction did not change.
export var collision_stationary_release_delay := 0.25

# When contact is finally released, expand more gently than the regular orbit zoom.
export var collision_clear_extend_weight := 1.4

# Speed used when retracting due to collision correction.
export var collision_shrink_weight := 10.0

# paths to objects which the arm won't collide with
export(Array, NodePath) var _exclude_paths: Array

# the layers which the end of the arm will collide with
export(int, LAYERS_3D_PHYSICS) var collision_mask := 1 setget set_collision_mask

# Ceiling collision prevention
export var ceiling_check_enabled := true
export var ceiling_margin := 0.3  # keep camera this far below detected ceiling
export var ceiling_check_distance := 3.0  # how far upward to probe for ceilings

# Local offset applied to the rendered child target (typically the Camera).
# This lets higher-level camera behaviors style the framing without fighting
# the arm's own collision-driven transform.
var camera_local_offset := Vector3.ZERO

var kinematic_body: KinematicBody
var _collision_latched_length := -1.0
var _collision_latch_origin := Vector3.ZERO
var _collision_latch_direction := Vector3.BACK
var _collision_release_timer := 0.0
var _collision_miss_timer := 0.0
var _excluded_objects: Array = []
var _zoom_out_blocked := false

func set_collider_shape(shape: Shape) -> void:
	collider_shape = shape
	if is_instance_valid(kinematic_body):
		if kinematic_body.get_child_count() > 0:
			kinematic_body.get_child(0).queue_free()
		var collision_shape := CollisionShape.new()
		collision_shape.shape = shape
		kinematic_body.add_child(collision_shape)

func set_collision_mask(mask: int) -> void:
	collision_mask = mask
	if is_instance_valid(kinematic_body):
		kinematic_body.collision_mask = mask

func _enter_tree():
	kinematic_body = KinematicBody.new()
	kinematic_body.collision_layer = 0
	kinematic_body.collision_mask = collision_mask
	_excluded_objects.clear()

	if not collider_shape:
		# Default to a sphere shape if not set
		var sphere = SphereShape.new()
		sphere.radius = 0.25
		set_collider_shape(sphere)
	else:
		set_collider_shape(collider_shape)

	kinematic_body.name = name + "_KinematicBody"

	for path in _exclude_paths:
		var node = get_node_or_null(path)
		if node and node is CollisionObject:
			kinematic_body.add_collision_exception_with(node)
			_add_excluded_object_internal(node)

	# Try to add exception for the player if it's in the hierarchy
	var parent = get_parent()
	while parent:
		if parent is KinematicBody:
			kinematic_body.add_collision_exception_with(parent)
			_add_excluded_object_internal(parent)
			break
		parent = parent.get_parent()

	# Add as top-level child to self rather than depending on current_scene which may be null in tests
	kinematic_body.set_as_toplevel(true)
	call_deferred("add_child", kinematic_body)
	yield (kinematic_body, "ready")
	set_physics_process(true)

func _exit_tree():
	if is_instance_valid(kinematic_body):
		kinematic_body.queue_free()
	set_physics_process(false)

func _ready():
	set_physics_process(false)
	target_length = spring_length
	_collision_latched_length = -1.0
	_collision_latch_origin = _get_arm_pose_origin()
	_collision_latch_direction = _get_arm_pose_direction()
	_collision_release_timer = 0.0
	_collision_miss_timer = 0.0
	_zoom_out_blocked = false
	_excluded_objects = _excluded_objects.duplicate()

func _add_excluded_object_internal(obj) -> void:
	if obj == null:
		return
	for existing in _excluded_objects:
		if existing == obj:
			return
	_excluded_objects.append(obj)

func add_excluded_object(obj):
	if obj is CollisionObject:
		_add_excluded_object_internal(obj)
		if is_instance_valid(kinematic_body):
			kinematic_body.add_collision_exception_with(obj)

func remove_excluded_object(obj):
	if obj is CollisionObject:
		for i in range(_excluded_objects.size() - 1, -1, -1):
			if _excluded_objects[i] == obj:
				_excluded_objects.remove(i)
		if is_instance_valid(kinematic_body):
			kinematic_body.remove_collision_exception_with(obj)

func clear_excluded_objects():
	# Godot 3 KinematicBody doesn't have a direct clear_collision_exceptions... a bit tricky. We would have to recreate it or keep track.
	pass # Not strictly needed right now since Player doesn't clear exceptions on the fly much.

func get_hit_length() -> float:
	return current_length

func set_camera_local_offset(offset: Vector3) -> void:
	camera_local_offset = offset

func get_camera_local_offset() -> Vector3:
	return camera_local_offset

func has_active_collision() -> bool:
	if _zoom_out_blocked:
		return true
	var desired_length := target_length if target_length > 0.0 else spring_length
	return current_length < desired_length - max(collision_jitter_epsilon, 0.02)

func is_zoom_out_blocked() -> bool:
	return _zoom_out_blocked

func _physics_process(delta):
	# Sync target_length with spring_length just in case someone modifies spring_length directly.
	target_length = spring_length

	# Use separate smoothing speeds: snappier retract, softer extension.
	var moving_outward := target_length > current_length
	var active_weight := extend_weight if moving_outward else retract_weight
	if weight > 0.0:
		active_weight = weight
	var t := clamp(active_weight * delta, 0.0, 1.0)
	var desired_length := max(lerp(current_length, target_length, t), min_length)
	var arm_origin := global_transform.origin
	var arm_motion := global_transform.basis.z * desired_length
	var rendered_length := desired_length
	var final_target := arm_origin + arm_motion
	var used_ceiling_accommodation := _can_accommodate_under_ceiling(arm_origin, desired_length)
	var safe_hit_length := -1.0

	if used_ceiling_accommodation:
		rendered_length = _advance_clear_length(delta)
		final_target = _clamp_target_below_ceiling(arm_origin + global_transform.basis.z * rendered_length, arm_origin)
	else:
		safe_hit_length = _cast_shape_hit_length(arm_origin, arm_motion, desired_length)
		if safe_hit_length >= 0.0:
			_collision_miss_timer = 0.0
			var hit_length := safe_hit_length
			var resolved_hit_length := _resolve_collision_hit_length(hit_length, delta)
			var length_delta := resolved_hit_length - current_length
			if length_delta < -collision_jitter_epsilon:
				# Retract immediately to the safe hit point so the camera never clips into
				# fresh obstacles when the player backs into a wall.
				var shrink_t := clamp(collision_shrink_weight * delta, 0.0, 1.0)
				current_length = lerp(current_length, resolved_hit_length, shrink_t)
				rendered_length = resolved_hit_length
			elif length_delta > collision_jitter_epsilon:
				# When the sweep remains colliding but finds a farther face, expand smoothly
				# instead of snapping the camera outwards frame-to-frame around corners.
				var extend_t := clamp(extend_weight * delta, 0.0, 1.0)
				current_length = lerp(current_length, resolved_hit_length, extend_t)
				rendered_length = current_length
			else:
				current_length = resolved_hit_length
				rendered_length = resolved_hit_length
		else:
			rendered_length = _advance_clear_length(delta)
		final_target = arm_origin + global_transform.basis.z * rendered_length

	_zoom_out_blocked = used_ceiling_accommodation or safe_hit_length >= 0.0 or _collision_latched_length >= 0.0

	if is_instance_valid(kinematic_body):
		kinematic_body.global_transform.origin = final_target

	_update_children(final_target)

func _cast_shape_hit_length(arm_origin: Vector3, arm_motion: Vector3, desired_length: float) -> float:
	var world = get_world()
	if world == null:
		return -1.0
	var space_state = world.direct_space_state
	if space_state == null or collider_shape == null:
		return -1.0

	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(collider_shape)
	params.transform = Transform(global_transform.basis, arm_origin)
	params.collision_mask = collision_mask
	params.exclude = _excluded_objects

	var motion_result = space_state.cast_motion(params, arm_motion)
	if motion_result.empty():
		return -1.0

	var safe_fraction := float(motion_result[0])
	if safe_fraction >= 0.9999:
		return -1.0

	return max((desired_length * safe_fraction) - collision_padding, min_length)

func _advance_clear_length(delta: float) -> float:
	if _collision_latched_length >= 0.0:
		_collision_miss_timer += delta
		var release_delay := collision_miss_grace
		if not _has_collision_latch_pose_changed():
			if collision_stationary_release_delay < 0.0:
				if current_length < _collision_latched_length - collision_jitter_epsilon:
					var stationary_hold_t := clamp(extend_weight * delta, 0.0, 1.0)
					current_length = lerp(current_length, _collision_latched_length, stationary_hold_t)
				else:
					current_length = _collision_latched_length
				return current_length
			release_delay = max(release_delay, collision_stationary_release_delay)
		if _collision_miss_timer < release_delay:
			if current_length < _collision_latched_length - collision_jitter_epsilon:
				var hold_extend_t := clamp(extend_weight * delta, 0.0, 1.0)
				current_length = lerp(current_length, _collision_latched_length, hold_extend_t)
			else:
				current_length = _collision_latched_length
			return current_length

		_collision_latched_length = -1.0
		_collision_release_timer = 0.0
		_collision_miss_timer = 0.0

	var clear_t := clamp(collision_clear_extend_weight * delta, 0.0, 1.0)
	current_length = lerp(current_length, target_length, clear_t)
	current_length = max(current_length, min_length)
	return current_length

func _start_collision_latch(hit_length: float) -> float:
	_collision_latched_length = hit_length
	_collision_latch_origin = _get_arm_pose_origin()
	_collision_latch_direction = _get_arm_pose_direction()
	_collision_release_timer = 0.0
	_collision_miss_timer = 0.0
	return _collision_latched_length

func _resolve_collision_hit_length(hit_length: float, delta: float) -> float:
	if _collision_latched_length < 0.0:
		return _start_collision_latch(hit_length)

	if hit_length < _collision_latched_length - collision_hold_epsilon:
		return _start_collision_latch(hit_length)

	if hit_length > _collision_latched_length + collision_release_hysteresis:
		_collision_release_timer += delta
		if _collision_release_timer >= collision_release_delay:
			return _start_collision_latch(hit_length)
		return _collision_latched_length

	_collision_release_timer = 0.0
	return _collision_latched_length

func _has_collision_latch_pose_changed() -> bool:
	if _collision_latched_length < 0.0:
		return true
	if _get_arm_pose_origin().distance_squared_to(_collision_latch_origin) > LATCH_POSE_TRANSLATION_EPSILON * LATCH_POSE_TRANSLATION_EPSILON:
		return true
	var current_direction := _get_arm_pose_direction()
	if current_direction.length_squared() <= 0.0001 or _collision_latch_direction.length_squared() <= 0.0001:
		return true
	return current_direction.dot(_collision_latch_direction) < 1.0 - LATCH_POSE_DIRECTION_DOT_EPSILON

func _get_arm_pose_origin() -> Vector3:
	return global_transform.origin if is_inside_tree() else transform.origin

func _get_arm_pose_direction() -> Vector3:
	var basis := global_transform.basis if is_inside_tree() else transform.basis
	return basis.z.normalized()

func _update_children(target: Vector3) -> void:
	var child_target := _resolve_child_target(target)
	for child in get_children():
		if child == kinematic_body:
			continue
		if child is Spatial:
			child.global_transform.origin = child_target

func _resolve_child_target(base_target: Vector3) -> Vector3:
	if camera_local_offset.length_squared() <= 0.000001:
		return base_target
	var vertical_world_offset := Vector3.UP * camera_local_offset.y
	var pivot_world_offset := global_transform.basis.z * camera_local_offset.z
	var lateral_world_offset := global_transform.basis.x * camera_local_offset.x
	if vertical_world_offset.length_squared() <= 0.000001 and pivot_world_offset.length_squared() <= 0.000001 and lateral_world_offset.length_squared() <= 0.000001:
		return base_target
	var vertical_target := base_target + vertical_world_offset
	var safe_pivot_offset := _resolve_safe_motion_offset(vertical_target, pivot_world_offset)
	var pivot_target := vertical_target + safe_pivot_offset
	var safe_lateral_offset := _resolve_safe_motion_offset(pivot_target, lateral_world_offset)
	return pivot_target + safe_lateral_offset

func _resolve_safe_motion_offset(origin: Vector3, desired_offset: Vector3) -> Vector3:
	var world = get_world()
	if world == null:
		return desired_offset
	var space_state = world.direct_space_state
	if space_state == null or collider_shape == null:
		return desired_offset

	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(collider_shape)
	params.transform = Transform(global_transform.basis, origin)
	params.collision_mask = collision_mask
	params.exclude = _excluded_objects

	var motion_result = space_state.cast_motion(params, desired_offset)
	if motion_result.empty():
		return desired_offset

	var safe_fraction := float(motion_result[0])
	if safe_fraction >= 0.9999:
		return desired_offset

	var desired_distance := desired_offset.length()
	if desired_distance <= 0.0001:
		return Vector3.ZERO

	var safe_distance := max((desired_distance * safe_fraction) - collision_padding, 0.0)
	if safe_distance <= 0.0001:
		return Vector3.ZERO

	return desired_offset.normalized() * safe_distance

func _can_accommodate_under_ceiling(arm_origin: Vector3, desired_length: float) -> bool:
	if not ceiling_check_enabled:
		return false
	var desired_target := arm_origin + global_transform.basis.z * desired_length
	var adjusted_target := _clamp_target_below_ceiling(desired_target, arm_origin)
	if adjusted_target.distance_squared_to(desired_target) <= 0.0001:
		return false
	return _is_target_position_clear(adjusted_target)

func _is_target_position_clear(target: Vector3) -> bool:
	var world = get_world()
	if world == null:
		return true
	var space_state = world.direct_space_state
	if space_state == null or collider_shape == null:
		return true

	var params := PhysicsShapeQueryParameters.new()
	params.set_shape(collider_shape)
	params.transform = Transform(global_transform.basis, target)
	params.collision_mask = collision_mask
	params.exclude = _excluded_objects

	return space_state.intersect_shape(params, 1).empty()

func _clamp_target_below_ceiling(target: Vector3, arm_origin: Vector3) -> Vector3:
	var world = get_world()
	if world == null:
		return target
	var space_state = world.direct_space_state
	if space_state == null:
		return target

	# Cast a ray upward from the arm origin to find ceilings
	var ray_from := global_transform.origin
	var ray_to := ray_from + Vector3.UP * ceiling_check_distance
	var result = space_state.intersect_ray(ray_from, ray_to, _excluded_objects, collision_mask)
	if result.empty():
		return target

	var ceiling_y: float = result.position.y - ceiling_margin
	if target.y > ceiling_y:
		var offset := target - arm_origin
		var desired_distance := offset.length()
		var planar := Vector3(offset.x, 0.0, offset.z)
		var planar_dir := planar.normalized() if planar.length_squared() > 0.0001 else Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z).normalized()
		var ceiling_offset_y := ceiling_y - arm_origin.y
		var max_vertical := clamp(ceiling_offset_y, -desired_distance, desired_distance)
		var horizontal_sq := max((desired_distance * desired_distance) - (max_vertical * max_vertical), 0.0)
		var horizontal_len := sqrt(horizontal_sq)
		target = arm_origin + planar_dir * horizontal_len + Vector3.UP * max_vertical
	return target
