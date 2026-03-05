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

# Speed used when retracting due to collision correction.
export var collision_shrink_weight := 28.0

# paths to objects which the arm won't collide with
export(Array, NodePath) var _exclude_paths: Array

# the layers which the end of the arm will collide with
export(int, LAYERS_3D_PHYSICS) var collision_mask := 1 setget set_collision_mask

var kinematic_body: KinematicBody

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
	
	# Try to add exception for the player if it's in the hierarchy
	var parent = get_parent()
	while parent:
		if parent is KinematicBody:
			kinematic_body.add_collision_exception_with(parent)
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

func add_excluded_object(obj):
	if is_instance_valid(kinematic_body) and obj is CollisionObject:
		kinematic_body.add_collision_exception_with(obj)

func remove_excluded_object(obj):
	if is_instance_valid(kinematic_body) and obj is CollisionObject:
		kinematic_body.remove_collision_exception_with(obj)

func clear_excluded_objects():
	# Godot 3 KinematicBody doesn't have a direct clear_collision_exceptions... a bit tricky. We would have to recreate it or keep track.
	pass # Not strictly needed right now since Player doesn't clear exceptions on the fly much.

func get_hit_length() -> float:
	return current_length

func _physics_process(delta):
	# Sync target_length with spring_length just in case someone modifies spring_length directly.
	target_length = spring_length

	if not is_instance_valid(kinematic_body):
		return

	# Use separate smoothing speeds: snappier retract, softer extension.
	var moving_outward := target_length > current_length
	var active_weight := extend_weight if moving_outward else retract_weight
	if weight > 0.0:
		active_weight = weight
	var t := clamp(active_weight * delta, 0.0, 1.0)
	var desired_length := max(lerp(current_length, target_length, t), min_length)
	var arm_origin := global_transform.origin
	var arm_motion := global_transform.basis.z * desired_length

	# Always cast from arm origin to avoid skipping geometry when the target jumps between frames.
	kinematic_body.global_transform.origin = arm_origin
	var collision_info := kinematic_body.move_and_collide(arm_motion)
	if is_instance_valid(collision_info):
		var safe_length := collision_info.travel.length() - collision_padding
		var hit_length := max(safe_length, min_length)
		# While colliding, only shrink on meaningful deltas.
		# Prevents jitter caused by frame-to-frame micro changes on contact points.
		if hit_length < current_length - collision_jitter_epsilon:
			var shrink_t := clamp(collision_shrink_weight * delta, 0.0, 1.0)
			current_length = lerp(current_length, hit_length, shrink_t)
	else:
		current_length = desired_length

	_update_children()

func _update_children() -> void:
	var target := kinematic_body.global_transform.origin
	for child in get_children():
		if child == kinematic_body:
			continue
		if child is Spatial:
			child.global_transform.origin = target
