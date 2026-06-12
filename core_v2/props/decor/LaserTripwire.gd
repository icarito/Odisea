extends PropBaseV2
class_name LaserTripwire

# LaserTripwire.gd
# Deterministic tripwire that activates when beam is broken.

export(float) var beam_length := 4.0
export(Color) var beam_color := Color.red

var _beam_mesh: MeshInstance
var _raycast: RayCast

func _ready():
	_beam_mesh = get_node_or_null("BeamMesh")
	_raycast = get_node_or_null("RayCast")

	# Initial visual update
	_update_visuals()

func _physics_process(delta):
	# InteractableBaseV2 has _physics_process which calls step(delta).
	# PropBaseV2 doesn't override _physics_process, so it's fine.
	step(delta)

	var colliding = false
	if _raycast:
		_raycast.force_raycast_update()
		if _raycast.is_colliding():
			var collider = _raycast.get_collider()
			# Ignore static geometry or self
			if collider != self and not (collider is StaticBody or collider is CSGShape):
				colliding = true

	# Logic:
	# If colliding -> active (beam broken)
	# If not colliding -> inactive (beam clear)
	# Unless latched? Tripwires usually reset.

	if colliding:
		if not is_active:
			set_active(true)
			_update_visuals()
	else:
		if is_active:
			set_active(false)
			_update_visuals()

func _update_visuals():
	if not _beam_mesh: return

	# Ensure unique material for this instance
	var mat = _beam_mesh.get_surface_material(0)
	if not mat:
		# If no material assigned, try getting from mesh
		if _beam_mesh.mesh and _beam_mesh.mesh.surface_get_material(0):
			mat = _beam_mesh.mesh.surface_get_material(0).duplicate()
		else:
			mat = SpatialMaterial.new()
		_beam_mesh.set_surface_material(0, mat)

	# Set base properties
	mat.flags_transparent = true
	mat.albedo_color = beam_color
	mat.albedo_color.a = 0.5
	mat.emission_enabled = true
	mat.emission = beam_color

	if is_active:
		# Beam Broken: Flash White/Bright
		mat.emission_energy = 8.0
		mat.albedo_color = Color.white
		mat.albedo_color.a = 0.8
	else:
		# Beam Intact: Normal Glow
		mat.emission_energy = 2.0
