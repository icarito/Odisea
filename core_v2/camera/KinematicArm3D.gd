# A GTA style arm for cameras
# Will only shorten the arm if the end is intersecting an obstacle
# So the arm can intersect small obstacles without shortening
# NOTE, the end of the arm extends out from the - z axis
class_name KinematicArm3D
extends Spatial

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
export var collision_miss_grace := 0.35

# When contact is finally released, expand more gently than the regular orbit zoom.
export var collision_clear_extend_weight := 2.5

# Speed used when retracting due to collision correction.
export var collision_shrink_weight := 28.0

# paths to objects which the arm won't collide with
export(Array, NodePath) var _exclude_paths: Array

# the layers which the end of the arm will collide with
export(int, LAYERS_3D_PHYSICS) var collision_mask := 1 setget set_collision_mask

# Ceiling collision prevention
export var ceiling_check_enabled := true
export var ceiling_margin := 0.3  # keep camera this far below detected ceiling
export var ceiling_check_distance := 3.0  # how far upward to probe for ceilings

var kinematic_body: KinematicBody
var _collision_latched_length := -1.0
var _collision_release_timer := 0.0
var _collision_miss_timer := 0.0
var _excluded_objects: Array = []

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
	_collision_release_timer = 0.0
	_collision_miss_timer = 0.0
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

	var safe_hit_length := _cast_shape_hit_length(arm_origin, arm_motion, desired_length)
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
		if _collision_latched_length >= 0.0:
			_collision_miss_timer += delta
			if _collision_miss_timer < collision_miss_grace:
				if current_length < _collision_latched_length - collision_jitter_epsilon:
					var hold_extend_t := clamp(extend_weight * delta, 0.0, 1.0)
					current_length = lerp(current_length, _collision_latched_length, hold_extend_t)
				else:
					current_length = _collision_latched_length
				rendered_length = current_length
			else:
				_collision_latched_length = -1.0
				_collision_release_timer = 0.0
				_collision_miss_timer = 0.0
				var clear_t := clamp(collision_clear_extend_weight * delta, 0.0, 1.0)
				current_length = lerp(current_length, target_length, clear_t)
				current_length = max(current_length, min_length)
				rendered_length = current_length
		else:
			var clear_t := clamp(collision_clear_extend_weight * delta, 0.0, 1.0)
			current_length = lerp(current_length, target_length, clear_t)
			current_length = max(current_length, min_length)
			rendered_length = current_length

	if is_instance_valid(kinematic_body):
		kinematic_body.global_transform.origin = arm_origin + global_transform.basis.z * rendered_length

	_update_children(arm_origin, rendered_length)

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

func _resolve_collision_hit_length(hit_length: float, delta: float) -> float:
	if _collision_latched_length < 0.0:
		_collision_latched_length = hit_length
		_collision_release_timer = 0.0
		return _collision_latched_length

	if hit_length < _collision_latched_length - collision_hold_epsilon:
		_collision_latched_length = hit_length
		_collision_release_timer = 0.0
		return _collision_latched_length

	_collision_release_timer = 0.0
	return _collision_latched_length

func _update_children(arm_origin: Vector3, rendered_length: float) -> void:
	var target := arm_origin + global_transform.basis.z * rendered_length

	# Ceiling clamp: prevent camera from poking through floors above
	if ceiling_check_enabled:
		target = _clamp_target_below_ceiling(target)

	for child in get_children():
		if child == kinematic_body:
			continue
		if child is Spatial:
			child.global_transform.origin = target

func _clamp_target_below_ceiling(target: Vector3) -> Vector3:
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
		target.y = ceiling_y
	return target
