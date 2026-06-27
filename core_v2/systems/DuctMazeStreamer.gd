tool
extends Spatial
class_name DuctMazeStreamer

# FD-052: Act 0 — Duct Maze Streamer (Rewrite v3)
# Procedural radial duct maze generation.

export var inner_radius := 2.0
export var ring_step := 4.0
export var sectors := 12
export var rings := 3
export var height_steps := 6
export var room_count := 4
export var extra_cycles := 2
export var seed_value := -1

# Visual Params
export var duct_radius := 2.0
export var duct_wall_thickness := 0.35
export var ring_spacing := 4.0
export var ring_height := 0.15
export var ring_extra_radius := 0.35

const DUCT_LAYER := 1 << 6 # bit 6 = layer 7 (Prop)

# Resource paths
const HULL_MAT_PATH := "res://core_v2/props/duct/DuctHull.tres"
const FLOOR_MAT_PATH := "res://core_v2/props/duct/DuctFloorGrate.tres"
const LIGHT_STRIP_MAT_PATH := "res://core_v2/props/duct/DuctLightStrip.tres"
const CONDUIT_MAT_PATH := "res://core_v2/props/duct/DuctConduit.tres"
const HAZARD_MAT_PATH := "res://core_v2/props/duct/DuctHazardStripe.tres"
const VALVE_PATH := "res://core_v2/props/pipe/PipeValve.tscn"
const AIRLOCK_CHAMBER_PATH := "res://core_v2/props/doors/AirlockChamber.tscn"
const IRIS_DOOR_PATH := "res://core_v2/components/IrisDoorV2.tscn"

var _resource_cache := {}
var _mesh_cache := {}

func _ready():
	if not Engine.editor_hint:
		generate()

func _get_res(path: String):
	if not _resource_cache.has(path):
		if ResourceLoader.exists(path):
			_resource_cache[path] = load(path)
		else:
			_resource_cache[path] = null
	return _resource_cache[path]

func generate() -> void:
	for child in get_children():
		child.queue_free()
	
	var mst_gen = ScaffoldMSTGenerator.new()
	var params = {
		"grid_width": sectors,
		"grid_depth": rings,
		"mst_max_height_steps": height_steps,
		"room_count": room_count,
		"extra_cycles": extra_cycles,
		"wrap_x": true
	}
	mst_gen.apply_params(params)
	var grid = mst_gen.generate_grid_data(seed_value)
	
	var last_cell_idx = -1
	var max_gy = -1
	var max_h = -1.0
	
	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null: continue
		
		var gx := i % sectors
		var gy := i / sectors
		
		# Find the exit cell candidate (furthest gy, then highest height)
		if gy > max_gy or (gy == max_gy and cell.base_height > max_h):
			max_gy = gy
			max_h = cell.base_height
			last_cell_idx = i

	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null: continue
		
		var gx := i % sectors
		var gy := i / sectors
		var v = cell.variant
		
		if i == last_cell_idx:
			_add_exit_airlock(cell, i)
			continue
		
		var tile = instantiate_tile(gx, gy, cell)
		if tile:
			add_child(tile)
			tile.transform = _grid_to_world(gx, gy, cell.base_height)
			# Apply local rotation. Following ODI-001, Z is always forward.
			# Radial ducts (rot 0) face Z radial.
			# Arcs (rot 90/270) face Z tangential.
			tile.rotate_object_local(Vector3.UP, deg2rad(v.rotation))

func _grid_to_world(gx: int, gy: int, height: float) -> Transform:
	var angle_deg := float(gx) * (360.0 / sectors)
	var angle_rad := deg2rad(angle_deg)
	var radius := inner_radius + (float(gy) + 0.5) * ring_step

	var world_x := radius * cos(angle_rad)
	var world_z := radius * sin(angle_rad)
	var pos := Vector3(world_x, height, world_z)

	# Basis following FD-052 Section 2.4:
	# tangent = circunferencial (Basis.x)
	# up = Vector3.UP (Basis.y)
	# radial = radial (Basis.z)
	var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad))
	var up := Vector3.UP
	var radial := Vector3(cos(angle_rad), 0, sin(angle_rad))

	return Transform(Basis(tangent, up, radial), pos)

func instantiate_tile(gx: int, gy: int, cell: Dictionary) -> Spatial:
	var v = cell.variant
	var id = v.id
	var is_room = cell.get("is_room", false)
	
	var tile: Spatial = null
	if is_room and _grado(v.connections) >= 2 and id in ["C", "T", "X"]:
		tile = make_capsule(v.connections, gy)
	else:
		match id:
			"W":
				if int(v.rotation) % 180 == 0:
					tile = make_duct_radial(gy)
				else:
					tile = make_duct_arc(gx, gy)
			"C", "T", "X":
				tile = make_junction(id, v.connections)
			"S":
				tile = make_incline(v.port_heights)
			"E":
				tile = make_endcap()
	
	if tile:
		tile.set_meta("gx", gx)
		tile.set_meta("gy", gy)
		_add_content_overlay(tile, gy)
		_apply_duct_properties(tile)
		_add_collapse_trigger(tile)
	
	return tile

func _add_collapse_trigger(tile: Spatial) -> void:
	var area = Area.new()
	area.name = "CollapseTrigger"
	var shape = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = 3.0
	shape.shape = sphere
	area.add_child(shape)
	tile.add_child(area)
	area.connect("body_entered", self, "_on_collapse_triggered", [tile])

func _on_collapse_triggered(body: Node, tile: Spatial) -> void:
	if body.name.begins_with("Pilot") or body.name.begins_with("Player"):
		var blocker = make_endcap()
		tile.add_child(blocker)
		
		# Place blocker behind the player based on the tile's orientation
		# Z is the forward axis.
		blocker.translation = Vector3(0, 0, -ring_step * 0.5)
		blocker.name = "CollapseBlocker"
		# Disconnect to avoid re-triggering
		var area = tile.get_node_or_null("CollapseTrigger")
		if area: area.queue_free()

func _apply_duct_properties(node: Node) -> void:
	if node is CollisionObject:
		node.collision_layer = DUCT_LAYER
		node.collision_mask = 255 # Collide with player
	for child in node.get_children():
		_apply_duct_properties(child)

func make_duct_radial(gy: int) -> Spatial:
	var root = Spatial.new()
	root.name = "DuctRadial"
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = _get_hollow_cylinder(ring_step, duct_radius, duct_wall_thickness)
	mesh_instance.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(mesh_instance)
	
	_add_collision_cylinder(root, ring_step, duct_radius)
	_add_structural_rings(root, Vector3.FORWARD, ring_step, duct_radius)
	_add_floor_grate(root, ring_step, duct_radius)
	
	return root

func make_duct_arc(gx: int, gy: int) -> Spatial:
	var root = Spatial.new()
	root.name = "DuctArc"
	var radius := inner_radius + (float(gy) + 0.5) * ring_step
	var arc_deg := 360.0 / sectors
	var arc_rad := deg2rad(arc_deg)
	
	var mesh_instance = MeshInstance.new()
	# The builder now generates arcs aligned with Z axis
	mesh_instance.mesh = DuctArcBuilder.get_or_build_arc(radius, duct_radius, arc_deg, 16)
	mesh_instance.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(mesh_instance)
	
	# Floor grate for the arc
	var segments_f = 8
	for i in range(segments_f):
		var u = (float(i + 0.5) / segments_f - 0.5) * arc_rad
		var grate = MeshInstance.new()
		var grate_mesh = QuadMesh.new()
		grate_mesh.size = Vector2(duct_radius * 1.5, (radius * arc_rad) / segments_f)
		grate.mesh = grate_mesh
		grate.material_override = _get_res(FLOOR_MAT_PATH)
		
		var x = radius * cos(u) - radius
		var z = radius * sin(u)
		grate.translation = Vector3(x, -duct_radius + 0.1, z)
		grate.rotation.y = -u
		grate.rotation.x = -PI * 0.5
		root.add_child(grate)
	
	# Segmented collision for the arc using BoxShape
	var segments = 8
	var body = StaticBody.new()
	root.add_child(body)
	for i in range(segments):
		var u_start = (float(i) / segments - 0.5) * arc_rad
		var u_end = (float(i+1) / segments - 0.5) * arc_rad
		var u_mid = (u_start + u_end) * 0.5
		
		var shape = CollisionShape.new()
		var box = BoxShape.new()
		var length = radius * (u_end - u_start)
		# Extents are half-sizes
		box.extents = Vector3(duct_radius, duct_radius, length * 0.5)
		shape.shape = box
		
		var x = radius * cos(u_mid) - radius
		var z = radius * sin(u_mid)
		shape.translation = Vector3(x, 0, z)
		shape.rotation.y = -u_mid
		body.add_child(shape)
	
	# Structural rings following the arc
	_add_structural_rings_arc(root, radius, arc_deg, 3)
	
	return root

func _add_structural_rings_arc(root: Spatial, R: float, arc_deg: float, count: int) -> void:
	var arc_rad = deg2rad(arc_deg)
	for i in range(count):
		var u = (float(i) / (count - 1) - 0.5) * arc_rad
		var ring = MeshInstance.new()
		var ring_mesh = CylinderMesh.new()
		ring_mesh.top_radius = duct_radius + ring_extra_radius
		ring_mesh.bottom_radius = duct_radius + ring_extra_radius
		ring_mesh.height = ring_height
		ring.mesh = ring_mesh
		ring.material_override = _get_res(CONDUIT_MAT_PATH)
		
		var x = R * cos(u) - R
		var z = R * sin(u)
		ring.translation = Vector3(x, 0, z)
		ring.rotation.y = -u
		ring.rotation.x = PI * 0.5
		root.add_child(ring)

func make_junction(id: String, connections: Array) -> Spatial:
	var root = Spatial.new()
	root.name = "Junction_" + id
	
	# Central hub
	var sphere = MeshInstance.new()
	sphere.mesh = _get_sphere_mesh(2.5)
	sphere.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(sphere)
	_add_collision_sphere(root, 2.5)
	
	# Arms (Z = Forward, X = Right)
	var dirs = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in range(4):
		if connections[i]:
			var arm = make_arm(dirs[i], ring_step * 0.5, duct_radius)
			root.add_child(arm)
	
	return root

func make_arm(dir: Vector3, length: float, radius: float) -> Spatial:
	var arm = Spatial.new()
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(length, radius, duct_wall_thickness)
	mesh.material_override = _get_res(HULL_MAT_PATH)
	arm.add_child(mesh)
	
	var look_dir = dir
	if look_dir == Vector3.UP or look_dir == Vector3.DOWN:
		arm.look_at(look_dir, Vector3.RIGHT)
	else:
		arm.look_at(look_dir, Vector3.UP)
	arm.translation = dir * length * 0.5
	
	_add_collision_cylinder(arm, length, radius)
	return arm

func make_incline(port_heights: Array) -> Spatial:
	var root = Spatial.new()
	root.name = "DuctIncline"
	
	# S variant has two ports: one at 0, one at +/- HEIGHT_STEP
	var h1 = 0.0
	for h in port_heights:
		if abs(h) > 0.001:
			h1 = h
			break

	var length = ring_step
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = _get_hollow_cylinder(length, duct_radius, duct_wall_thickness)
	mesh_instance.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(mesh_instance)
	
	# Slope the duct
	# Length must be the hypotenuse to bridge the gap between cells
	var hypotenuse = sqrt(length * length + h1 * h1)
	mesh_instance.mesh = _get_hollow_cylinder(hypotenuse, duct_radius, duct_wall_thickness)
	
	var angle = atan2(h1, length)
	mesh_instance.rotation.x = angle
	mesh_instance.translation.y = h1 * 0.5
	
	var body = _add_collision_cylinder(root, hypotenuse, duct_radius)
	body.rotation.x = angle
	body.translation.y = h1 * 0.5
	
	_add_structural_rings(root, Vector3.FORWARD, length, duct_radius)
	return root

func make_endcap() -> Spatial:
	var root = Spatial.new()
	root.name = "DuctEndCap"
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(1.0, duct_radius, duct_wall_thickness)
	mesh.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(mesh)
	
	# Solid cap
	var cap = MeshInstance.new()
	var cap_mesh = CylinderMesh.new()
	cap_mesh.top_radius = duct_radius + duct_wall_thickness
	cap_mesh.bottom_radius = duct_radius + duct_wall_thickness
	cap_mesh.height = 0.1
	cap.mesh = cap_mesh
	cap.material_override = _get_res(HULL_MAT_PATH)
	cap.translation = Vector3(0, 0, 0.5)
	cap.rotation.x = PI * 0.5
	root.add_child(cap)
	
	_add_collision_cylinder(root, 1.0, duct_radius)
	return root

func make_capsule(connections: Array, gy: int) -> Spatial:
	var root = Spatial.new()
	root.name = "CapsuleRoom"
	
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = _get_capsule_mesh(3.0, 4.0)
	mesh_instance.material_override = _get_res(HULL_MAT_PATH)
	root.add_child(mesh_instance)
	
	_add_collision_capsule(root, 4.0, 3.0)
	
	# Ports
	var dirs = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in range(4):
		if connections[i]:
			var arm = make_arm(dirs[i], 2.0, duct_radius)
			arm.translation = dirs[i] * 4.0
			root.add_child(arm)
			
	# Lights
	var light = OmniLight.new()
	light.light_energy = 1.0
	light.omni_range = 10.0
	root.add_child(light)
	
	# Decoration
	var valve_scene = _get_res(VALVE_PATH)
	if valve_scene:
		var valve = valve_scene.instance()
		root.add_child(valve)
		valve.translation = Vector3(1.5, -2.0, 0.0)
	
	return root

func _get_hollow_cylinder(length: float, radius: float, thickness: float) -> ArrayMesh:
	var key = "h_cyl_%f_%f_%f" % [length, radius, thickness]
	if _mesh_cache.has(key): return _mesh_cache[key]
	
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 16
	var half_l = length * 0.5
	
	for i in range(segments):
		var a0 = TAU * i / segments
		var a1 = TAU * (i + 1) / segments
		var c0 = cos(a0); var s0 = sin(a0)
		var c1 = cos(a1); var s1 = sin(a1)
		
		# Inner
		var p0 = Vector3(radius * c0, radius * s0, -half_l)
		var p1 = Vector3(radius * c1, radius * s1, -half_l)
		var p2 = Vector3(radius * c0, radius * s0, half_l)
		var p3 = Vector3(radius * c1, radius * s1, half_l)
		
		st.add_normal(Vector3(-c0, -s0, 0))
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
		st.add_vertex(p1); st.add_vertex(p3); st.add_vertex(p2)
		
		# Outer
		var orad = radius + thickness
		var op0 = Vector3(orad * c0, orad * s0, -half_l)
		var op1 = Vector3(orad * c1, orad * s1, -half_l)
		var op2 = Vector3(orad * c0, orad * s0, half_l)
		var op3 = Vector3(orad * c1, orad * s1, half_l)
		
		st.add_normal(Vector3(c0, s0, 0))
		st.add_vertex(op2); st.add_vertex(op1); st.add_vertex(op0)
		st.add_vertex(op2); st.add_vertex(op3); st.add_vertex(op1)

	var mesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

func _get_sphere_mesh(radius: float) -> ArrayMesh:
	var key = "sphere_%f" % radius
	if _mesh_cache.has(key): return _mesh_cache[key]
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	_mesh_cache[key] = mesh
	return mesh

func _get_capsule_mesh(radius: float, height: float) -> ArrayMesh:
	var key = "capsule_%f_%f" % [radius, height]
	if _mesh_cache.has(key): return _mesh_cache[key]
	var cap = CapsuleMesh.new()
	cap.radius = radius
	cap.mid_height = height
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cap.get_mesh_arrays())
	_mesh_cache[key] = mesh
	return mesh

func _add_collision_cylinder(root: Node, length: float, radius: float) -> StaticBody:
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var cylinder = CylinderShape.new()
	cylinder.radius = radius
	cylinder.height = length
	shape.shape = cylinder
	shape.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_collision_sphere(root: Node, radius: float) -> StaticBody:
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = radius
	shape.shape = sphere
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_collision_capsule(root: Node, height: float, radius: float) -> StaticBody:
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var capsule = CapsuleShape.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.rotation_degrees = Vector3(90, 0, 0)
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_structural_rings(root: Node, axis: Vector3, length: float, radius: float, count: int = 2) -> void:
	for i in range(count):
		var ring = MeshInstance.new()
		var ring_mesh = CylinderMesh.new()
		ring_mesh.top_radius = radius + ring_extra_radius
		ring_mesh.bottom_radius = radius + ring_extra_radius
		ring_mesh.height = ring_height
		ring.mesh = ring_mesh
		ring.material_override = _get_res(CONDUIT_MAT_PATH)
		
		var t = -length * 0.5 + (length / (count + 1)) * (i + 1)
		ring.translation = axis * t
		ring.rotation_degrees = Vector3(90, 0, 0)
		root.add_child(ring)

func _add_floor_grate(root: Node, length: float, radius: float) -> void:
	var grate = MeshInstance.new()
	var grate_mesh = QuadMesh.new()
	grate_mesh.size = Vector2(radius * 1.5, length)
	grate.mesh = grate_mesh
	grate.material_override = _get_res(FLOOR_MAT_PATH)
	grate.translation = Vector3(0, -radius + 0.1, 0)
	grate.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(grate)

func _add_content_overlay(node: Spatial, gy: int) -> void:
	var color = Color.white
	var zone = "Air"
	if gy >= 2:
		color = Color.cyan; zone = "Gas"
	elif gy == 1:
		color = Color.blue; zone = "Water"
	else:
		color = Color(0.5, 0.5, 0.5); zone = "Air"
	
	node.set_meta("zone", zone)
	
	var light = OmniLight.new()
	light.light_color = color
	light.light_energy = 0.4
	light.omni_range = 8.0
	node.add_child(light)

	if zone != "Air" and node.name == "CapsuleRoom":
		_apply_tint(node, color)

func _apply_tint(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance:
			var mat = child.material_override
			if not mat:
				mat = child.mesh.surface_get_material(0) if child.mesh else null
			if mat is SpatialMaterial:
				var new_mat = mat.duplicate()
				new_mat.albedo_color = new_mat.albedo_color.linear_interpolate(color, 0.3)
				child.material_override = new_mat
		_apply_tint(child, color)

func _add_exit_airlock(cell: Dictionary, idx: int) -> void:
	var airlock_scene = _get_res(AIRLOCK_CHAMBER_PATH)
	if not airlock_scene: return
	
	var airlock = airlock_scene.instance()
	add_child(airlock)
	
	var gx := idx % sectors
	var gy := idx / sectors
	airlock.transform = _grid_to_world(gx, gy, cell.base_height)
	airlock.rotate_object_local(Vector3.UP, PI) # Orient outward
	
	# Add Iris Door
	var iris_scene = _get_res(IRIS_DOOR_PATH)
	if iris_scene:
		var iris = iris_scene.instance()
		airlock.add_child(iris)
		iris.translation = Vector3(0, 0, 0)
		iris.scale = Vector3.ONE * (duct_radius / 1.7)
		_apply_duct_properties(iris)

func _grado(conn: Array) -> int:
	var count = 0
	for c in conn:
		if c: count += 1
	return count
