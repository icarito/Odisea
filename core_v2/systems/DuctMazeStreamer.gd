tool
extends Spatial
class_name DuctMazeStreamer

# FD-052: Act 0 — Duct Maze Streamer (Rewrite v3)
# Procedural radial duct maze generation.

export var inner_radius := 2.0
export var ring_step := 4.0      # axial length of each duct segment (NOT radial spacing)
export var sectors := 12
export var rings := 3
export var height_steps := 6

# Concentric radial fill (FD-052): the maze fills the cylinder interior. Rings grow
# INWARD from the wall so everything stays inside the Core shell (radius ~30).
export var wall_radius := 28.0   # outermost ring radius; keep < Core inner shell (30)
export var radial_step := 1.5    # radial gap between concentric rings
# Axial spread: MST base_height has only `height_steps` discrete levels (×2m each),
# which is a thin slice in an 8000-long tube. Scale it so the maze spans the axis.
export var axial_scale := 1.0
export var room_count := 4
export var extra_cycles := 2
export var seed_value := -1

# Visual Params
export var duct_radius := 2.0
export var duct_wall_thickness := 0.35
export var ring_spacing := 4.0
export var ring_height := 0.15
export var ring_extra_radius := 0.35
# How far from the junction CENTRE each arm begins. Arms used to start at the hub
# centre (z=0), so an axial arm and an arc arm both filled the ~duct_radius ball at
# the origin and interpenetrated (~a couple of metres of clipping). Starting each arm
# at the hub rim instead leaves the centre clear; the hub collar + the arm overshoot
# still cover the joint so no gap opens.
export var junction_hub_reach := 0.8

const DUCT_LAYER := 1 << 6 # bit 6 = layer 7 (Prop)

# Resource paths
const HULL_MAT_PATH := "res://core_v2/props/duct/DuctHull.tres"
const FLOOR_MAT_PATH := "res://core_v2/props/duct/DuctFloorGrate.tres"
const LIGHT_STRIP_MAT_PATH := "res://core_v2/props/duct/DuctLightStrip.tres"
const CONDUIT_MAT_PATH := "res://core_v2/props/duct/DuctConduit.tres"
const HAZARD_MAT_PATH := "res://core_v2/props/duct/DuctHazardStripe.tres"
const VALVE_PATH := "res://core_v2/props/pipe/PipeValve.tscn"
const AIRLOCK_CHAMBER_PATH := "res://core_v2/props/doors/AirlockChamber.tscn"
const IRIS_DOOR_PATH := "res://core_v2/props/doors/IrisDoorV2.tscn"

var _resource_cache := {}
var _mesh_cache := {}

func _ready():
	generate()

func _get_res(path: String):
	if not _resource_cache.has(path):
		if ResourceLoader.exists(path):
			_resource_cache[path] = load(path)
		else:
			_resource_cache[path] = null
	return _resource_cache[path]

const AIRLOCK_HULL_SHADER := "res://core_v2/props/scifi_lights/shaders/airlock_hull.shader"
const DUCT_HULL_SHADER := "res://core_v2/props/duct/shaders/duct_hull.shader"

# All duct hull pieces: the airlock panel shader look, but forced CULL_DISABLED so that
# wherever an open mouth shows the tube interior (junctions, endcaps, capsule ports) the
# wall is visible from both sides — cull_back left those interior faces dark/inverted
# ("cull dañado"). Now that the straight tube mesh has UVs the panels render correctly,
# so cull_disabled no longer degenerates into a solid emissive fill.
func _hull_mat() -> Material:
	if _resource_cache.has("__hull_shared"):
		return _resource_cache["__hull_shared"]
	var mat = ShaderMaterial.new()
	var shader = _get_res(DUCT_HULL_SHADER)  # = airlock shader with render_mode cull_disabled
	if shader:
		mat.shader = shader
		mat.set_shader_param("seam_emission", 0.8)
		mat.set_shader_param("intensity", 0.7)
		_resource_cache["__hull_shared"] = mat
		return mat
	var fallback = SpatialMaterial.new()
	fallback.albedo_color = Color(0.22, 0.25, 0.28)
	fallback.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_resource_cache["__hull_shared"] = fallback
	return fallback

# STRAIGHT ducts: same panels but cull_disabled (visible from both sides, which the user
# wants) and with the emissive seams turned OFF — the straight tube was reading as fully
# emissive. intensity=0 kills the seam glow; the panels still shade normally.
func _hull_mat_straight() -> Material:
	if _resource_cache.has("__hull_straight"):
		return _resource_cache["__hull_straight"]
	var mat = ShaderMaterial.new()
	var shader = _get_res(DUCT_HULL_SHADER)
	if shader:
		mat.shader = shader
		mat.set_shader_param("seam_emission", 0.0)
		mat.set_shader_param("intensity", 0.0)
		_resource_cache["__hull_straight"] = mat
		return mat
	var fallback = SpatialMaterial.new()
	fallback.albedo_color = Color(0.22, 0.25, 0.28)
	fallback.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_resource_cache["__hull_straight"] = fallback
	return fallback

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
	
	# Airlocks are no longer dropped loose on the furthest cell. Instead they couple to
	# ROOMS at the mouth of an interactable (tangential E/W) connection — see
	# _select_airlock_cells / _add_room_airlock. This gives them spatial meaning
	# (entrance/exit of a chamber) instead of floating at an arbitrary endpoint.
	var airlock_cells := _select_airlock_cells(grid)

	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null: continue

		var gx := i % sectors
		var gy := i / sectors
		var v = cell.variant

		var tile = instantiate_tile(gx, gy, cell)
		if tile:
			# Capture the authored name BEFORE add_child: Godot auto-renames on a name
			# collision (e.g. "DuctArc" -> "@DuctArc@443"), and that "@" prefix broke the
			# begins_with("DuctArc") test in _grid_to_world, routing arcs through the
			# straight-duct basis (bug 3: arcs mis-oriented / not connecting).
			var tile_kind = String(tile.name)
			add_child(tile)
			tile.transform = _grid_to_world(gx, gy, cell.base_height, tile_kind)

			if airlock_cells.has(i):
				_add_room_airlock(cell, gx, gy, airlock_cells[i])

# Wrap-on-wall model (FD-052): the maze hugs the cylinder wall at a near-fixed
# radius. gx wraps the circumference, gy runs ALONG the tube axis (Y). base_height
# gives a small radial relief so it does not read as a flat sheet. Centralised so
# tile placement and the arc mesh (make_duct_arc) stay in sync.
func _ring_radius(_gy: int, _height: float = 0.0) -> float:
	# Wrap-on-wall: every piece sits at the wall. (No per-piece radial relief — that
	# collapsed pieces to the center because base_height is the AXIAL offset, 0..12.)
	return wall_radius

func _grid_to_world(gx: int, gy: int, height: float, piece_name: String = "") -> Transform:
	var angle_deg := float(gx) * (360.0 / sectors)
	var angle_rad := deg2rad(angle_deg)
	var radius := _ring_radius(gy, height)

	var world_x := radius * cos(angle_rad)
	# gy walks the cylinder axis: this is the long direction of the tube.
	var world_y := float(gy) * ring_step * axial_scale
	var world_z := radius * sin(angle_rad)
	var pos := Vector3(world_x, world_y, world_z)

	var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad))
	var radial := Vector3(cos(angle_rad), 0, sin(angle_rad))
	var up := Vector3(0, 1, 0)

	# Arcs connect two sectors at the SAME Y level, hugging the wall along the
	# circumference. DuctArcBuilder authors the arc so that its navigable direction
	# (tangent to the arc) is local +Z and its centre of curvature is at local -X
	# (i.e. local +X points away from the arc centre). To wrap the cylinder wall:
	#   local +Z -> circle tangent   (sweep along the circumference)
	#   local +X -> radial-out       (so -X, the arc centre, points at the axis)
	#   local +Y -> global up (axis)
	# => Basis columns (x=radial, y=up, z=tangent).
	if piece_name.begins_with("DuctArc"):
		return Transform(Basis(radial, up, tangent), pos)

	# Everything else (straight ducts, junctions) connects ALONG the tube: their
	# authored "forward" (local Z) must point along global Y. local Y = radial-out.
	#   x = tangent, y = radial-out, z = axial(global Y)
	return Transform(Basis(tangent, radial, up), pos)

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
	# Same material as the curved ducts (airlock panel shader, cull_back). The earlier
	# cull_disabled variant made the straight tube read as a solid blue glow inside.
	mesh_instance.material_override = _hull_mat()
	root.add_child(mesh_instance)
	
	_add_collision_cylinder(root, ring_step, duct_radius)
	_add_structural_rings(root, Vector3.FORWARD, ring_step, duct_radius)
	_add_floor_grate(root, ring_step, duct_radius)
	
	return root

func make_duct_arc(gx: int, gy: int) -> Spatial:
	var root = Spatial.new()
	root.name = "DuctArc"
	# Arc curvature must match the wall radius so it follows the cylinder circumference.
	var radius := wall_radius
	var arc_deg := 360.0 / sectors
	var arc_rad := deg2rad(arc_deg)
	
	var mesh_instance = MeshInstance.new()
	# The builder now generates arcs aligned with Z axis
	mesh_instance.mesh = DuctArcBuilder.get_or_build_arc(radius, duct_radius, arc_deg, 16)
	mesh_instance.material_override = _hull_mat()
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
	
	# HOLLOW collision: the old segmented BoxShapes filled the curved tube so the player
	# could not enter it (bug). Use a trimesh of the arc wall mesh instead, so only the
	# wall collides and the curve is navigable.
	var body = StaticBody.new()
	root.add_child(body)
	var arc_shape = CollisionShape.new()
	arc_shape.shape = mesh_instance.mesh.create_trimesh_shape()
	body.add_child(arc_shape)
	
	# Structural rings following the arc
	_add_structural_rings_arc(root, radius, arc_deg, 3)
	
	return root

func _add_structural_rings_arc(root: Spatial, R: float, arc_deg: float, count: int) -> void:
	var arc_rad = deg2rad(arc_deg)
	# Torus collar (bug 2): axis = local Z. Along the arc the local tangent at parameter u
	# is (-sin u, 0, cos u); a yaw of -u rotates the collar's Z axis onto that tangent so
	# the band sits square around the curved tube (no flat-plate look).
	var collar = _get_ring_collar_mesh(duct_radius + ring_extra_radius, max(ring_height, 0.18))
	for i in range(count):
		var u = (float(i) / (count - 1) - 0.5) * arc_rad
		var ring = MeshInstance.new()
		ring.mesh = collar
		ring.material_override = _get_res(CONDUIT_MAT_PATH)

		var x = R * cos(u) - R
		var z = R * sin(u)
		ring.translation = Vector3(x, 0, z)
		ring.rotation.y = -u
		root.add_child(ring)

func make_junction(id: String, connections: Array) -> Spatial:
	var root = Spatial.new()
	root.name = "Junction_" + id

	# FD-052 v4: build the junction from intersecting procedural cylinders instead of a
	# spherical hub + look_at()'d arms. The hub sphere + arms-with-look_at() never aligned
	# with the Z=forward convention (AGENTS.md §2.1) and rendered as broken geometry.
	# Connections layout in junction-LOCAL frame (set by _grid_to_world for straight pieces):
	#   +Z / -Z  = FORWARD / BACK     (NORTH / SOUTH, axial along the cylinder tube)
	#   +X / -X  = RIGHT / LEFT       (EAST / WEST,  circumferential around the wall)
	# Each junction is a hub of intersecting HULL_MAT hollow cylinders with CONDUIT_MAT
	# rings at the far ends and FLOOR_MAT grates along their length.
	# Arm parameters per spec:
	#   C-junction N-S: full ring_step through-cylinder along Z (single piece)
	#   all other arms: length ring_step*0.5, offset ring_step*0.25 along the arm direction
	match id:
		"C":
			# Corner: N-S through cylinder + one (or two) lateral stubs.
			if connections[0] or connections[2]:
				_make_junction_through(root, ring_step)
			if connections[1]:
				_make_junction_arm(root, Vector3.RIGHT, ring_step * 0.5, ring_step * 0.25)
			if connections[3]:
				_make_junction_arm(root, Vector3.LEFT, ring_step * 0.5, ring_step * 0.25)
		"T", "X":
			# T = 3 independent arms; X = 4 independent arms.
			if connections[0]:
				_make_junction_arm(root, Vector3.FORWARD, ring_step * 0.5, ring_step * 0.25)
			if connections[2]:
				_make_junction_arm(root, Vector3.BACK, ring_step * 0.5, ring_step * 0.25)
			if connections[1]:
				_make_junction_arm(root, Vector3.RIGHT, ring_step * 0.5, ring_step * 0.25)
			if connections[3]:
				_make_junction_arm(root, Vector3.LEFT, ring_step * 0.5, ring_step * 0.25)

	# Central hub collision: HOLLOW (trimesh of a sphere shell) so the player can pass
	# through the centre of the junction. A solid SphereShape sealed the hub; a trimesh
	# of the shell mesh makes only the shell surface collide, leaving the interior open.
	# Matches the existing _add_collision_sphere pattern.
	var hub_body = StaticBody.new()
	root.add_child(hub_body)
	var hub_col = CollisionShape.new()
	hub_col.shape = _get_sphere_mesh(duct_radius * 1.25).create_trimesh_shape()
	hub_body.add_child(hub_col)

	return root

# N-S through-cylinder for C-junction: full ring_step along local Z, centered on the
# junction origin. Rings at BOTH ends (per spec, "anillos en los extremos"); a single
# floor strip runs along the cylinder length. HOLLOW trimesh collision so the player
# can walk through the bore.
func _make_junction_through(root: Spatial, length: float) -> void:
	var cyl = MeshInstance.new()
	var cyl_mesh := _get_hollow_cylinder(length, duct_radius, duct_wall_thickness)
	cyl.mesh = cyl_mesh
	cyl.material_override = _hull_mat()
	root.add_child(cyl)

	_add_floor_grate(root, length, duct_radius)

	var body = StaticBody.new()
	root.add_child(body)
	var shape = CollisionShape.new()
	shape.shape = cyl_mesh.create_trimesh_shape()
	body.add_child(shape)

	var collar = _get_ring_collar_mesh(duct_radius + ring_extra_radius, max(ring_height, 0.18))
	for z in [-length * 0.5, length * 0.5]:
		var ring = MeshInstance.new()
		ring.mesh = collar
		ring.material_override = _get_res(CONDUIT_MAT_PATH)
		ring.translation = Vector3(0, 0, z)
		root.add_child(ring)

# Single junction arm as a child of `root`. `dir` is the arm direction in junction-LOCAL
# space (FORWARD, BACK, RIGHT, LEFT). The hollow-cylinder mesh runs along arm-local +Z,
# so the arm's basis is built by hand to rotate arm-local +Z onto `dir` (look_at() in a
# not-yet-parented node ignores the parent's rotation and was the source of the wrong
# orientation bug). The arm spans `offset` to `offset+length` along `dir` in junction-local
# coordinates. Floor grate, far-end ring, and cylinder collision are added as children of
# the arm Spatial so they inherit its rotation automatically.
func _make_junction_arm(root: Spatial, dir: Vector3, length: float, offset: float) -> void:
	var arm = Spatial.new()

	var cyl = MeshInstance.new()
	cyl.mesh = _get_hollow_cylinder(length, duct_radius, duct_wall_thickness)
	cyl.material_override = _hull_mat()
	arm.add_child(cyl)

	# Orient arm so local +Z = dir. Build basis by hand from cross products.
	var fwd := dir.normalized()
	var up_ref := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := up_ref.cross(fwd).normalized()
	var up := fwd.cross(right).normalized()
	arm.transform.basis = Basis(right, up, fwd)
	# Mesh is centred on its origin, so its centre sits at offset + length*0.5 along dir.
	arm.translation = fwd * (offset + length * 0.5)

	# Floor grate (lies flat along arm direction; child of arm so inherits the rotation).
	_add_floor_grate(arm, length, duct_radius)

	# Structural ring at the FAR end of the arm (CONDUIT_MAT). Cylinder centred on the
	# arm origin, far mouth at arm-local +Z = +length*0.5.
	var collar = _get_ring_collar_mesh(duct_radius + ring_extra_radius, max(ring_height, 0.18))
	var ring = MeshInstance.new()
	ring.mesh = collar
	ring.material_override = _get_res(CONDUIT_MAT_PATH)
	ring.translation = Vector3(0, 0, length * 0.5)
	arm.add_child(ring)

	# HOLLOW collision: solid CylinderShape / SphereShape fill the tube and seal the hub
	# ("no se puede atravesar el medio del cilindro"). Use trimesh of the same wall mesh
	# so only the WALL collides and the interior is navigable — matches make_duct_radial
	# / _add_collision_cylinder. The shape is a child of the arm Spatial so it inherits
	# the arm's rotation automatically.
	var col_body = StaticBody.new()
	arm.add_child(col_body)
	var col_shape = CollisionShape.new()
	col_shape.shape = cyl.mesh.create_trimesh_shape()
	col_body.add_child(col_shape)

	root.add_child(arm)

# A junction arm that follows the cylinder wall circumferentially (EAST/WEST).
# `dir_sign` = +1 toward increasing gx (junction local +X), -1 toward decreasing gx.
# The arc curves around the global axis at wall_radius and spans HALF a sector so it meets
# the neighbour junction/arc coming the other way. Built in the arm's own local frame and
# then rotated into the junction frame so:
#   arc travel  (builder +Z) -> junction +X * dir_sign  (circumferential)
#   arc out     (builder +X) -> junction +Y             (radial-out; curvature centre is
#                                                         the cylinder axis, at -Y)
func make_arc_arm(dir_sign: int, radius: float) -> Spatial:
	var arm = Spatial.new()
	arm.name = "ArcArm"
	var R := _ring_radius(0)
	var half_arc_deg := (360.0 / sectors) * 0.5

	# Inset the near end off the hub centre by the same hub_reach as the axial arms, so
	# the arc tube starts at the rim instead of filling the central ball (clipping fix).
	var start_deg := rad2deg(junction_hub_reach / max(R, 0.001))
	var mesh = MeshInstance.new()
	mesh.mesh = _build_arc_arm_mesh(R, radius, half_arc_deg, 8, start_deg)
	mesh.material_override = _hull_mat()
	arm.add_child(mesh)

	# Map builder axes (X=out, Y=up, Z=travel) into the junction frame. For EAST
	# (dir_sign=+1): col_x=image(X)=+Y_j, col_y=image(Y)=+Z_j, col_z=image(Z)=+X_j — a
	# proper rotation (cyclic permutation). WEST mirrors the travel axis (col_z) and flips
	# col_y so the basis stays right-handed (no inverted winding).
	if dir_sign >= 0:
		arm.transform.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	else:
		arm.transform.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))

	# Hollow trimesh collision from the same wall mesh (walls collide, interior navigable).
	var body = StaticBody.new()
	arm.add_child(body)
	var shape = CollisionShape.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(shape)
	return arm

# Like DuctArcBuilder._build_arc but sweeping u in [0, arc_deg] (one-directional) so the
# NEAR end sits exactly at the local origin (the junction hub) and the tube travels toward
# +Z, curving toward -X (the cylinder axis). Centre of section at u: (R*cos u - R,0,R*sin u).
func _build_arc_arm_mesh(R: float, r: float, arc_deg: float, arc_segs: int, start_deg: float = 0.0) -> ArrayMesh:
	var key = "arcarm_%f_%f_%f_%d_%f" % [R, r, arc_deg, arc_segs, start_deg]
	if _mesh_cache.has(key): return _mesh_cache[key]

	var section_segs := 16
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var uvs = PoolVector2Array()
	var idx = PoolIntArray()
	var arc_rad := deg2rad(arc_deg)
	var start_rad := deg2rad(start_deg)

	for i in range(arc_segs + 1):
		# Sweep from start_rad (hub rim) to arc_rad (toward the neighbour). The section
		# centre at u is still (R*cos u - R, 0, R*sin u), so trimming the start simply
		# moves the near mouth off the junction centre by the inset arc length.
		var u = start_rad + (float(i) / arc_segs) * (arc_rad - start_rad)
		var cos_u = cos(u); var sin_u = sin(u)
		var center = Vector3(R * cos_u - R, 0, R * sin_u)
		for j in range(section_segs + 1):
			var v = (float(j) / section_segs) * TAU
			var cv = cos(v); var sv = sin(v)
			var x = r * cv
			var z = (R + x) * sin_u
			x = (R + x) * cos_u - R
			var y = r * sv
			var p = Vector3(x, y, z)
			verts.push_back(p)
			norms.push_back((p - center).normalized())
			uvs.push_back(Vector2(float(i) / arc_segs, float(j) / section_segs))

	for i in range(arc_segs):
		for j in range(section_segs):
			var i0 = i * (section_segs + 1) + j
			var i1 = i0 + 1
			var i2 = (i + 1) * (section_segs + 1) + j
			var i3 = i2 + 1
			idx.push_back(i0); idx.push_back(i1); idx.push_back(i2)
			idx.push_back(i1); idx.push_back(i3); idx.push_back(i2)

	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = mesh
	return mesh

func make_arm(dir: Vector3, length: float, radius: float, start_offset: float = 0.0) -> Spatial:
	var arm = Spatial.new()
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(length, radius, duct_wall_thickness)
	mesh.material_override = _hull_mat()
	arm.add_child(mesh)

	# The tube mesh runs along LOCAL Z. Orient the arm so local +Z points at `dir`,
	# building the basis by hand. (look_at() here was wrong: it runs in GLOBAL space on a
	# node not yet in the tree, so it ignored the junction's own rotation and arms that
	# should open sideways ended up axial — bug "Junction T no abre al costado".)
	var fwd := dir.normalized()
	var up_ref := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := up_ref.cross(fwd).normalized()
	var up := fwd.cross(right).normalized()
	arm.transform.basis = Basis(right, up, fwd)
	# Near end sits at `start_offset` from the origin, far end at start_offset+length.
	# The mesh is centred, so the centre is at start_offset + length*0.5.
	arm.translation = dir * (start_offset + length * 0.5)

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
	mesh_instance.material_override = _hull_mat()
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

	# Rings must inherit the duct's slope too — otherwise the decorative collars stay
	# perpendicular to world Y while the cylinder tilts, reading as "rings no incline".
	# Same X rotation + same Y offset as the mesh and the collision body.
	var rings_root = Spatial.new()
	rings_root.rotation.x = angle
	rings_root.translation.y = h1 * 0.5
	root.add_child(rings_root)
	_add_structural_rings(rings_root, Vector3.FORWARD, length, duct_radius)
	return root

func make_endcap() -> Spatial:
	var root = Spatial.new()
	root.name = "DuctEndCap"
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(1.0, duct_radius, duct_wall_thickness)
	mesh.material_override = _hull_mat()
	root.add_child(mesh)
	
	# Open torus collar at the mouth instead of a solid disc plate. The flat CylinderMesh
	# cap read as a "circular plate covering the section" (bug); a collar frames the
	# opening like the curved-duct rings and keeps the tube passable.
	var collar = MeshInstance.new()
	collar.mesh = _get_ring_collar_mesh(duct_radius + ring_extra_radius, max(ring_height, 0.18))
	collar.material_override = _get_res(CONDUIT_MAT_PATH)
	collar.translation = Vector3(0, 0, 0.5)
	root.add_child(collar)

	_add_collision_cylinder(root, 1.0, duct_radius)
	return root

func make_capsule(connections: Array, gy: int) -> Spatial:
	var root = Spatial.new()
	root.name = "CapsuleRoom"
	
	# Room must be wider than the ducts that meet it, otherwise the player hits its closed
	# wall coming down a fatter tube. Size it above duct_radius so it reads as a chamber.
	var room_radius = duct_radius * 1.6
	var room_height = duct_radius * 2.2
	var mesh_instance = MeshInstance.new()
	mesh_instance.mesh = _get_capsule_mesh(room_radius, room_height)
	mesh_instance.material_override = _hull_mat()
	root.add_child(mesh_instance)

	_add_collision_capsule(root, room_height, room_radius)
	
	# Ports: short connector tubes punching out of the room wall toward each neighbour, so
	# the room actually opens into the ducts that meet it (not a sealed blob).
	var port_len = room_radius
	var dirs = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in range(4):
		if connections[i]:
			var arm = make_arm(dirs[i], port_len, duct_radius)
			# make_arm centres the tube at dir*len*0.5; push it out so it bridges the wall.
			arm.translation = dirs[i] * room_radius
			root.add_child(arm)
			
	# No dynamic OmniLight per tile: GLES2 forward does not scale with omni lights.
	# Illumination comes from emissive materials (DuctLightStrip.tres) + scene DirectionalLight.

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
	
	# Per-vertex normals: each corner gets the radial normal at its OWN angle (not the
	# segment-start angle), so shading is smooth and the outer face is correctly lit
	# instead of reading as black (bug 1). Inner normals point in (toward axis), outer
	# normals point out. Winding is set so each face's front matches its normal.
	for i in range(segments):
		var a0 = TAU * i / segments
		var a1 = TAU * (i + 1) / segments
		var c0 = cos(a0); var s0 = sin(a0)
		var c1 = cos(a1); var s1 = sin(a1)

		var ni0 = Vector3(-c0, -s0, 0)  # inner normal at a0 (toward axis)
		var ni1 = Vector3(-c1, -s1, 0)  # inner normal at a1
		var no0 = Vector3(c0, s0, 0)    # outer normal at a0 (away from axis)
		var no1 = Vector3(c1, s1, 0)    # outer normal at a1

		# UVs: U = around the circumference, V = along the length. Without UVs the airlock
		# panel shader read everything as a seam -> solid emissive blue (bug). U is scaled
		# by the circumference and V by the length so panels stay roughly square.
		var u0 = float(i) / segments * (TAU * radius) / 4.0
		var u1 = float(i + 1) / segments * (TAU * radius) / 4.0
		var vlo = 0.0
		var vhi = length / 4.0
		var uv_p0 = Vector2(u0, vlo); var uv_p1 = Vector2(u1, vlo)
		var uv_p2 = Vector2(u0, vhi); var uv_p3 = Vector2(u1, vhi)

		# Inner
		var p0 = Vector3(radius * c0, radius * s0, -half_l)
		var p1 = Vector3(radius * c1, radius * s1, -half_l)
		var p2 = Vector3(radius * c0, radius * s0, half_l)
		var p3 = Vector3(radius * c1, radius * s1, half_l)

		st.add_normal(ni0); st.add_uv(uv_p0); st.add_vertex(p0)
		st.add_normal(ni1); st.add_uv(uv_p1); st.add_vertex(p1)
		st.add_normal(ni0); st.add_uv(uv_p2); st.add_vertex(p2)
		st.add_normal(ni1); st.add_uv(uv_p1); st.add_vertex(p1)
		st.add_normal(ni1); st.add_uv(uv_p3); st.add_vertex(p3)
		st.add_normal(ni0); st.add_uv(uv_p2); st.add_vertex(p2)

		# Outer
		var orad = radius + thickness
		var op0 = Vector3(orad * c0, orad * s0, -half_l)
		var op1 = Vector3(orad * c1, orad * s1, -half_l)
		var op2 = Vector3(orad * c0, orad * s0, half_l)
		var op3 = Vector3(orad * c1, orad * s1, half_l)

		# Outer face: winding reversed vs the inner face so the front side faces OUTWARD
		# (matching the outward normal). The previous order culled the outer face, so the
		# tube was visible only from inside (bug 1, recurring).
		st.add_normal(no0); st.add_uv(uv_p0); st.add_vertex(op0)
		st.add_normal(no1); st.add_uv(uv_p1); st.add_vertex(op1)
		st.add_normal(no0); st.add_uv(uv_p2); st.add_vertex(op2)
		st.add_normal(no1); st.add_uv(uv_p1); st.add_vertex(op1)
		st.add_normal(no1); st.add_uv(uv_p3); st.add_vertex(op3)
		st.add_normal(no0); st.add_uv(uv_p2); st.add_vertex(op2)

	var mesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

# Torus collar that wraps AROUND the tube as a raised band (bug 2: the old rings used a
# thin solid CylinderMesh disc -> read as a flat plate seen edge-on). The torus axis is
# local Z, so it sits in the local XY plane and hugs a tube whose run direction is Z.
func _get_ring_collar_mesh(major_radius: float, minor_radius: float) -> ArrayMesh:
	var key = "collar_%f_%f" % [major_radius, minor_radius]
	if _mesh_cache.has(key): return _mesh_cache[key]

	var ring_segs = 20   # around the tube circumference
	var tube_segs = 8    # around the collar's own thickness
	var verts = PoolVector3Array()
	var norms = PoolVector3Array()
	var idx = PoolIntArray()

	for i in range(ring_segs + 1):
		var u = TAU * i / ring_segs
		var cu = cos(u); var su = sin(u)
		# Ring runs in local XY plane (axis = local Z). Centre of each section:
		var center = Vector3(major_radius * cu, major_radius * su, 0)
		for j in range(tube_segs + 1):
			var v = TAU * j / tube_segs
			var cv = cos(v); var sv = sin(v)
			# Section circle lives in the (radial, Z) plane of the ring.
			var radial = Vector3(cu, su, 0)
			var n = radial * cv + Vector3(0, 0, sv)
			verts.push_back(center + n * minor_radius)
			norms.push_back(n)

	for i in range(ring_segs):
		for j in range(tube_segs):
			var a = i * (tube_segs + 1) + j
			var b = a + 1
			var c = (i + 1) * (tube_segs + 1) + j
			var d = c + 1
			idx.push_back(a); idx.push_back(c); idx.push_back(b)
			idx.push_back(b); idx.push_back(c); idx.push_back(d)

	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
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
	# HOLLOW collision: a solid CylinderShape filled the tube so the player could not
	# enter. Build a concave (trimesh) shape from the hollow-cylinder wall mesh, so only
	# the wall collides and the interior is navigable (zero-g maze).
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var mesh: ArrayMesh = _get_hollow_cylinder(length, radius, duct_wall_thickness)
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_collision_sphere(root: Node, radius: float) -> StaticBody:
	# HOLLOW collision (see _add_collision_cylinder): a solid SphereShape sealed the
	# junction hub. Use the sphere shell mesh as a trimesh so the player can pass through.
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var mesh: ArrayMesh = _get_sphere_mesh(radius)
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_collision_capsule(root: Node, height: float, radius: float) -> StaticBody:
	# HOLLOW collision: a solid CapsuleShape made the room an impassable blob ("cápsula
	# rara que no deja pasar"). Use a trimesh of the capsule shell so the player can be
	# INSIDE the room; the wall collides, the interior is open.
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	shape.shape = _get_capsule_mesh(radius, height).create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)
	return body

func _add_structural_rings(root: Node, axis: Vector3, length: float, radius: float, count: int = 2) -> void:
	# Torus collars wrapping the tube. The tube runs along local Z, and the collar mesh's
	# axis is local Z too, so the band hugs the tube cross-section with no rotation.
	var collar = _get_ring_collar_mesh(radius + ring_extra_radius, max(ring_height, 0.18))
	for i in range(count):
		var ring = MeshInstance.new()
		ring.mesh = collar
		ring.material_override = _get_res(CONDUIT_MAT_PATH)

		var t = -length * 0.5 + (length / (count + 1)) * (i + 1)
		ring.translation = axis * t
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

	# Zone is conveyed via emissive tint instead of a dynamic OmniLight (GLES2 cost).
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

# Pick which cells get an airlock coupled to them, and on WHICH connection.
# Returns { cell_index : connection_index } where the connection is a TANGENTIAL one
# (EAST=1 or WEST=3) so the chamber's door through-axis ends up HORIZONTAL and the
# player can actually interact with it (axial N/S connections run along global Y =
# the player's up, which would stack the doors vertically and break interaction).
#
# Targets, in priority order: rooms (is_room) and the dead-end endpoints (degree 1),
# because an airlock reads as the entrance/exit of a chamber or the cap of a spur.
# We only take cells that expose a tangential connection, and cap the count so the
# maze is not wall-to-wall airlocks.
func _select_airlock_cells(grid: Array) -> Dictionary:
	var out := {}
	var max_airlocks := 3

	# Rooms (is_room) that BOTH expose a tangential (interactable) mouth AND render a tile
	# with an actual tangential tube to butt against. Capsule rooms (id C/T/X) and
	# tangential straight/arc duct-rooms (id W) qualify; an endcap (id E) is rendered as an
	# AXIAL stub regardless of its MST connection, so an airlock on its tangential side
	# would float disconnected — exclude it. Axial-only rooms are dropped by
	# _tangential_conn (doors there would stack along the player's up = uninteractable).
	for i in range(grid.size()):
		if out.size() >= max_airlocks:
			break
		var cell = grid[i]
		if cell == null: continue
		if not cell.get("is_room", false):
			continue
		var id = cell.variant.id
		if not (id in ["C", "T", "X", "W"]):
			continue
		var conn_dir = _tangential_conn(cell.variant.connections)
		if conn_dir == -1:
			continue
		out[i] = conn_dir

	return out

# Returns EAST (1) if present, else WEST (3), else -1. Both are tangential connections
# whose airlock door through-axis is HORIZONTAL (interactable). Axial N/S returns -1.
func _tangential_conn(conn: Array) -> int:
	if conn[1]:
		return 1
	if conn[3]:
		return 3
	return -1

# Couple an AirlockChamber to a room/endpoint cell at the mouth of a tangential
# connection, oriented so the through-axis (and thus the doors) is horizontal.
func _add_room_airlock(cell: Dictionary, gx: int, gy: int, conn_dir: int) -> void:
	var airlock_scene = _get_res(AIRLOCK_CHAMBER_PATH)
	if not airlock_scene: return

	var airlock = airlock_scene.instance()
	airlock.name = "RoomAirlock"
	# No scene transition in the maze: let the airlock complete its cycle locally
	# (open the exit door after pressurizing) instead of hanging on "PRESURIZANDO".
	if "standalone_cycle" in airlock:
		airlock.standalone_cycle = true
	add_child(airlock)

	var angle_rad := deg2rad(float(gx) * (360.0 / sectors))
	var radius := _ring_radius(gy, cell.base_height)
	var cell_pos := Vector3(radius * cos(angle_rad), float(gy) * ring_step * axial_scale, radius * sin(angle_rad))
	var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad)) # horizontal, along the wall
	var up := Vector3(0, 1, 0)

	# Through-axis points along the chosen connection: EAST=+tangent, WEST=-tangent.
	var through := tangent if conn_dir == 1 else -tangent

	# Butt the chamber's INNER door (local -Z, ~chamber_inner_half from the chamber centre)
	# against the room's tangential tube mouth, so the airlock reads as coupled to the room
	# instead of floating in the bore.
	#   capsule rooms (C/T/X): the port tube reaches ~2*room_radius from the cell centre.
	#   tangential duct-rooms (W): the arc/straight tube reaches ~one duct radius past the bore.
	var id = cell.variant.id
	var room_radius := duct_radius * 1.6
	var tube_reach := (room_radius * 2.0) if (id in ["C", "T", "X"]) else (duct_radius + 1.0)
	var chamber_inner_half := 4.1
	var mouth_reach := tube_reach + chamber_inner_half
	var pos := cell_pos + through * mouth_reach

	# Build a globally-upright basis with local Z = through (door through-axis horizontal,
	# local Y = global up). Doors then face horizontally so the player's forward interact
	# box can reach the door Frame (see history of the loose-airlock interaction fix).
	var side := up.cross(through).normalized()
	airlock.transform = Transform(Basis(side, up, through), pos)
	# NOTE: AirlockChamber.tscn already contains its own IrisDoorV2 wired to an
	# AirlockControllerV2 that actually opens it. We must NOT add a second loose iris
	# here — that duplicate had no controller, so it never opened and overlapped the
	# real door (bug: "airlocks/iris don't open").

func _grado(conn: Array) -> int:
	var count = 0
	for c in conn:
		if c: count += 1
	return count
