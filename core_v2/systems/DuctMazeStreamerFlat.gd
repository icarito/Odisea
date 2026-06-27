tool
extends Spatial

# FD-053: Flat Duct Maze Streamer (Scaffold-based)
const ScaffoldMSTGenerator = preload("res://core_v2/systems/ScaffoldMSTGenerator.gd")

export(int) var grid_width := 8
export(int) var grid_depth := 8
export(int) var room_count := 4
export(int) var extra_cycles := 2
export(float) var cell_size := 4.0
export(int) var maze_seed := 42

export(Material) var mat_hull = preload("res://core_v2/props/duct/DuctHull.tres")
export(Material) var mat_floor = preload("res://core_v2/props/duct/DuctFloorGrate.tres")
export(Material) var mat_conduit = preload("res://core_v2/props/duct/DuctConduit.tres")

const PROP_LAYER = 64 # Layer 7
const INNER_R = 2.0
const OUTER_R = 2.35
const RING_OUTER_R = 2.45

func _ready():
	generate()

func generate():
	# Clear existing
	for child in get_children():
		child.queue_free()

	var mst = ScaffoldMSTGenerator.new()
	mst.apply_params({
		"grid_width": grid_width,
		"grid_depth": grid_depth,
		"cell_size": cell_size,
		"room_count_min": room_count,
		"room_count_max": room_count,
		"extra_cycles": extra_cycles,
		"mst_max_height_steps": 1 # Keep it flat
	})

	var grid_data = mst.generate_grid_data(maze_seed)

	for i in range(grid_data.size()):
		var data = grid_data[i]
		if data == null: continue

		var gx = i % grid_width
		var gy = i / grid_width

		var tile = _instantiate_tile(data)
		add_child(tile)
		tile.translation = Vector3(gx * cell_size, 0, gy * cell_size)

func _instantiate_tile(data) -> Spatial:
	var root = Spatial.new()
	var variant = data.variant
	var id = variant.id
	var rot = variant.rotation

	var body = StaticBody.new()
	body.collision_layer = PROP_LAYER
	body.collision_mask = 0
	root.add_child(body)

	var hull_mesh = MeshInstance.new()
	hull_mesh.material_override = mat_hull
	body.add_child(hull_mesh)

	var floor_mesh = MeshInstance.new()
	floor_mesh.material_override = mat_floor
	body.add_child(floor_mesh)

	var conduit_mesh = MeshInstance.new()
	conduit_mesh.material_override = mat_conduit
	body.add_child(conduit_mesh)

	match id:
		"W": # Straight
			hull_mesh.mesh = _get_straight_mesh()
			floor_mesh.mesh = _get_straight_floor()
			conduit_mesh.mesh = _get_straight_rings()
			var col = CollisionShape.new()
			var shape = CylinderShape.new()
			shape.radius = INNER_R
			shape.height = cell_size
			col.shape = shape
			col.rotation_degrees.x = 90
			body.add_child(col)
		"E": # Endcap
			hull_mesh.mesh = _get_endcap_mesh()
			floor_mesh.mesh = _get_endcap_floor()
			conduit_mesh.mesh = _get_endcap_rings()
			var col = CollisionShape.new()
			var shape = CylinderShape.new()
			shape.radius = INNER_R
			shape.height = cell_size * 0.5
			col.shape = shape
			col.rotation_degrees.x = 90
			col.translation.z = -cell_size * 0.25
			body.add_child(col)
		"C": # Elbow
			hull_mesh.mesh = _get_elbow_mesh()
			floor_mesh.mesh = _get_elbow_floor()
			conduit_mesh.mesh = _get_elbow_rings()
			_add_elbow_collision(body)
		"T": # T-Junction
			hull_mesh.mesh = _get_t_junction_mesh()
			floor_mesh.mesh = _get_t_junction_floor()
			conduit_mesh.mesh = _get_t_junction_rings()
			_add_junction_collision(body, 3)
		"X": # X-Junction
			hull_mesh.mesh = _get_x_junction_mesh()
			floor_mesh.mesh = _get_x_junction_floor()
			conduit_mesh.mesh = _get_x_junction_rings()
			_add_junction_collision(body, 4)
		"S": # Incline (fallback to straight for v1)
			hull_mesh.mesh = _get_straight_mesh()
			floor_mesh.mesh = _get_straight_floor()
			conduit_mesh.mesh = _get_straight_rings()
			var col = CollisionShape.new()
			var shape = CylinderShape.new()
			shape.radius = INNER_R
			shape.height = cell_size
			col.shape = shape
			col.rotation_degrees.x = 90
			body.add_child(col)

	root.rotation_degrees.y = -rot
	return root

func _get_straight_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size, 16)
	st.generate_normals()
	return st.commit()

func _get_straight_rings() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, cell_size * 0.5 - 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, -cell_size * 0.5 + 0.1))
	st.generate_normals()
	return st.commit()

func _get_straight_floor() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = INNER_R * 1.4
	_add_quad(st, Vector3(-w*0.5, -INNER_R+0.1, -cell_size*0.5), Vector3(w*0.5, -INNER_R+0.1, -cell_size*0.5),
				 Vector3(w*0.5, -INNER_R+0.1, cell_size*0.5), Vector3(-w*0.5, -INNER_R+0.1, cell_size*0.5))
	st.generate_normals()
	return st.commit()

func _get_endcap_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size * 0.5, 16, Vector3(0, 0, -cell_size * 0.25))
	_add_cap(st, OUTER_R, 16, Vector3(0, 0, 0))
	st.generate_normals()
	return st.commit()

func _get_endcap_rings() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, -cell_size * 0.5 + 0.1))
	st.generate_normals()
	return st.commit()

func _get_endcap_floor() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = INNER_R * 1.4
	_add_quad(st, Vector3(-w*0.5, -INNER_R+0.1, -cell_size*0.5), Vector3(w*0.5, -INNER_R+0.1, -cell_size*0.5),
				 Vector3(w*0.5, -INNER_R+0.1, 0), Vector3(-w*0.5, -INNER_R+0.1, 0))
	st.generate_normals()
	return st.commit()

func _get_elbow_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_arc(st, INNER_R, OUTER_R, cell_size * 0.5, 90, 16, 8)
	st.generate_normals()
	return st.commit()

func _get_elbow_rings() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, -cell_size * 0.5 + 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(cell_size * 0.5 - 0.1, 0, 0), Vector3(0, 90, 0))
	st.generate_normals()
	return st.commit()

func _get_elbow_floor() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc_r = cell_size * 0.5
	var pivot = Vector3(arc_r, 0, -arc_r)
	var w = INNER_R * 1.4
	var segments = 4
	for i in range(segments):
		var t0 = float(i) / segments * PI/2.0
		var t1 = float(i + 1) / segments * PI/2.0
		var c0 = pivot + Vector3(-cos(t0) * arc_r, -INNER_R+0.1, sin(t0) * arc_r)
		var c1 = pivot + Vector3(-cos(t1) * arc_r, -INNER_R+0.1, sin(t1) * arc_r)
		var d0 = Vector3(-cos(t0), 0, sin(t0)).cross(Vector3.UP)
		var d1 = Vector3(-cos(t1), 0, sin(t1)).cross(Vector3.UP)
		_add_quad(st, c0 - d0 * w*0.5, c0 + d0 * w*0.5, c1 + d1 * w*0.5, c1 - d1 * w*0.5)
	st.generate_normals()
	return st.commit()

func _get_t_junction_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size, 16) # N-S
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size * 0.5, 16, Vector3(cell_size*0.25, 0, 0), Vector3(0, 90, 0)) # E stub
	st.generate_normals()
	return st.commit()

func _get_t_junction_rings() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, cell_size * 0.5 - 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, -cell_size * 0.5 + 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(cell_size * 0.5 - 0.1, 0, 0), Vector3(0, 90, 0))
	st.generate_normals()
	return st.commit()

func _get_t_junction_floor() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = INNER_R * 1.4
	_add_quad(st, Vector3(-w*0.5, -INNER_R+0.1, -cell_size*0.5), Vector3(w*0.5, -INNER_R+0.1, -cell_size*0.5),
				 Vector3(w*0.5, -INNER_R+0.1, cell_size*0.5), Vector3(-w*0.5, -INNER_R+0.1, cell_size*0.5))
	_add_quad(st, Vector3(0, -INNER_R+0.1, -w*0.5), Vector3(cell_size*0.5, -INNER_R+0.1, -w*0.5),
				 Vector3(cell_size*0.5, -INNER_R+0.1, w*0.5), Vector3(0, -INNER_R+0.1, w*0.5))
	st.generate_normals()
	return st.commit()

func _get_x_junction_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size, 16) # N-S
	_add_hollow_cylinder(st, INNER_R, OUTER_R, cell_size, 16, Vector3(0,0,0), Vector3(0,90,0)) # E-W
	st.generate_normals()
	return st.commit()

func _get_x_junction_rings() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, cell_size * 0.5 - 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(0, 0, -cell_size * 0.5 + 0.1))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(cell_size * 0.5 - 0.1, 0, 0), Vector3(0, 90, 0))
	_add_hollow_cylinder(st, OUTER_R, RING_OUTER_R, 0.2, 16, Vector3(-cell_size * 0.5 + 0.1, 0, 0), Vector3(0, 90, 0))
	st.generate_normals()
	return st.commit()

func _get_x_junction_floor() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = INNER_R * 1.4
	_add_quad(st, Vector3(-w*0.5, -INNER_R+0.1, -cell_size*0.5), Vector3(w*0.5, -INNER_R+0.1, -cell_size*0.5),
				 Vector3(w*0.5, -INNER_R+0.1, cell_size*0.5), Vector3(-w*0.5, -INNER_R+0.1, cell_size*0.5))
	_add_quad(st, Vector3(-cell_size*0.5, -INNER_R+0.1, -w*0.5), Vector3(cell_size*0.5, -INNER_R+0.1, -w*0.5),
				 Vector3(cell_size*0.5, -INNER_R+0.1, w*0.5), Vector3(-cell_size*0.5, -INNER_R+0.1, w*0.5))
	st.generate_normals()
	return st.commit()

func _add_hollow_cylinder(st: SurfaceTool, inner_r: float, outer_r: float, height: float, sides: int, offset := Vector3.ZERO, rot := Vector3.ZERO):
	var basis = Basis(rot * PI / 180.0)
	var half_h = height * 0.5
	for i in range(sides):
		var a0 = float(i) / sides * TAU
		var a1 = float(i + 1) / sides * TAU
		var p_in_0_bot = basis.xform(Vector3(cos(a0) * inner_r, sin(a0) * inner_r, -half_h)) + offset
		var p_in_1_bot = basis.xform(Vector3(cos(a1) * inner_r, sin(a1) * inner_r, -half_h)) + offset
		var p_in_0_top = basis.xform(Vector3(cos(a0) * inner_r, sin(a0) * inner_r, half_h)) + offset
		var p_in_1_top = basis.xform(Vector3(cos(a1) * inner_r, sin(a1) * inner_r, half_h)) + offset
		var p_out_0_bot = basis.xform(Vector3(cos(a0) * outer_r, sin(a0) * outer_r, -half_h)) + offset
		var p_out_1_bot = basis.xform(Vector3(cos(a1) * outer_r, sin(a1) * outer_r, -half_h)) + offset
		var p_out_0_top = basis.xform(Vector3(cos(a0) * outer_r, sin(a0) * outer_r, half_h)) + offset
		var p_out_1_top = basis.xform(Vector3(cos(a1) * outer_r, sin(a1) * outer_r, half_h)) + offset
		_add_quad(st, p_in_1_bot, p_in_0_bot, p_in_0_top, p_in_1_top)
		_add_quad(st, p_out_0_bot, p_out_1_bot, p_out_1_top, p_out_0_top)

func _add_hollow_arc(st: SurfaceTool, inner_r: float, outer_r: float, pivot_dist: float, angle_deg: float, radial_sides: int, arc_segments: int):
	var arc_r = pivot_dist
	for j in range(arc_segments):
		var t0 = float(j) / arc_segments * deg2rad(angle_deg)
		var t1 = float(j + 1) / arc_segments * deg2rad(angle_deg)
		var pivot = Vector3(pivot_dist, 0, -pivot_dist)
		for i in range(radial_sides):
			var a0 = float(i) / radial_sides * TAU
			var a1 = float(i + 1) / radial_sides * TAU
			var pts = []
			for t in [t0, t1]:
				var center = pivot + Vector3(-cos(t) * arc_r, 0, sin(t) * arc_r)
				var normal = Vector3(-cos(t), 0, sin(t))
				var up = Vector3.UP
				var p_radial = []
				for a in [a0, a1]:
					var v = (normal * cos(a) * inner_r) + (up * sin(a) * inner_r)
					p_radial.append(center + v)
					v = (normal * cos(a) * outer_r) + (up * sin(a) * outer_r)
					p_radial.append(center + v)
				pts.append(p_radial)
			_add_quad(st, pts[1][2], pts[0][2], pts[0][0], pts[1][0])
			_add_quad(st, pts[0][3], pts[1][3], pts[1][1], pts[0][1])

func _add_cap(st: SurfaceTool, radius: float, sides: int, offset: Vector3):
	for i in range(sides):
		var a0 = float(i) / sides * TAU
		var a1 = float(i + 1) / sides * TAU
		st.add_vertex(offset)
		st.add_vertex(offset + Vector3(cos(a1) * radius, sin(a1) * radius, 0))
		st.add_vertex(offset + Vector3(cos(a0) * radius, sin(a0) * radius, 0))

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3):
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _add_elbow_collision(body: StaticBody):
	var arc_r = cell_size * 0.5
	var pivot = Vector3(arc_r, 0, -arc_r)
	for i in range(3):
		var t = (float(i) + 0.5) / 3.0 * PI/2.0
		var pos = pivot + Vector3(-cos(t) * arc_r, 0, sin(t) * arc_r)
		var col = CollisionShape.new()
		var shape = BoxShape.new()
		shape.extents = Vector3(1.0, INNER_R, 1.0)
		col.shape = shape
		col.translation = pos
		col.rotation.y = t
		body.add_child(col)

func _add_junction_collision(body: StaticBody, arms: int):
	var col_sphere = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = INNER_R * 1.25
	col_sphere.shape = sphere
	body.add_child(col_sphere)
	for i in range(arms):
		var angle = i * PI/2.0
		if arms == 3 and i == 2: angle = PI
		var col = CollisionShape.new()
		var shape = CylinderShape.new()
		shape.radius = INNER_R
		shape.height = cell_size * 0.5
		col.shape = shape
		col.rotation_degrees.x = 90
		col.rotation.y = -angle
		col.translation = Vector3(0, 0, -cell_size * 0.25).rotated(Vector3.UP, -angle)
		body.add_child(col)
