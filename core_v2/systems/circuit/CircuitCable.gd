extends PropBaseV2
class_name CircuitCable

const TubeBuilder = preload("res://core_v2/systems/pipe/TubeBuilder.gd")

# CircuitCable.gd
# Procedurally generated cable that connects circuit nodes.
# Supports both CSG and direct Mesh generation.

signal connection_broken

export(Curve3D) var path_curve: Curve3D
export(bool) var use_csg := false
export(Material) var cable_material: Material
export(float) var health := 10.0
export(float) var cable_radius := 0.05
export(int) var cable_sides := 8

var _hurtbox: Area

func _ready():
	# FIRST call parent class _ready() to ensure set_active and other methods are available
	# This sets is_active, anim_progress, target_progress, and calls _update_visuals()
	._ready()

	# If no Curve3D is assigned (common in props/tests), create a tiny default
	# curve so that build() can produce visible geometry for validation.
	if not path_curve:
		var default_curve = Curve3D.new()
		# Make the default cable along X axis (horizontal) for typical circuit layout
		# In this project +Z is backward (camera direction), so X is horizontal left-right
		default_curve.add_point(Vector3(0, 0, 0))
		default_curve.add_point(Vector3(3, 0, 0))
		path_curve = default_curve

	if path_curve:
		# Build synchronously so _update_visuals() can access the mesh
		build()

func build():
	# Clear previous children
	for child in get_children():
		child.queue_free()

	if not path_curve or path_curve.get_point_count() < 2:
		return

	if use_csg:
		_build_csg()
	else:
		_build_mesh()

	_setup_hurtbox()

func _build_csg():
	var path_node = Path.new()
	path_node.curve = path_curve
	path_node.name = "Path"
	add_child(path_node)
	var csg = CSGPolygon.new()
	csg.mode = CSGPolygon.MODE_PATH
	csg.path_node = path_node.get_path()
	csg.polygon = _generate_circle_polygon(cable_radius, cable_sides)
	csg.material = cable_material
	csg.use_collision = true
	csg.name = "CableVis"
	add_child(csg)


func _build_mesh():
	var mesh_inst = MeshInstance.new()
	mesh_inst.mesh = _generate_tube_mesh(path_curve, cable_radius, cable_sides)
	
	# Create a unique material per instance (duplicate the assigned material or create new)
	var unique_material = null
	if cable_material:
		unique_material = cable_material.duplicate()
	else:
		unique_material = SpatialMaterial.new()
	mesh_inst.material_override = unique_material
	
	# If no material was assigned, create a visible fallback
	if not cable_material:
		unique_material.emission_enabled = true
		unique_material.emission = Color(1, 1, 0)
		unique_material.albedo_color = Color(1, 1, 0.2)
	
	mesh_inst.name = "CableVis"
	add_child(mesh_inst)
	# Con una curva muy corta (p. ej. la de 2 puntos por defecto, o la placeholder que build()
	# arma en _ready() antes de que init_from_curve() aplique la real) generate_tube_mesh()
	# puede devolver una malla sin superficies validas. create_trimesh_collision() no tolera
	# eso: falla con "Condition '!static_body' is true" porque nunca llega a crear el cuerpo.
	if mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 0:
		mesh_inst.create_trimesh_collision()


func _setup_hurtbox():
	# Create an Area named Hurtbox and populate it with capsule CollisionShapes
	if _hurtbox and is_instance_valid(_hurtbox):
		_hurtbox.queue_free()

	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 1
	_hurtbox.collision_mask = 0
	add_child(_hurtbox)

	if not path_curve:
		return

	var points = path_curve.get_baked_points()
	if points.size() < 2:
		return

	var prev = points[0]
	var interval = 0.5 # Generate collision every 0.5 units to reduce count
	var dist_acc = 0.0

	for i in range(1, points.size()):
		var curr = points[i]
		var seg_len = prev.distance_to(curr)
		dist_acc += seg_len

		if dist_acc >= interval or i == points.size() - 1:
			var col = CollisionShape.new()
			var capsule = CapsuleShape.new()
			capsule.radius = cable_radius * 2.0
			capsule.height = dist_acc
			col.shape = capsule

			var center = (prev + curr) / 2.0

			_hurtbox.add_child(col)

			var local_center = _hurtbox.to_local(center)
			col.transform.origin = local_center

			var dir = (curr - prev).normalized()
			var right = dir.cross(Vector3.UP)
			if right.length_squared() < 0.0001:
				right = dir.cross(Vector3.RIGHT)
			right = right.normalized()
			var up_vec = right.cross(dir).normalized()
			var basis = Basis(right, up_vec, -dir)
			col.transform.basis = basis

			prev = curr
			dist_acc = 0.0


func _generate_circle_polygon(radius: float, sides: int) -> PoolVector2Array:
	return TubeBuilder.generate_circle_polygon(radius, sides)

func _generate_tube_mesh(curve: Curve3D, radius: float, sides: int) -> ArrayMesh:
	return TubeBuilder.generate_tube_mesh(curve, radius, sides)

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0:
		emit_signal("connection_broken")
		queue_free()

# Compatibility for other damage systems
func damage(amount: float) -> void:
	take_damage(amount)

func hit(amount: float) -> void:
	take_damage(amount)

func is_broken() -> bool:
	return health <= 0

func init_from_curve(curve: Curve3D) -> void:
	# Initialize the cable from a Curve3D and build geometry
	path_curve = curve
	build()

# --- Energy Reactivity ---

func _update_visuals() -> void:
	"""Override from PropBaseV2 to react to energy (is_active state)."""
	var t = target_progress if anim_progress < 0.01 else anim_progress
	
	# Update legacy state for test compatibility
	if t < 0.3:
		circuit_state = "idle"
	elif t < 0.7:
		circuit_state = "mid"
	else:
		circuit_state = "active"
	
	# Get the cable visual mesh
	var mesh_inst = get_node_or_null("CableVis")
	if not mesh_inst:
		return
	
	# ALWAYS create a fresh material for energy visualization
	var mat = SpatialMaterial.new()
	mesh_inst.material_override = mat
	
	# Energy states: inactive (dim gray), active (glowing cyan/electric blue)
	var inactive_color = Color(0.1, 0.1, 0.1)  # Very dark gray (almost black)
	var active_color = Color(0.0, 1.0, 0.8)     # Bright electric cyan
	
	# Add dramatic pulse effect based on time when active
	var pulse = 1.0
	if t > 0.5:
		pulse = 1.0 + 0.3 * sin(OS.get_ticks_msec() * 0.01)
	
	# Interpolate based on animation progress
	var current_color = inactive_color.linear_interpolate(active_color, t)
	
	# Set albedo
	mat.albedo_color = current_color
	
	# Enable emission for strong glow effect when active
	mat.emission_enabled = true
	mat.emission = current_color
	mat.emission_energy = t * 5.0 * pulse  # Very strong glow!
	
	# Make it really obvious when off - no glow at all
	if t < 0.1:
		mat.emission_energy = 0.0
		mat.albedo_color = Color(0.05, 0.05, 0.05)  # Very dark

# --- Interaction (for manual testing) ---

func set_active(value: bool, immediate: bool = false) -> void:
	"""Override set_active to update state property when called by Lever."""
	.set_active(value, immediate)
	_update_visuals()

func interact(_from = null) -> void:
	"""Toggle energy state. Called by player interaction or pipeline."""
	.set_active(not is_active)

# Legacy state handling for backward compatibility with tests
var circuit_state: String = "idle" # idle, mid, active

# Alias for test compatibility
func get_state() -> String:
	return circuit_state

func set_state(value: String) -> void:
	circuit_state = value

var state: String = "idle" setget set_state, get_state

# Legacy method - now calls set_active
func set_cable_visuals(emission: float, color: Color):
	if not cable_material:
		cable_material = SpatialMaterial.new()
		var mesh_inst = get_node_or_null("CableVis")
		if mesh_inst:
			mesh_inst.material_override = cable_material
	cable_material.emission_enabled = true
	cable_material.emission = color * emission
	cable_material.albedo_color = color
