extends Spatial

# MultiToolLaser.gd
# Visuals and raycasting for the laser mode.

export(Color) var laser_color := Color(1.0, 0.3, 0.1) # Red-orange
export(float) var max_range := 50.0

onready var _raycast: RayCast = $RayCast
onready var _beam_mesh: MeshInstance = $BeamMesh
onready var _impact_particles: CPUParticles = $ImpactParticles

func _ready():
	set_firing(false)
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

func _update_beam_material():
	var mat = SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.albedo_color = laser_color
	mat.albedo_color.a = 0.6
	mat.emission_enabled = true
	mat.emission = laser_color
	mat.emission_energy = 2.0
	_beam_mesh.set_surface_material(0, mat)
