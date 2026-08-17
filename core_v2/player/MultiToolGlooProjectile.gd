extends KinematicBody

# MultiToolGlooProjectile.gd
# Projectile that flies with gravity and sticks to static surfaces.

export(float) var gravity := 9.8
export(float) var speed := 15.0
export(float) var lifetime := 240.0
export(float) var launch_radius := 0.09
export(float) var blob_radius := 0.35
export(float) var cure_time := 0.65
export(float) var collision_radius := 0.32
export(float) var surface_offset := 0.08
export(int) var projectile_collision_mask := 253
export(int) var attached_static_mask := 1
export(float) var wake_impulse := 3.0
export(int) var laser_detection_layer := 512
export(Color) var gloo_color := Color(0.18, 0.88, 0.78, 1.0)
export(Color) var cured_color := Color(0.46, 0.58, 0.52, 1.0)
export(Color) var emission_color := Color(0.08, 0.55, 0.48, 1.0)
export(float) var emission_energy := 0.45
export(float) var laser_heat_time := 2.2
export(float) var laser_cool_rate := 1.4
export(Color) var laser_hot_color := Color(1.0, 0.12, 0.02, 1.0)
export(float) var smoke_fx_scale := 2.0
export(float) var explosion_fx_scale := 1.2
export(float) var fx_lifetime_scale := 1.8
export(float) var fx_camera_offset := 0.35
export(float) var laser_heat_spread_radius := 0.75
export(float) var merge_distance := 0.28
export(float) var merge_radius_gain := 0.45
export(float) var joint_bias := 0.15
export(float) var joint_damping := 0.9
export(float) var joint_impulse_clamp := 1.2

var velocity := Vector3.ZERO
var _is_stuck := false
var _is_destroying := false
var _is_laser_heating := false
var _age := 0.0
var _cure_elapsed := 0.0
var _laser_heat_elapsed := 0.0
var _laser_contact_this_frame := false
var _current_radius := 0.09
var _anchor_collider = null
var _solid_collision_enabled := true
var _laser_area: Area = null
var _laser_shape: CollisionShape = null
var _glue_joints := []

onready var _mesh: MeshInstance = $MeshInstance
onready var _particles: CPUParticles = $ImpactParticles
onready var _collision_shape: CollisionShape = $CollisionShape

const SmokeScene = preload("res://assets/flipbook_particles/assets/smokes/smoke_03/smoke_03.tscn")
const ExplosionScene = preload("res://assets/flipbook_particles/assets/explosions/explosion_03/explosion_03.tscn")

func _ready():
	set_as_toplevel(true)
	collision_mask = projectile_collision_mask
	add_collision_exception_with(self)
	_setup_laser_detection_area()
	_apply_visual_settings()
	add_to_group("gloo_blob")
	add_to_group("replay_sync")

func configure(p_speed: float, p_gravity: float, p_lifetime: float, p_launch_radius: float, p_blob_radius: float, p_cure_time: float, p_collision_radius: float, p_surface_offset: float, p_collision_mask: int, p_attached_static_mask: int, p_wake_impulse: float, p_color: Color, p_cured_color: Color, p_emission_color: Color, p_emission_energy: float, p_laser_heat_time: float, p_laser_cool_rate: float, p_smoke_fx_scale: float, p_explosion_fx_scale: float, p_fx_lifetime_scale: float, p_fx_camera_offset: float, p_laser_heat_spread_radius: float, p_merge_distance: float, p_merge_radius_gain: float, p_joint_bias: float, p_joint_damping: float, p_joint_impulse_clamp: float) -> void:
	speed = p_speed
	gravity = p_gravity
	lifetime = p_lifetime
	launch_radius = p_launch_radius
	blob_radius = p_blob_radius
	cure_time = p_cure_time
	collision_radius = p_collision_radius
	surface_offset = p_surface_offset
	projectile_collision_mask = p_collision_mask
	attached_static_mask = p_attached_static_mask
	wake_impulse = p_wake_impulse
	gloo_color = p_color
	cured_color = p_cured_color
	emission_color = p_emission_color
	emission_energy = p_emission_energy
	laser_heat_time = p_laser_heat_time
	laser_cool_rate = p_laser_cool_rate
	smoke_fx_scale = p_smoke_fx_scale
	explosion_fx_scale = p_explosion_fx_scale
	fx_lifetime_scale = p_fx_lifetime_scale
	fx_camera_offset = p_fx_camera_offset
	laser_heat_spread_radius = p_laser_heat_spread_radius
	merge_distance = p_merge_distance
	merge_radius_gain = p_merge_radius_gain
	joint_bias = p_joint_bias
	joint_damping = p_joint_damping
	joint_impulse_clamp = p_joint_impulse_clamp
	collision_mask = projectile_collision_mask
	_current_radius = launch_radius
	_apply_visual_settings()

func _apply_visual_settings() -> void:
	var cure_t := 1.0
	if _is_stuck and cure_time > 0.0:
		cure_t = clamp(_cure_elapsed / cure_time, 0.0, 1.0)
	if _mesh:
		_mesh.scale = Vector3.ONE * max(0.01, _current_radius / 0.35)
		var mat = _mesh.get_surface_material(0)
		if mat == null or mat.resource_local_to_scene == false:
			mat = SpatialMaterial.new()
			_mesh.set_surface_material(0, mat)
		mat.flags_unshaded = false
		mat.flags_transparent = cure_t < 0.98
		var color := gloo_color.linear_interpolate(cured_color, cure_t)
		if _is_laser_heating:
			var heat_t: float = clamp(_laser_heat_elapsed / max(0.01, laser_heat_time), 0.0, 1.0)
			color = color.linear_interpolate(laser_hot_color, min(1.0, heat_t * 2.0))
		color.a = lerp(0.72, 1.0, cure_t)
		mat.albedo_color = color
		mat.metallic = 0.0 if _is_laser_heating else lerp(0.18, 0.0, cure_t)
		mat.roughness = 0.38 if _is_laser_heating else lerp(0.18, 0.92, cure_t)
		mat.emission_enabled = (emission_energy > 0.0 and cure_t < 0.98) or _is_laser_heating
		mat.emission = laser_hot_color if _is_laser_heating else emission_color
		mat.emission_energy = 3.0 if _is_laser_heating else lerp(emission_energy, 0.0, cure_t)
	if _collision_shape and _collision_shape.shape:
		if _collision_shape.shape.resource_local_to_scene == false:
			_collision_shape.shape = _collision_shape.shape.duplicate()
		if _collision_shape.shape is SphereShape:
			_collision_shape.shape.radius = max(0.01, _current_radius)
	if _laser_shape and _laser_shape.shape:
		if _laser_shape.shape is SphereShape:
			_laser_shape.shape.radius = max(0.01, _current_radius)

func _setup_laser_detection_area() -> void:
	if _laser_area:
		return
	_laser_area = Area.new()
	_laser_area.name = "LaserHitArea"
	_laser_area.collision_layer = laser_detection_layer
	_laser_area.collision_mask = 0
	_laser_area.monitoring = false
	_laser_area.monitorable = true
	add_child(_laser_area)
	_laser_shape = CollisionShape.new()
	var shape := SphereShape.new()
	shape.radius = max(0.01, _current_radius)
	_laser_shape.shape = shape
	_laser_area.add_child(_laser_shape)

func launch(start_transform: Transform):
	global_transform = start_transform
	_current_radius = launch_radius
	_apply_visual_settings()
	velocity = -start_transform.basis.z * speed
	set_physics_process(true)

func _physics_process(delta):
	# Normal physics process only if not managed by a session (replay/recording)
	var sm = get_node_or_null("/root/SessionManager")
	if sm and (sm.is_recording or sm.is_replaying):
		return
	step(delta)

func step(delta: float):
	if _is_destroying:
		return
	if _is_laser_heating:
		if _laser_contact_this_frame:
			_laser_heat_elapsed = min(laser_heat_time, _laser_heat_elapsed + delta)
		else:
			_laser_heat_elapsed = max(0.0, _laser_heat_elapsed - (laser_cool_rate * delta))
			if _laser_heat_elapsed <= 0.0:
				_is_laser_heating = false
		_laser_contact_this_frame = false
		_apply_visual_settings()
		if _laser_heat_elapsed >= laser_heat_time:
			_finish_laser_destroy()
		return
	if _is_stuck:
		_age += delta
		if _cure_elapsed < cure_time:
			_cure_elapsed = min(cure_time, _cure_elapsed + delta)
			var t := 1.0 if cure_time <= 0.0 else _cure_elapsed / cure_time
			t = t * t * (3.0 - 2.0 * t)
			_current_radius = lerp(launch_radius, blob_radius, t)
			_apply_visual_settings()
			if _cure_elapsed >= cure_time:
				_try_merge_nearby_gloo()
				_resolve_cured_collision_behavior()
		if _age > lifetime:
			fade_out()
		return

	velocity.y -= gravity * delta
	
	var motion := velocity * delta
	var space_state := get_world().direct_space_state
	var ray_end := global_transform.origin + motion
	if motion.length_squared() > 0.0001:
		ray_end += motion.normalized() * max(_current_radius, collision_radius)
	var hit := space_state.intersect_ray(global_transform.origin, ray_end, [self], collision_mask)
	if hit and _should_stick_to(hit.get("collider", null)):
		_wake_collider(hit["collider"], hit["normal"])
		_stick_at(hit["collider"], hit["position"], hit["normal"])
		return

	var collision = move_and_collide(motion)
	if collision:
		_handle_collision(collision)

func get_snapshot() -> Dictionary:
	return {
		"p": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"v": [velocity.x, velocity.y, velocity.z],
		"s": _is_stuck,
		"a": _age
	}

func restore_snapshot(data: Dictionary):
	if data.has("p"):
		var p = data["p"]
		global_transform.origin = Vector3(p[0], p[1], p[2])
	if data.has("v"):
		var v = data["v"]
		velocity = Vector3(v[0], v[1], v[2])
	if data.has("s"):
		_is_stuck = data["s"]
	if data.has("a"):
		_age = data["a"]

func _handle_collision(collision: KinematicCollision):
	var collider = collision.collider
	if not _should_stick_to(collider):
		return
	_wake_collider(collider, collision.normal)
	_stick_at(collider, collision.position, collision.normal)

func _should_stick_to(collider) -> bool:
	if _is_player_collider(collider):
		return false
	return collider is StaticBody or collider is CSGShape or collider is RigidBody or collider is KinematicBody

func _is_player_collider(collider) -> bool:
	var node = collider
	for _i in range(8):
		if node == null:
			return false
		if node is Node and node.is_in_group("player"):
			return true
		node = node.get_parent() if node is Node else null
	return false

func _wake_collider(collider, normal: Vector3) -> void:
	if collider == null or not is_instance_valid(collider):
		return
	if collider.has_method("wake_up"):
		collider.wake_up()
	if collider is RigidBody:
		collider.sleeping = false

func _stick_at(collider, position: Vector3, normal: Vector3):
	if not (collider is Spatial):
		laser_hit()
		return

	_anchor_collider = collider
	_is_stuck = true
	velocity = Vector3.ZERO
	_cure_elapsed = 0.0
	_current_radius = launch_radius
	
	# Small adjustment to visual position to sit ON the surface
	global_transform.origin = position + normal * surface_offset
	_apply_visual_settings()
	
	# Visual feedback
	if _particles:
		_particles.emitting = true
	
	var parent = collider
	var old_transform = global_transform
	get_parent().remove_child(self)
	parent.add_child(self)
	set_as_toplevel(false)
	global_transform = old_transform
	add_collision_exception_with(collider)
	if collider.has_method("add_collision_exception_with"):
		collider.add_collision_exception_with(self)
	_add_gloo_collision_exceptions()
	_try_patch_leak(collider)

	if collider is StaticBody or collider is CSGShape:
		_set_solid_collision(true, _get_static_gloo_collision_mask())
	else:
		_set_solid_collision(false)


func _try_patch_leak(node: Node) -> void:
	var curr = node
	var depth = 0
	while curr != null and depth < 6:
		if curr.has_method("patch_with_gloo"):
			curr.call("patch_with_gloo")
			return
		if curr.is_in_group("gloo_patchable"):
			if curr.has_method("patch_with_gloo"):
				curr.call("patch_with_gloo")
				return
			for child in curr.get_children():
				if child.has_method("patch_with_gloo"):
					child.call("patch_with_gloo")
					return
		curr = curr.get_parent()
		depth += 1

func _add_gloo_collision_exceptions() -> void:
	for blob in get_tree().get_nodes_in_group("gloo_blob"):
		if blob == self or not is_instance_valid(blob):
			continue
		if blob is PhysicsBody:
			add_collision_exception_with(blob)
			blob.add_collision_exception_with(self)

func _resolve_cured_collision_behavior() -> void:
	if not is_instance_valid(_anchor_collider):
		_set_solid_collision(false)
		return
	if _anchor_collider is StaticBody or _anchor_collider is CSGShape:
		_set_solid_collision(true, _get_static_gloo_collision_mask())
		return
	var bridged_bodies := _get_bridged_bodies(_anchor_collider)
	if bridged_bodies.size() > 0:
		var anchors_to_static := _contains_static_body(bridged_bodies)
		if anchors_to_static:
			_wake_for_glue(_anchor_collider)
		for body in bridged_bodies:
			if anchors_to_static:
				_wake_for_glue(body)
			else:
				_wake_collider(body, Vector3.ZERO)
			_create_glue_joint(_anchor_collider, body)
		_set_solid_collision(false)
	else:
		_set_solid_collision(false)

func _try_merge_nearby_gloo() -> void:
	for blob in get_tree().get_nodes_in_group("gloo_blob"):
		if blob == self or not is_instance_valid(blob) or not (blob is Spatial):
			continue
		if blob.has_method("is_destroying") and blob.is_destroying():
			continue
		var dist: float = global_transform.origin.distance_to(blob.global_transform.origin)
		if dist > merge_distance:
			continue
		if _anchor_collider != null and blob.get("_anchor_collider") != _anchor_collider:
			continue
		_absorb_gloo(blob)

func _absorb_gloo(blob) -> void:
	if not is_instance_valid(blob):
		return
	var other_radius := collision_radius
	if blob.has_method("get_laser_hit_radius"):
		other_radius = float(blob.get_laser_hit_radius())
	blob.call("_release_glue_joints")
	blob.queue_free()
	blob_radius = min(blob_radius + other_radius * merge_radius_gain, collision_radius * 3.0)
	collision_radius = max(collision_radius, blob_radius)
	_current_radius = max(_current_radius, blob_radius)
	_apply_visual_settings()

func _set_solid_collision(enabled: bool, mask: int = 0) -> void:
	_solid_collision_enabled = enabled
	collision_layer = 64 if enabled else 0
	collision_mask = mask if enabled else 0
	if _collision_shape:
		_collision_shape.disabled = not enabled

func _get_static_gloo_collision_mask() -> int:
	return projectile_collision_mask | 2

func _get_bridged_bodies(anchor) -> Array:
	var bridged := []
	var space_state := get_world().direct_space_state
	var shape := SphereShape.new()
	shape.radius = max(collision_radius, _current_radius) * 1.05
	var query := PhysicsShapeQueryParameters.new()
	query.set_shape(shape)
	query.transform = global_transform
	query.collision_mask = projectile_collision_mask
	query.exclude = [self, anchor]
	var hits := space_state.intersect_shape(query, 12)
	for hit in hits:
		var collider = hit.get("collider", null)
		if collider == null or not is_instance_valid(collider):
			continue
		if collider == anchor or collider == self:
			continue
		if _is_player_collider(collider):
			continue
		if collider is StaticBody or collider is CSGShape or collider is RigidBody or collider is KinematicBody:
			if not bridged.has(collider):
				bridged.append(collider)
	return bridged

func _contains_static_body(bodies: Array) -> bool:
	for body in bodies:
		if body is StaticBody or body is CSGShape:
			return true
	return false

func _wake_for_glue(anchor) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	if anchor.has_method("wake_up"):
		anchor.wake_up()
	if anchor is RigidBody:
		anchor.sleeping = false

func _create_glue_joint(a, b) -> void:
	if a == null or b == null:
		return
	if not (is_instance_valid(a) and is_instance_valid(b)):
		return
	if a == b:
		return
	if not (a is PhysicsBody and b is PhysicsBody):
		return
	if _has_existing_joint_between(a, b):
		return

	var joint := PinJoint.new()
	joint.name = "GlooPinJoint"
	joint.add_to_group("gloo_joint")
	get_tree().root.add_child(joint)
	joint.global_transform.origin = global_transform.origin
	joint.set("nodes/node_a", joint.get_path_to(a))
	joint.set("nodes/node_b", joint.get_path_to(b))
	joint.set("collision/exclude_nodes", false)
	joint.set("params/bias", joint_bias)
	joint.set("params/damping", joint_damping)
	joint.set("params/impulse_clamp", joint_impulse_clamp)
	joint.set_meta("gloo_node_a", str(a.get_path()))
	joint.set_meta("gloo_node_b", str(b.get_path()))
	_glue_joints.append(joint)

func _has_existing_joint_between(a: Node, b: Node) -> bool:
	var path_a := str(a.get_path())
	var path_b := str(b.get_path())
	for node in get_tree().get_nodes_in_group("gloo_joint"):
		if not is_instance_valid(node):
			continue
		var node_a := String(node.get_meta("gloo_node_a", ""))
		var node_b := String(node.get_meta("gloo_node_b", ""))
		if (node_a == path_a and node_b == path_b) or (node_a == path_b and node_b == path_a):
			return true
	return false

func is_destroying() -> bool:
	return _is_destroying

func laser_hit(propagate: bool = true) -> void:
	if _is_destroying:
		return
	_laser_contact_this_frame = true
	if not _is_laser_heating:
		_is_laser_heating = true
		_set_solid_collision(false)
		_apply_visual_settings()
		_spawn_flipbook_fx(SmokeScene, smoke_fx_scale * 0.85, laser_heat_time * fx_lifetime_scale)
	if propagate:
		_spread_laser_heat()

func _spread_laser_heat() -> void:
	for blob in get_tree().get_nodes_in_group("gloo_blob"):
		if blob == self or not is_instance_valid(blob) or not (blob is Spatial):
			continue
		if global_transform.origin.distance_to(blob.global_transform.origin) > laser_heat_spread_radius:
			continue
		if blob.has_method("laser_hit"):
			blob.laser_hit(false)

func get_laser_hit_radius() -> float:
	return max(_current_radius, collision_radius)

func _finish_laser_destroy() -> void:
	if _is_destroying:
		return
	_is_destroying = true
	_release_glue_joints()
	_spawn_flipbook_fx(SmokeScene, smoke_fx_scale * 1.25, 1.15 * fx_lifetime_scale)
	_spawn_flipbook_fx(ExplosionScene, explosion_fx_scale * 1.35, 0.75 * fx_lifetime_scale)
	queue_free()

func _release_glue_joints() -> void:
	for joint in _glue_joints:
		if is_instance_valid(joint):
			joint.queue_free()
	_glue_joints.clear()

func _spawn_flipbook_fx(scene: PackedScene, scale_value: float, lifetime_sec: float) -> void:
	if scene == null or not get_tree():
		return
	var fx = scene.instance()
	get_tree().root.add_child(fx)
	if fx is Spatial:
		fx.global_transform.origin = _get_fx_origin()
		fx.scale = Vector3.ONE * scale_value
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = lifetime_sec
	fx.add_child(timer)
	timer.connect("timeout", fx, "queue_free")
	timer.start()

func _get_fx_origin() -> Vector3:
	var origin := global_transform.origin
	var camera := get_viewport().get_camera()
	if camera and is_instance_valid(camera):
		var to_camera: Vector3 = camera.global_transform.origin - origin
		if to_camera.length_squared() > 0.0001:
			origin += to_camera.normalized() * fx_camera_offset
	return origin

func fade_out():
	# Simple shrink and free
	var tween = create_tween()
	if tween:
		tween.tween_property(self, "scale", Vector3.ZERO, 0.5)
		tween.tween_callback(self, "queue_free")
	else:
		# Fallback if tweening not available/working as expected in GLES2/3.6
		queue_free()

func create_tween() -> SceneTreeTween:
	if get_tree():
		return get_tree().create_tween()
	return null
