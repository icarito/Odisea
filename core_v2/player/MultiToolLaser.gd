extends Spatial

# MultiToolLaser.gd
# Visuals and raycasting for the laser mode.

export(Color) var laser_color := Color(1.0, 0.3, 0.1) # Red-orange
export(float) var max_range := 50.0
export(int) var collision_mask := 765
export(float) var beam_alpha := 0.6
export(float) var emission_energy := 2.0

onready var _raycast: RayCast = $RayCast
onready var _beam_mesh: MeshInstance = $BeamMesh
onready var _impact_particles: CPUParticles = $ImpactParticles

func _ready():
	_raycast.collision_mask = collision_mask
	_raycast.cast_to = Vector3(0, 0, -max_range)
	set_firing(false)
	_update_beam_material()

func configure(p_max_range: float, p_collision_mask: int, p_color: Color, p_alpha: float, p_emission_energy: float) -> void:
	max_range = p_max_range
	collision_mask = p_collision_mask
	laser_color = p_color
	beam_alpha = p_alpha
	emission_energy = p_emission_energy
	if _raycast:
		_raycast.collision_mask = collision_mask
		_raycast.cast_to = Vector3(0, 0, -max_range)
	if _beam_mesh:
		_update_beam_material()

func set_firing(firing: bool):
	visible = firing
	_raycast.enabled = firing
	if firing:
		set_physics_process(true)
		_impact_particles.emitting = false # Will be enabled on collision
	else:
		set_physics_process(false)
		_impact_particles.emitting = false

func _physics_process(_delta):
	if not _raycast.enabled:
		return

	_raycast.force_raycast_update()
	
	var beam_length = max_range
	if _raycast.is_colliding():
		var collision_point = _raycast.get_collision_point()
		beam_length = global_transform.origin.distance_to(collision_point)
		var collider = _raycast.get_collider()
		var target = _find_laser_target(collider)
		if target == null:
			target = _find_gloo_target_on_beam(beam_length)
		if target and target.has_method("laser_hit"):
			target.laser_hit()
		
		_impact_particles.global_transform.origin = collision_point
		var normal = _raycast.get_collision_normal()
		if normal.cross(Vector3.UP).length() < 0.001:
			_impact_particles.look_at(collision_point + normal, Vector3.RIGHT)
		else:
			_impact_particles.look_at(collision_point + normal, Vector3.UP)
		
		if not _impact_particles.emitting:
			_impact_particles.emitting = true
	else:
		if _impact_particles.emitting:
			_impact_particles.emitting = false

	# Update beam visuals
	# BeamMesh is a unit cylinder (height 2, radius 1) or unit cube.
	# We'll use a CubeMesh for simplicity, centered at origin.
	# It points towards -Z.
	_beam_mesh.scale.z = beam_length
	_beam_mesh.translation.z = -beam_length / 2.0

func _find_laser_target(collider):
	var target = collider
	for _i in range(4):
		if target == null:
			return null
		if target.has_method("laser_hit"):
			return target
		target = target.get_parent()
	return null

func _find_gloo_target_on_beam(beam_length: float):
	var from: Vector3 = global_transform.origin
	var dir: Vector3 = -global_transform.basis.z.normalized()
	var best = null
	var best_t := beam_length
	for blob in get_tree().get_nodes_in_group("gloo_blob"):
		if not is_instance_valid(blob) or not (blob is Spatial):
			continue
		var to_blob: Vector3 = blob.global_transform.origin - from
		var t: float = clamp(to_blob.dot(dir), 0.0, beam_length)
		var closest: Vector3 = from + dir * t
		var radius := 0.4
		if blob.has_method("get_laser_hit_radius"):
			radius = float(blob.get_laser_hit_radius())
		if closest.distance_to(blob.global_transform.origin) <= radius and t <= best_t:
			best = blob
			best_t = t
	return best

func _update_beam_material():
	var mat = SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.albedo_color = laser_color
	mat.albedo_color.a = beam_alpha
	mat.emission_enabled = true
	mat.emission = laser_color
	mat.emission_energy = emission_energy
	_beam_mesh.set_surface_material(0, mat)
