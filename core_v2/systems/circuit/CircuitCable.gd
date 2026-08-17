extends PropBaseV2
class_name CircuitCable

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
	._ready()

	# If no Curve3D is assigned (common in props/tests), create a tiny default
	# curve so that build() can produce visible geometry for validation.
	if not path_curve:
		var default_curve = Curve3D.new()
		default_curve.add_point(Vector3(0, 0, 0))
		default_curve.add_point(Vector3(3, 0, 0))
		path_curve = default_curve

	if path_curve:
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

	var unique_material = null
	if cable_material:
		unique_material = cable_material.duplicate()
	else:
		unique_material = SpatialMaterial.new()
	mesh_inst.material_override = unique_material

	if not cable_material:
		unique_material.emission_enabled = true
		unique_material.emission = Color(1, 1, 0)
		unique_material.albedo_color = Color(1, 1, 0.2)

	mesh_inst.name = "CableVis"
	add_child(mesh_inst)
	mesh_inst.create_trimesh_collision()


	# The collision sibling created by create_trimesh_collision is a StaticBody.
	# We might want to move its shape to our Hurtbox or keep it as physical barrier.
	# For destructibility, we need an Area.

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

	points = path_curve.get_baked_points()
	if points.size() < 2:
		return

	# Create segments (deprecated simple loop removed). We use a more robust
	# accumulation loop below that batches capsule shapes and parents them to
	# the Hurtbox before calling Spatial methods that require being inside
	# the scene tree (e.g. look_at()).

	# For this implementation, I will assume the caller (Projectile/Explosion) checks for `take_damage` on the collider.
	# If I use `create_trimesh_collision`, I get a StaticBody. I can attach a script to it.

	# However, to be robust, I will manually create an Area with simplified collision (Capsules) as planned above.
	# Capsule in Godot 3 is Height along Z? No, it's usually Y.
	# If I look_at(p2), the local -Z points to p2.
	# I need to align the capsule (Y-axis) with the Z-axis.
	# Rotate X -90 degrees.

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

			# Parent to the hurtbox first so we can compute local transforms
			# relative to it without calling Spatial methods that may depend
			# on being in the tree. Then set a stable basis oriented along
			# the segment direction.
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
	var arr = PoolVector2Array()
	for i in range(sides):
		var angle = (i / float(sides)) * TAU
		arr.append(Vector2(cos(angle), sin(angle)) * radius)
	return arr

func _generate_tube_mesh(curve: Curve3D, radius: float, sides: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var baked_points = curve.get_baked_points()
	var baked_tilts = curve.get_baked_tilts()
	# Up vector logic needed. Curve3D uses tilts.
	# Simple Frenet frame or similar.

	# For simplicity, I'll rely on a basic up vector that rotates if direction changes up.
	# Or just use `curve.interpolate_baked_up_vectors` if available in 3.5? No.

	var up = Vector3.UP

	for i in range(baked_points.size()):
		var p = baked_points[i]
		var tangent = Vector3.FORWARD
		if i < baked_points.size() - 1:
			tangent = (baked_points[i+1] - p).normalized()
		elif i > 0:
			tangent = (p - baked_points[i-1]).normalized()

		# Make a basis
		var right = tangent.cross(up).normalized()
		if right.length_squared() < 0.001:
			right = tangent.cross(Vector3.RIGHT).normalized()
		up = right.cross(tangent).normalized()

		var basis = Basis(right, up, -tangent) # -Z is forward in basis?
		# Actually we just need a rotation to place the ring.

		# Generate ring
		for j in range(sides + 1): # +1 to close loop
			var angle = (j / float(sides)) * TAU
			var local_pos = Vector2(cos(angle), sin(angle)) * radius
			var pos_3d = p + (right * local_pos.x) + (up * local_pos.y)

			var uv_x = j / float(sides)
			var uv_y = i / float(baked_points.size())
			st.add_uv(Vector2(uv_x, uv_y))
			st.add_vertex(pos_3d)

	# Indices
	var ring_v_count = sides + 1
	for i in range(baked_points.size() - 1):
		for j in range(sides):
			var curr = i * ring_v_count + j
			var next = curr + 1
			var upper_curr = (i + 1) * ring_v_count + j
			var upper_next = upper_curr + 1

			# Tri 1
			st.add_index(curr)
			st.add_index(upper_curr)
			st.add_index(next)

			# Tri 2
			st.add_index(next)
			st.add_index(upper_curr)
			st.add_index(upper_next)

	st.generate_normals()
	var mesh = st.commit()
	return mesh

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
	# Use target_progress if anim_progress hasn't started (animation pending)
	# This ensures immediate visual feedback when set_active is called
	# Fix: Use target_progress whenever anim_progress is at initial value (0), regardless of direction
	var t = target_progress if anim_progress < 0.01 else anim_progress
	
	# Update legacy state for test compatibility
	# Map anim_progress to state: idle (0-0.3), mid (0.3-0.7), active (0.7-1.0)
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
	# This ensures we don't modify the assigned cable_material (CableVisible.tres)
	var mat = SpatialMaterial.new()
	mesh_inst.material_override = mat
	
	# Energy states: inactive (dim gray), active (glowing cyan/electric blue)
	var inactive_color = Color(0.1, 0.1, 0.1)  # Very dark gray (almost black)
	var active_color = Color(0.0, 1.0, 0.8)     # Bright electric cyan
	
	# Add dramatic pulse effect based on time when active
	var pulse = 1.0
	if t > 0.5:
		# Pulse effect when more than 50% active
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
	# Call parent implementation
	.set_active(value, immediate)
	# Force update the state immediately
	_update_visuals()

func interact(_from = null) -> void:
	"""Toggle energy state. Called by player interaction or pipeline."""
	# Use the base class toggle via set_active
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
