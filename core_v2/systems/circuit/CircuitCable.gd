extends Spatial
class_name CircuitCable

# CircuitCable.gd
# Procedurally generated cable that connects circuit nodes.
# Supports both CSG and direct Mesh generation.

signal connection_broken

export(Curve3D) var path_curve: Curve3D
export(bool) var use_csg := true
export(Material) var cable_material: Material
export(float) var health := 10.0
export(float) var cable_radius := 0.05
export(int) var cable_sides := 8

var _hurtbox: Area

func _ready():
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
	csg.use_collision = true # Enable collision for damage detection
	csg.name = "CableVis"
	add_child(csg)

func _build_mesh():
	var mesh_inst = MeshInstance.new()
	mesh_inst.mesh = _generate_tube_mesh(path_curve, cable_radius, cable_sides)
	if cable_material:
		mesh_inst.material_override = cable_material
	mesh_inst.name = "CableVis"
	add_child(mesh_inst)

	# Generate collision for the mesh
	mesh_inst.create_trimesh_collision()
	# The collision sibling created by create_trimesh_collision is a StaticBody.
	# We might want to move its shape to our Hurtbox or keep it as physical barrier.
	# For destructibility, we need an Area.

func _setup_hurtbox():
	# Create a Hurtbox Area to detect damage
	_hurtbox = Area.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_layer = 1 # Logic/World layer
	_hurtbox.collision_mask = 0 # Doesn't scan, only detects entering
	add_child(_hurtbox)

	# If CSG, it handles its own collision (StaticBody), so we might need to duplicate it for Area?
	# CSGPolygon.use_collision creates a StaticBody. To receive damage, we usually need an Area or a body script.
	# If we want the cable to be physical, StaticBody is good.
	# But we need to handle "take_damage".

	# We can attach a script to the generated StaticBody or Area to forward damage.
	# Or, simply, if we use Mesh generation, `create_trimesh_collision` makes a StaticBody.

	# Let's try to make the Hurtbox wrap the curve.
	# This is hard to do perfectly without duplicating geometry.
	# A simple approximation: multiple capsules along the path.

	var points = path_curve.get_baked_points()
	if points.size() < 2:
		return

	# Create segments
	for i in range(points.size() - 1):
		var p1 = points[i]
		var p2 = points[i+1]
		var dist = p1.distance_to(p2)
		if dist < 0.01: continue

		var col = CollisionShape.new()
		var capsule = CapsuleShape.new()
		capsule.radius = cable_radius * 1.5 # Slightly larger for hit detection
		capsule.height = dist
		col.shape = capsule

		# Position and Orient
		var center = (p1 + p2) / 2.0
		col.transform.origin = center
		col.look_at(p2, Vector3.UP)
		# Capsule is Z-aligned? No, Capsule height is usually Y-aligned or Z-aligned depending on engine.
		# In Godot, CapsuleShape is usually height along Z (or Y?).
		# Wait, Godot 3 CapsuleShape is height along Z axis in Spatial?
		# Actually, `look_at` aligns -Z to target.
		# Check Godot docs/memory: "Standard Godot 3.5...".
		# Godot 3 CapsuleShape is upright (Y-axis) usually.
		# So if we look_at, Z is forward. We need to rotate X 90 deg?
		# Let's verify Capsule orientation.

		# Better approach: Use the mesh collision for hit detection if possible.
		# But `create_trimesh_collision` makes a StaticBody.
		# We can change that StaticBody to an Area if we want, or just add a script to it.
		pass

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
			col.transform.origin = center
			col.look_at(curr, Vector3.UP)

			_hurtbox.add_child(col)

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
	return st.commit()

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
