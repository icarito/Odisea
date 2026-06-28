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
export var wall_radius := 28.0   # duct centreline radius inside the Core shell

export var room_count := 4
export var extra_cycles := 2
export var seed_value := -1
export var streaming_enabled := false
export var stream_chunk_rings := 24
export var stream_active_chunks_each_side := 1
export var stream_update_interval := 0.25
export var collapse_enabled := false
export var generated_airlocks_enabled := false

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
const FORWARD_INTERACT_SCRIPT = preload("res://core_v2/components/ForwardInteract.gd")

var _resource_cache := {}
var _mesh_cache := {}
var _active_chunks := {}
var _stream_timer := 0.0

func _ready():
	generate()

func _process(delta: float) -> void:
	if not streaming_enabled:
		return
	_stream_timer -= delta
	if _stream_timer > 0.0:
		return
	_stream_timer = stream_update_interval
	_refresh_stream_chunks(false)

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

func generate() -> void:
	for child in get_children():
		child.queue_free()
	_active_chunks.clear()

	if streaming_enabled:
		_refresh_stream_chunks(true)
		return

	_build_chunk_contents(self, 0, rings)

func _refresh_stream_chunks(force: bool) -> void:
	var current_chunk := _current_stream_chunk()
	var wanted := {}
	for chunk_idx in range(current_chunk - stream_active_chunks_each_side, current_chunk + stream_active_chunks_each_side + 1):
		wanted[chunk_idx] = true
		if force or not _active_chunks.has(chunk_idx) or not is_instance_valid(_active_chunks[chunk_idx]):
			_create_stream_chunk(chunk_idx)

	for chunk_idx in _active_chunks.keys():
		if wanted.has(chunk_idx):
			continue
		var chunk = _active_chunks[chunk_idx]
		if is_instance_valid(chunk):
			chunk.queue_free()
		_active_chunks.erase(chunk_idx)

func _current_stream_chunk() -> int:
	var player = _get_stream_target()
	if not is_instance_valid(player):
		return 0
	var local_pos: Vector3 = global_transform.affine_inverse().xform(player.global_transform.origin)
	return int(floor(local_pos.y / _stream_chunk_length()))

func _stream_chunk_length() -> float:
	return float(max(stream_chunk_rings, 1)) * ring_step

func _get_stream_target() -> Spatial:
	var session = get_node_or_null("/root/SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		return session.player as Spatial
	var pilot = get_tree().get_root().find_node("Pilot", true, false)
	if pilot is Spatial:
		return pilot
	return null

func _create_stream_chunk(chunk_idx: int) -> void:
	var chunk = Spatial.new()
	chunk.name = "DuctChunk_%d" % chunk_idx
	chunk.translation.y = float(chunk_idx) * _stream_chunk_length()
	chunk.set_meta("duct_chunk_index", chunk_idx)
	add_child(chunk)
	_active_chunks[chunk_idx] = chunk
	_build_chunk_contents(chunk, chunk_idx, max(stream_chunk_rings, 1))

func _build_chunk_contents(parent: Spatial, chunk_idx: int, chunk_rings: int) -> void:
	var mst_gen = ScaffoldMSTGenerator.new()
	var fixed_tiles := _get_fixed_border_tiles(chunk_idx, chunk_rings)
	var params = {
		"grid_width": sectors,
		"grid_depth": chunk_rings,
		"mst_max_height_steps": height_steps,
		"room_count": room_count,
		"extra_cycles": extra_cycles,
		"wrap_x": true,
		"fixed_border_tiles": fixed_tiles
	}
	mst_gen.apply_params(params)
	var grid = mst_gen.generate_grid_data(_chunk_seed(chunk_idx))
	
	# Airlocks are no longer dropped loose on the furthest cell. Instead they couple to
	# ROOMS at the mouth of an interactable (tangential E/W) connection — see
	# _select_airlock_cells / _add_room_airlock. This gives them spatial meaning
	# (entrance/exit of a chamber) instead of floating at an arbitrary endpoint.
	var airlock_cells := _select_airlock_cells(grid) if generated_airlocks_enabled else {}

	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null: continue

		var gx := i % sectors
		var gy := i / sectors
		var v = cell.variant

		var tile = instantiate_tile(gx, gy, cell)
		if tile:
			var tile_kind := String(tile.name)
			parent.add_child(tile)
			tile.transform = _grid_to_world(gx, gy, cell.base_height, tile_kind)

			if airlock_cells.has(i):
				_add_room_airlock(cell, gx, gy, airlock_cells[i], parent)

func _stable_hash(a: int, b: int, c: int = 0) -> int:
	var h = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	if seed_value >= 0:
		h ^= seed_value * 12345
	return int(h) & 0x7fffffff

func _get_fixed_border_tiles(chunk_idx: int, chunk_rings: int) -> Dictionary:
	var fixed := {}
	# NORTH boundary of chunk N (gy=0) meets SOUTH of chunk N-1.
	# Hashing chunk_idx ensures both agree on this seam.
	# Boundary tiles are forced to be axial straight ducts ("W", rot 0) to ensure
	# seamless connections without junction/arc mismatch.
	var north_gx = _stable_hash(chunk_idx, 101) % sectors
	fixed["%d,0" % north_gx] = {"height": 0.0, "id": "W", "rotation": 0}

	# SOUTH boundary of chunk N (gy=chunk_rings-1) meets NORTH of chunk N+1.
	# Hashing chunk_idx + 1 ensures both agree.
	var south_gx = _stable_hash(chunk_idx + 1, 101) % sectors
	fixed["%d,%d" % [south_gx, chunk_rings - 1]] = {"height": 0.0, "id": "W", "rotation": 0}

	return fixed

func _chunk_seed(chunk_idx: int) -> int:
	var base_seed := seed_value if seed_value >= 0 else 0
	return int(base_seed + chunk_idx * 73856093)

func _grid_to_world(gx: int, gy: int, height: float, piece_name: String = "") -> Transform:
	var angle_deg := float(gx) * (360.0 / sectors)
	var angle_rad := deg2rad(angle_deg)
	var radius := wall_radius
	var world_x := radius * cos(angle_rad)
	var world_y := _axis_y(gy)
	var world_z := radius * sin(angle_rad)
	var pos := Vector3(world_x, world_y, world_z)
	var tangent := Vector3(-sin(angle_rad), 0, cos(angle_rad))
	var up := Vector3.UP
	var radial := Vector3(cos(angle_rad), 0, sin(angle_rad))
	if piece_name.begins_with("DuctArc"):
		return Transform(Basis(radial, up, tangent), pos)
	return Transform(Basis(tangent, radial, up), pos)

func _axis_y(gy: int) -> float:
	return float(gy) * ring_step

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
				tile = make_endcap(_single_connection_dir(v.connections))
	
	if tile:
		tile.set_meta("gx", gx)
		tile.set_meta("gy", gy)
		_add_content_overlay(tile, gy)
		_apply_duct_properties(tile)
		if collapse_enabled:
			_add_collapse_trigger(tile)
	
	return tile

func _single_connection_dir(connections: Array) -> Vector3:
	var dirs = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in range(min(connections.size(), 4)):
		if connections[i]:
			return dirs[i]
	return Vector3.FORWARD

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
	
	var body = StaticBody.new()
	root.add_child(body)
	var segments_c := 8
	var segment_len := (radius * arc_rad) / segments_c
	var wall := max(duct_wall_thickness, 0.2)
	for i in range(segments_c):
		var u_col = (float(i + 0.5) / segments_c - 0.5) * arc_rad
		var segment_basis := Basis(Vector3.UP, -u_col)
		var center := Vector3(radius * cos(u_col) - radius, 0, radius * sin(u_col))
		var half_segment := segment_len * 0.49
		var wall_specs = [
			[Vector3(0, duct_radius + wall * 0.5, 0), Vector3(duct_radius, wall * 0.5, half_segment)],
			[Vector3(0, -duct_radius - wall * 0.5, 0), Vector3(duct_radius, wall * 0.5, half_segment)],
			[Vector3(duct_radius + wall * 0.5, 0, 0), Vector3(wall * 0.5, duct_radius + wall, half_segment)],
			[Vector3(-duct_radius - wall * 0.5, 0, 0), Vector3(wall * 0.5, duct_radius + wall, half_segment)]
		]
		for spec in wall_specs:
			var shape = CollisionShape.new()
			var box = BoxShape.new()
			box.extents = spec[1]
			shape.shape = box
			shape.translation = center + segment_basis.xform(spec[0])
			shape.rotation.y = -u_col
			body.add_child(shape)
	
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

	var dirs = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]

	# Collect the directions this junction actually connects, so the hub shell is pierced
	# with an open mouth toward each arm. The old solid SphereMesh (radius ~= the bore)
	# sealed every crossing: from inside a duct the hub read as a wall and a T had no gap
	# to walk through.
	var hole_dirs := []
	for i in range(4):
		if connections[i]:
			hole_dirs.append(dirs[i])

	# Hub sized so the carved mouths stay BELOW 45deg half-angle: then four mouths (90deg
	# apart on an X) don't overlap, and each hole rim sits well out from the equator so the
	# arms seat into it without a gap AND without reaching so far in that they cross. At
	# ratio 1.6: mouth ~39deg, footprint ~4.3m < the 5.1m half-sector (no sphere-to-sphere
	# overlap now that duct_radius=2.7). This headroom is exactly what the thinner bore bought.
	var hub_radius := duct_radius * 1.6
	# Mouth half-angle = asin(bore/hub_radius): the carved hole is then EXACTLY bore-sized
	# (its rim radius == duct_radius). No extra fudge — the old +4deg widened the hole past
	# the tube so a thin ring gap opened between the cut sphere and the arm.
	var mouth_half_angle := asin(clamp(duct_radius / hub_radius, 0.0, 0.999))
	# Where the hole rim sits along the arm axis: the arm must start at (or just inside) this
	# z so its tube wall meets the cut sphere edge with no gap (the "gap entre la esfera
	# cortada y los ductos" bug). cos(mouth) shrinks fast as the hole grows, so for a tight
	# hub this is near the equator — the arm has to reach well back into the hub.
	var mouth_rim_z := hub_radius * cos(mouth_half_angle)

	var hub = MeshInstance.new()
	hub.name = "JunctionHub"
	hub.mesh = _get_pierced_sphere_mesh(hub_radius, duct_wall_thickness, hole_dirs, mouth_half_angle)
	hub.material_override = _hull_mat()
	root.add_child(hub)

	# Collision for the hub: a TRIMESH of the pierced shell itself (exact, hollow, with the
	# mouths open) instead of a box approximation. Box floor/walls left the player clipping
	# the curved sphere where the square collider and the round mesh disagreed; the trimesh
	# matches the visual wall exactly so you can't pass through it (FD-052 hollow-collision
	# lesson: tubes/arcs/spheres need create_trimesh_shape, not primitive shapes).
	var hub_body = StaticBody.new()
	hub_body.name = "HubCollision"
	var hub_col = CollisionShape.new()
	hub_col.shape = hub.mesh.create_trimesh_shape()
	hub_body.add_child(hub_col)
	root.add_child(hub_body)

	# Arms bridge from the HUB SURFACE to the cell boundary. AXIAL arms (FORWARD/BACK ==
	# ±local Z) are straight; TANGENTIAL arms (RIGHT/LEFT == ±local X) CURVE around the
	# cylinder (a straight tangential arm shoots as a chord across the hub and falls short of
	# the neighbour ~10m away on the arc). dirs order: [FWD,RIGHT,BACK,LEFT].
	#
	# Each arm starts at the MOUTH RIM (mouth_rim_z), pulled in by a small overlap so the tube
	# wall seats into the cut sphere edge with no gap. This is keyed to the hole geometry, so
	# it stays sealed for elbow/T/X alike. The hollow hub interior is the crossing volume, so
	# even when the rim is near the equator (4-way X) the arms don't cross — they plug their
	# own mouth and stop.
	var rim_overlap := duct_wall_thickness
	var hub_clearance := max(mouth_rim_z - rim_overlap, 0.0)
	# Axial arms slightly overshoot the cell half so the seam with the neighbour closes (no
	# gap between sections); the small overlap is hidden by the collars.
	var axial_len := max(ring_step * 0.5 - hub_clearance + duct_wall_thickness, duct_radius * 0.5)
	# Tangential arc: start at the mouth-rim angle so the curved tube seats into the hole, span
	# to the mid-sector boundary so it reaches the neighbour's arc tile.
	var sector_half_deg := (360.0 / sectors) * 0.5
	var arc_start_deg := rad2deg(hub_clearance / wall_radius)
	var arc_span_deg := max(sector_half_deg - arc_start_deg, sector_half_deg * 0.4)
	for i in range(4):
		if not connections[i]:
			continue
		if i == 0 or i == 2:
			# Axial (straight).
			var arm = make_arm(dirs[i], axial_len, duct_radius, hub_clearance)
			root.add_child(arm)
		else:
			# Tangential (curved): RIGHT(i=1)=+X=east(+1), LEFT(i=3)=-X=west(-1).
			var arc_sign := 1.0 if i == 1 else -1.0
			var arc_arm = make_arc_arm(arc_sign, arc_span_deg, arc_start_deg, duct_radius)
			root.add_child(arc_arm)

	return root

func make_arm(dir: Vector3, length: float, radius: float, start_offset: float = 0.0) -> Spatial:
	var arm = Spatial.new()
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(length, radius, duct_wall_thickness)
	mesh.material_override = _hull_mat()
	arm.add_child(mesh)

	_add_hollow_box_collision(arm, length, radius)

	_add_structural_rings(arm, Vector3.FORWARD, length, radius)
	_add_arm_end_collar(arm, -length * 0.5, radius)
	_add_arm_end_collar(arm, length * 0.5, radius)

	var fwd := dir.normalized()
	var up_ref := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := up_ref.cross(fwd).normalized()
	var local_up := fwd.cross(right).normalized()
	arm.transform.basis = Basis(right, local_up, fwd)
	arm.translation = dir * (start_offset + length * 0.5)
	return arm

# A junction's tangential (E/W) connection follows the cylinder circumference, so a straight
# arm is wrong: it shoots as a chord across the hub (the "tubos cruzan el hub" / "lados muy
# juntos" bug) and falls short of the neighbour ~10m away around the arc. This builds a
# CURVED arm in the junction's local frame: X=tangent, Y=radial(outward), Z=axial. The arc
# bends in the local XY plane around centre (0,-R,0) (R = wall_radius, the cylinder axis is
# at -radial), starting at the hub rim and spanning `span_deg` toward the neighbour mouth.
# `sign` = +1 for EAST (+X), -1 for WEST (-X). Returns a Spatial already in local coords.
func make_arc_arm(dir_sign: float, span_deg: float, start_deg: float, radius: float) -> Spatial:
	var arm = Spatial.new()
	var R := wall_radius
	var start_rad := deg2rad(start_deg)
	var end_rad := deg2rad(start_deg + span_deg)
	var mesh = MeshInstance.new()
	mesh.mesh = _build_arc_arm_mesh(R, radius, duct_wall_thickness, start_rad, end_rad, dir_sign)
	mesh.material_override = _hull_mat()
	arm.add_child(mesh)
	# Trimesh collision straight off the curved hull (exact hollow wall, no clipping) — the
	# box-segment approximation let the player catch/pass between segments on the curve.
	var body = StaticBody.new()
	var col = CollisionShape.new()
	col.shape = mesh.mesh.create_trimesh_shape()
	body.add_child(col)
	arm.add_child(body)
	# End collar at the outer mouth (where it meets the neighbour arc tile).
	_add_arc_arm_collar(arm, R, radius, end_rad, dir_sign)
	return arm

# Centreline point at angle t (t=0 at hub) and its forward tangent, in local XY plane.
func _arc_point(R: float, t: float, dir_sign: float) -> Vector3:
	return Vector3(dir_sign * R * sin(t), -R + R * cos(t), 0)

func _arc_forward(t: float, dir_sign: float) -> Vector3:
	return Vector3(dir_sign * cos(t), -sin(t), 0).normalized()

func _build_arc_arm_mesh(R: float, r: float, thickness: float, t0: float, t1: float, dir_sign: float) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arc_segs := 10
	var ring_segs := 16
	var orad := r + thickness
	for ai in range(arc_segs):
		var ta = lerp(t0, t1, float(ai) / arc_segs)
		var tb = lerp(t0, t1, float(ai + 1) / arc_segs)
		var ca := _arc_point(R, ta, dir_sign)
		var cb := _arc_point(R, tb, dir_sign)
		var fa := _arc_forward(ta, dir_sign)
		var fb := _arc_forward(tb, dir_sign)
		# Cross-section basis: axial (local Z) and the in-plane radial of the arc.
		var axial := Vector3(0, 0, 1)
		var ra: Vector3 = fa.cross(axial).normalized()   # in-plane normal at a
		var rb: Vector3 = fb.cross(axial).normalized()
		for ri in range(ring_segs):
			var p0 = TAU * ri / ring_segs
			var p1 = TAU * (ri + 1) / ring_segs
			# Cross-section direction at section angle p (0=+axial, sweeps around the tube).
			var da0 = (axial * cos(p0) + ra * sin(p0))
			var da1 = (axial * cos(p1) + ra * sin(p1))
			var db0 = (axial * cos(p0) + rb * sin(p0))
			var db1 = (axial * cos(p1) + rb * sin(p1))
			# UV: U around the tube, V along the arc.
			var uA = float(ai) / arc_segs * (abs(t1 - t0) * R) / 4.0
			var uB = float(ai + 1) / arc_segs * (abs(t1 - t0) * R) / 4.0
			var v0 = float(ri) / ring_segs * (TAU * r) / 4.0
			var v1 = float(ri + 1) / ring_segs * (TAU * r) / 4.0
			# Inner wall (normals point inward).
			_arc_quad(st, ca + da0 * r, cb + db0 * r, ca + da1 * r, cb + db1 * r,
				-da0, -db0, -da1, -db1, Vector2(v0, uA), Vector2(v0, uB), Vector2(v1, uA), Vector2(v1, uB), false)
			# Outer wall (normals point outward).
			_arc_quad(st, ca + da0 * orad, cb + db0 * orad, ca + da1 * orad, cb + db1 * orad,
				da0, db0, da1, db1, Vector2(v0, uA), Vector2(v0, uB), Vector2(v1, uA), Vector2(v1, uB), true)
	return st.commit()

func _arc_quad(st: SurfaceTool, a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3,
		na0: Vector3, nb0: Vector3, na1: Vector3, nb1: Vector3,
		uva0: Vector2, uvb0: Vector2, uva1: Vector2, uvb1: Vector2, outward: bool) -> void:
	if outward:
		st.add_normal(na0); st.add_uv(uva0); st.add_vertex(a0)
		st.add_normal(nb0); st.add_uv(uvb0); st.add_vertex(b0)
		st.add_normal(na1); st.add_uv(uva1); st.add_vertex(a1)
		st.add_normal(nb0); st.add_uv(uvb0); st.add_vertex(b0)
		st.add_normal(nb1); st.add_uv(uvb1); st.add_vertex(b1)
		st.add_normal(na1); st.add_uv(uva1); st.add_vertex(a1)
	else:
		st.add_normal(na0); st.add_uv(uva0); st.add_vertex(a0)
		st.add_normal(na1); st.add_uv(uva1); st.add_vertex(a1)
		st.add_normal(nb0); st.add_uv(uvb0); st.add_vertex(b0)
		st.add_normal(nb0); st.add_uv(uvb0); st.add_vertex(b0)
		st.add_normal(na1); st.add_uv(uva1); st.add_vertex(a1)
		st.add_normal(nb1); st.add_uv(uvb1); st.add_vertex(b1)

func _add_arc_arm_collar(arm: Node, R: float, r: float, t: float, dir_sign: float) -> void:
	var collar = MeshInstance.new()
	collar.mesh = _get_ring_collar_mesh(r + ring_extra_radius, max(ring_height, 0.18))
	collar.material_override = _get_res(CONDUIT_MAT_PATH)
	var centre := _arc_point(R, t, dir_sign)
	var fwd := _arc_forward(t, dir_sign)
	var axial := Vector3(0, 0, 1)
	var rad: Vector3 = fwd.cross(axial).normalized()
	collar.transform = Transform(Basis(rad, axial, fwd), centre)
	arm.add_child(collar)

func _add_arm_end_collar(root: Node, z: float, radius: float) -> void:
	var collar = MeshInstance.new()
	collar.mesh = _get_ring_collar_mesh(radius + ring_extra_radius, max(ring_height, 0.18))
	collar.material_override = _get_res(CONDUIT_MAT_PATH)
	collar.translation = Vector3(0, 0, z)
	root.add_child(collar)

func _add_hollow_box_collision(root: Node, length: float, radius: float) -> StaticBody:
	var body = StaticBody.new()
	root.add_child(body)
	var wall := max(duct_wall_thickness, 0.2)
	var half_len := length * 0.5
	var specs = [
		[Vector3(0, radius + wall * 0.5, 0), Vector3(radius, wall * 0.5, half_len)],
		[Vector3(0, -radius - wall * 0.5, 0), Vector3(radius, wall * 0.5, half_len)],
		[Vector3(radius + wall * 0.5, 0, 0), Vector3(wall * 0.5, radius + wall, half_len)],
		[Vector3(-radius - wall * 0.5, 0, 0), Vector3(wall * 0.5, radius + wall, half_len)]
	]
	for spec in specs:
		var shape = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = spec[1]
		shape.shape = box
		shape.translation = spec[0]
		body.add_child(shape)
	return body

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

func make_endcap(dir: Vector3 = Vector3.FORWARD) -> Spatial:
	var root = Spatial.new()
	root.name = "DuctEndCap"
	var length := 1.0
	var mesh = MeshInstance.new()
	mesh.mesh = _get_hollow_cylinder(length, duct_radius, duct_wall_thickness)
	mesh.material_override = _hull_mat()
	root.add_child(mesh)

	var cap = MeshInstance.new()
	cap.mesh = _get_cap_disc_mesh(duct_radius + duct_wall_thickness)
	cap.material_override = _hull_mat()
	cap.translation = Vector3(0, 0, length * 0.5)
	root.add_child(cap)
	
	# Open torus collar at the mouth instead of a solid disc plate. The flat CylinderMesh
	# cap read as a "circular plate covering the section" (bug); a collar frames the
	# opening like the curved-duct rings and keeps the tube passable.
	var collar = MeshInstance.new()
	collar.mesh = _get_ring_collar_mesh(duct_radius + ring_extra_radius, max(ring_height, 0.18))
	collar.material_override = _get_res(CONDUIT_MAT_PATH)
	collar.translation = Vector3(0, 0, length * 0.5)
	root.add_child(collar)

	var body = StaticBody.new()
	root.add_child(body)
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(duct_radius + duct_wall_thickness, duct_radius + duct_wall_thickness, 0.12)
	shape.shape = box
	shape.translation = Vector3(0, 0, length * 0.5)
	body.add_child(shape)

	var fwd := dir.normalized()
	var up_ref := Vector3.UP if abs(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := up_ref.cross(fwd).normalized()
	var local_up := fwd.cross(right).normalized()
	root.transform.basis = Basis(right, local_up, fwd)
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

	# The room shell is visual only. A capsule trimesh seals the port mouths before the
	# connector arms are added, making some room-junctions look open but physically closed.
	
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

# Hollow sphere shell with a MOUTH carved toward each arm direction, so the junction
# reads as a sphere from outside but is open and navigable from inside the ducts (the
# plain SphereMesh hub was a closed ball ~the bore diameter -> sealed every crossing).
# Built as a lat/long UV sphere; any quad whose centre falls within `hole_half_angle`
# of a hole direction is skipped, opening a round port aligned with the arm bore. Both
# inner and outer faces are emitted (wall thickness) so the shell is visible from in
# and out, matching the hollow-cylinder/_hull_mat convention.
func _get_pierced_sphere_mesh(radius: float, thickness: float, hole_dirs: Array, hole_half_angle: float) -> ArrayMesh:
	var dir_key = ""
	for d in hole_dirs:
		dir_key += "_%d%d%d" % [round(d.x), round(d.y), round(d.z)]
	var key = "pierced_sphere_%f_%f_%f%s" % [radius, thickness, hole_half_angle, dir_key]
	if _mesh_cache.has(key): return _mesh_cache[key]

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings = 16   # latitude bands
	var segs = 24    # longitude segments
	var cos_thresh = cos(hole_half_angle)
	var orad = radius + thickness

	for ri in range(rings):
		var t0 = PI * ri / rings
		var t1 = PI * (ri + 1) / rings
		for si in range(segs):
			var p0 = TAU * si / segs
			var p1 = TAU * (si + 1) / segs
			# Quad corners as unit directions (theta = polar from +Y, phi around).
			var d00 = _sphere_dir(t0, p0)
			var d01 = _sphere_dir(t0, p1)
			var d10 = _sphere_dir(t1, p0)
			var d11 = _sphere_dir(t1, p1)
			# Skip the quad if its centre lies inside any hole cone -> opens a port.
			var centre = (d00 + d01 + d10 + d11).normalized()
			var in_hole = false
			for hd in hole_dirs:
				if centre.dot(hd) >= cos_thresh:
					in_hole = true
					break
			if in_hole:
				continue
			_emit_sphere_quad(st, d00, d01, d10, d11, radius, false)  # inner (faces in)
			_emit_sphere_quad(st, d00, d01, d10, d11, orad, true)     # outer (faces out)

	var mesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

func _sphere_dir(theta: float, phi: float) -> Vector3:
	var st_ = sin(theta)
	return Vector3(st_ * cos(phi), cos(theta), st_ * sin(phi))

# Emit one sphere quad (two tris). `outward`=false makes the front face point toward the
# centre (inner shell, normals inward); =true points it away (outer shell).
func _emit_sphere_quad(st: SurfaceTool, d00: Vector3, d01: Vector3, d10: Vector3, d11: Vector3, r: float, outward: bool) -> void:
	var s = 1.0 if outward else -1.0
	var v00 = d00 * r; var v01 = d01 * r; var v10 = d10 * r; var v11 = d11 * r
	var n00 = d00 * s; var n01 = d01 * s; var n10 = d10 * s; var n11 = d11 * s
	# UV roughly from spherical coords so the panel shader has gradient (no all-seam blue).
	var uv00 = _sphere_uv(d00, r); var uv01 = _sphere_uv(d01, r)
	var uv10 = _sphere_uv(d10, r); var uv11 = _sphere_uv(d11, r)
	if outward:
		# CCW seen from outside.
		st.add_normal(n00); st.add_uv(uv00); st.add_vertex(v00)
		st.add_normal(n10); st.add_uv(uv10); st.add_vertex(v10)
		st.add_normal(n01); st.add_uv(uv01); st.add_vertex(v01)
		st.add_normal(n01); st.add_uv(uv01); st.add_vertex(v01)
		st.add_normal(n10); st.add_uv(uv10); st.add_vertex(v10)
		st.add_normal(n11); st.add_uv(uv11); st.add_vertex(v11)
	else:
		# Reversed winding so the front face points inward (visible from inside the hub).
		st.add_normal(n00); st.add_uv(uv00); st.add_vertex(v00)
		st.add_normal(n01); st.add_uv(uv01); st.add_vertex(v01)
		st.add_normal(n10); st.add_uv(uv10); st.add_vertex(v10)
		st.add_normal(n01); st.add_uv(uv01); st.add_vertex(v01)
		st.add_normal(n11); st.add_uv(uv11); st.add_vertex(v11)
		st.add_normal(n10); st.add_uv(uv10); st.add_vertex(v10)

func _sphere_uv(d: Vector3, r: float) -> Vector2:
	var u = (atan2(d.z, d.x) + PI) / TAU * (TAU * r) / 4.0
	var v = (acos(clamp(d.y, -1.0, 1.0)) / PI) * (PI * r) / 4.0
	return Vector2(u, v)

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

func _get_cap_disc_mesh(radius: float) -> ArrayMesh:
	var key = "cap_disc_%f" % radius
	if _mesh_cache.has(key): return _mesh_cache[key]
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var normal := Vector3(0, 0, 1)
	for i in range(segments):
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		st.add_normal(normal); st.add_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3.ZERO)
		st.add_normal(normal); st.add_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5)); st.add_vertex(Vector3(radius * cos(a0), radius * sin(a0), 0))
		st.add_normal(normal); st.add_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5)); st.add_vertex(Vector3(radius * cos(a1), radius * sin(a1), 0))
	var mesh = st.commit()
	_mesh_cache[key] = mesh
	return mesh

func _add_collision_cylinder(root: Node, length: float, radius: float) -> StaticBody:
	# Godot 3 ConcavePolygonShape treats the hollow-cylinder triangles as two-sided
	# blockers. Four box walls keep the tube open without invisible circular plates.
	return _add_hollow_box_collision(root, length, radius)

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
func _add_room_airlock(cell: Dictionary, gx: int, gy: int, conn_dir: int, parent: Node = null) -> void:
	var airlock_scene = _get_res(AIRLOCK_CHAMBER_PATH)
	if not airlock_scene: return

	var airlock = airlock_scene.instance()
	airlock.name = "RoomAirlock"
	# No scene transition in the maze: let the airlock complete its cycle locally
	# (open the exit door after pressurizing) instead of hanging on "PRESURIZANDO".
	if "standalone_cycle" in airlock:
		airlock.standalone_cycle = true
	var target_parent := parent if parent != null else self
	target_parent.add_child(airlock)
	_sanitize_generated_airlock_collision(airlock)
	_ensure_airlock_interactables(airlock)

	var angle_rad := deg2rad(float(gx) * (360.0 / sectors))
	var radius := wall_radius
	var cell_pos := Vector3(radius * cos(angle_rad), _axis_y(gy), radius * sin(angle_rad))
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

func _sanitize_generated_airlock_collision(airlock: Node) -> void:
	var shell = airlock.get_node_or_null("CylindricalShell")
	if shell is CollisionObject:
		shell.collision_layer = 0
		shell.collision_mask = 0
		var shell_shape = shell.get_node_or_null("CollisionShape")
		if shell_shape is CollisionShape:
			shell_shape.disabled = true
	var camera_walls = airlock.get_node_or_null("CameraWalls")
	if camera_walls is CollisionObject:
		camera_walls.collision_layer = 0
		camera_walls.collision_mask = 0
		for child in camera_walls.get_children():
			if child is CollisionShape:
				child.disabled = true

func _ensure_airlock_interactables(airlock: Node) -> void:
	var doors = [
		[airlock.get_node_or_null("OuterDoor"), "outer"],
		[airlock.get_node_or_null("InnerDoor"), "inner"]
	]
	for entry in doors:
		var door = entry[0]
		if not is_instance_valid(door):
			continue
		_mark_airlock_door_interactable(door, airlock, String(entry[1]))

func _mark_airlock_door_interactable(door: Node, owner: Node, door_name: String) -> void:
	var pending: Array = [door]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node.has_method("interact"):
			node.set_meta("airlock_controller_owned", true)
			node.set_meta("airlock_controller_owner_path", owner.get_path())
			node.set_meta("airlock_door_name", door_name)
			if not node.is_in_group("interactable"):
				node.add_to_group("interactable")
			if not node.is_in_group("focusable"):
				node.add_to_group("focusable")
		if "is_interactable" in node:
			node.set("is_interactable", true)
		for child in node.get_children():
			pending.push_back(child)

	if door.get_node_or_null("InteractionProxy") == null:
		var proxy = KinematicBody.new()
		proxy.name = "InteractionProxy"
		proxy.set_script(FORWARD_INTERACT_SCRIPT)
		proxy.set_meta("airlock_controller_owned", true)
		proxy.set_meta("airlock_controller_owner_path", owner.get_path())
		proxy.set_meta("airlock_door_name", door_name)
		proxy.collision_layer = 4
		proxy.collision_mask = 0
		door.add_child(proxy)
		var shape = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = Vector3(2.2, 2.2, 0.6)
		shape.shape = box
		proxy.add_child(shape)
		if "interaction_text" in proxy:
			proxy.set("interaction_text", "Operar exclusa")
		if "is_interactable" in proxy:
			proxy.set("is_interactable", true)

func _grado(conn: Array) -> int:
	var count = 0
	for c in conn:
		if c: count += 1
	return count
