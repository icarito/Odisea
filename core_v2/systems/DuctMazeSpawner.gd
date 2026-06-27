tool
extends Spatial
class_name DuctMazeStreamer

# FD-052: DuctMazeStreamer
# Streams axial duct maze chunks around the player.

const INNER_RADIUS = 16.0
const DEFAULT_RING_STEP = 8.0
const ANGLE_STEP = 30.0
const CSG_SUBTRACT = 2
# Duct tiles live on the Prop layer (7, bit 64) instead of Entorno (1). The player
# always collides with Prop (PLAYER_REQUIRED_COLLISION_MASK), but the camera spring arm
# (camera_collision_mask=129 = Entorno+CameraCollision, no Prop) ignores them — so the
# camera passes THROUGH the ducts instead of being shoved by every wall, letting you see
# inside the tubes.
const DUCT_COLLISION_LAYER = 1 << 6

export(float) var inner_radius := INNER_RADIUS
export(float) var ring_step := DEFAULT_RING_STEP
export(int) var sectors := 12
export(int) var rings := 6
export(int) var height_steps := 6
export(int) var room_count := 4
export(int) var extra_cycles := 2
export(int) var seed_value := -1
export(bool) var axial_layout := false
export(float) var axial_center_y := 0.0
export(bool) var add_connection_bridges := true
export(float) var duct_radius := 3.75
export(float) var duct_wall_thickness := 0.35
export(float) var connection_overlap := 1.25
export(float) var collar_radius_extra := 0.08
export(float) var collar_length := 0.55
export(float) var room_radius_multiplier := 3.2
export(float) var room_length_multiplier := 1.6
export(int) var mesh_segments := 16
export(int) var room_segments := 18
export(int) var overlay_stride := 8
export(bool) var enable_zone_particles := false
export(bool) var streaming_enabled := false
export(NodePath) var stream_target_path := NodePath("../../Pilot")
export(float) var stream_total_length := 8000.0
export(int) var stream_chunk_rings := 24
export(int) var stream_active_chunks_each_side := 1
export(int) var stream_seam_ports := 4
export(float) var stream_update_interval := 0.35
export(int) var stream_builds_per_tick := 1
# DEPRECATED: replaced by MST with wrap_x=true in axial_layout. Kept for .tscn compatibility.
export(bool) var dual_axial_lanes := false
# DEPRECATED: replaced by MST with wrap_x=true in axial_layout. Kept for .tscn compatibility.
export(bool) var concentric_axial_lanes := false
# DEPRECATED (concentric/dual only)
export(int) var lane_a_sector := -1
# DEPRECATED (concentric/dual only)
export(int) var lane_b_sector := -1
# DEPRECATED (concentric/dual only)
export(int) var lane_connector_stride := 8
# DEPRECATED (concentric/dual only)
export(int) var lane_connector_offset := 3
# DEPRECATED (concentric only)
export(float) var concentric_radius_gap := 12.0
# DEPRECATED (concentric only)
export(int) var concentric_spine_stride := 4
# DEPRECATED (concentric only)
export(int) var radial_bridge_stride := 20
# DEPRECATED (concentric only)
export(int) var radial_bridge_offset := 4
# DEPRECATED (concentric only): entry tunnel is now a room seeded by MST.
export(bool) var entry_tunnel_enabled := true
# DEPRECATED (concentric only)
export(int) var entry_sector := 0
export(bool) var room_airlocks_enabled := true
export(bool) var room_light_strips_enabled := true
export(bool) var corridor_valves_enabled := false

# Tile paths
const TILE_PATHS = {
	"E": "res://core_v2/props/duct/DuctEndCap.tscn",
	"W": "res://core_v2/props/duct/DuctRadial.tscn",
	"C": "res://core_v2/props/duct/DuctElbow.tscn",
	"T": "res://core_v2/props/duct/DuctTee.tscn",
	"X": "res://core_v2/props/duct/DuctCross.tscn",
	"S": "res://core_v2/props/duct/DuctIncline.tscn"
}
const CAPSULE_PATH = "res://core_v2/props/duct/CapsuleRoom.tscn"
const VALVE_PATH = "res://core_v2/props/duct/DuctGateValve.tscn"
const IRIS_DOOR_PATH = "res://core_v2/props/doors/IrisDoorV2.tscn"
# IrisDoorV2's iris_radius default — used to scale the door to the duct opening.
const IRIS_DOOR_BASE_RADIUS = 1.7

# Resource cache
var _resource_cache := {}
var _runtime_material: Material = null
var _stream_chunks := {}
var _stream_target: Spatial = null
var _stream_timer := 0.0
var _stream_chunk_count := 0
var _stream_desired_chunks := {}
var _stream_pending_chunks := []
var _build_rings := -1
var _build_axial_center_y := 0.0
var _build_chunk_index := -1
var _room_light_material: Material = null

# Exported dictionaries for manual override
export(Dictionary) var duct_tiles := {}
export(PackedScene) var capsule_scene: PackedScene

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
	# Clear existing
	for child in get_children():
		child.queue_free()

	_stream_chunks.clear()
	if streaming_enabled and axial_layout:
		_start_streaming()
		return

	set_physics_process(false)
	_generate_grid_into(self, rings, axial_center_y, seed_value, {})

func _generate_grid_into(parent: Spatial, grid_depth: int, center_y: float, grid_seed: int, fixed_border_tiles: Dictionary, chunk_index: int = -1) -> void:
	var grid: Array
	var mst_gen = ScaffoldMSTGenerator.new()
	var params = {
		"grid_width": sectors,
		"grid_depth": grid_depth,
		"mst_max_height_steps": height_steps,
		"room_count": room_count,
		"extra_cycles": extra_cycles,
		"fixed_border_tiles": fixed_border_tiles,
		"wrap_x": axial_layout
	}
	mst_gen.apply_params(params)
	grid = mst_gen.generate_grid_data(grid_seed)

	var previous_build_rings: int = _build_rings
	var previous_build_center_y: float = _build_axial_center_y
	var previous_build_chunk_index: int = _build_chunk_index
	_build_rings = grid_depth
	_build_axial_center_y = center_y
	_build_chunk_index = chunk_index

	for i in range(grid.size()):
		var cell = grid[i]
		if cell == null:
			continue

		var gx: int = int(_cell_value(cell, "grid_x", i % sectors))
		var gy: int = int(_cell_value(cell, "grid_y", i / sectors))
		var base_height: float = float(_cell_value(cell, "base_height", 0.0))
		var is_room: bool = bool(_cell_value(cell, "is_room", false))
		var extra_endpoint_specs: Array = _cell_value(cell, "extra_endpoint_specs", [])
		var v = _cell_value(cell, "variant", null)
		if v == null:
			continue

		var instance: Spatial = null

		instance = _make_procedural_tile(v.connections, v.port_heights, _cell_radius(gy, base_height), is_room, extra_endpoint_specs)
		if instance:
			parent.add_child(instance)
			instance.transform = _grid_to_world(gx, gy, base_height)
			instance.set_meta("variant_id", v.id)
			instance.set_meta("rotation", v.rotation)
			_add_overlay(instance, gy, i)

	_insert_valves(parent)
	_activate_collapse_triggers(parent)
	_build_rings = previous_build_rings
	_build_axial_center_y = previous_build_center_y
	_build_chunk_index = previous_build_chunk_index

func _physics_process(delta: float) -> void:
	if not streaming_enabled or not axial_layout:
		return
	_stream_timer -= delta
	if _stream_timer > 0.0:
		return
	_stream_timer = max(0.05, stream_update_interval)
	_refresh_stream(false)
	_process_stream_queue()

func _start_streaming() -> void:
	_stream_target = get_node_or_null(stream_target_path) as Spatial
	_stream_chunk_count = int(max(1, ceil(stream_total_length / _stream_chunk_length())))
	_stream_desired_chunks.clear()
	_stream_pending_chunks.clear()
	set_physics_process(true)
	_refresh_stream(true)

func _refresh_stream(force: bool) -> void:
	var center_chunk: int = _chunk_index_for_y(_stream_target_local_y())
	var desired := {}
	var radius: int = int(max(0, stream_active_chunks_each_side))
	for chunk_index in range(center_chunk - radius, center_chunk + radius + 1):
		if chunk_index < 0 or chunk_index >= _stream_chunk_count:
			continue
		desired[chunk_index] = true
		if not _stream_chunks.has(chunk_index):
			if force and chunk_index == center_chunk:
				_load_stream_chunk(chunk_index)
			else:
				_queue_stream_chunk(chunk_index)

	_stream_desired_chunks = desired
	for i in range(_stream_pending_chunks.size() - 1, -1, -1):
		if not desired.has(_stream_pending_chunks[i]):
			_stream_pending_chunks.remove(i)

	for key in _stream_chunks.keys():
		if not desired.has(key):
			var chunk: Node = _stream_chunks[key]
			_stream_chunks.erase(key)
			if is_instance_valid(chunk):
				chunk.queue_free()

func _queue_stream_chunk(chunk_index: int) -> void:
	if _stream_chunks.has(chunk_index) or _stream_pending_chunks.has(chunk_index):
		return
	_stream_pending_chunks.append(chunk_index)

func _process_stream_queue() -> void:
	var built := 0
	while built < int(max(1, stream_builds_per_tick)) and not _stream_pending_chunks.empty():
		var chunk_index: int = int(_stream_pending_chunks.pop_front())
		if _stream_desired_chunks.has(chunk_index) and not _stream_chunks.has(chunk_index):
			_load_stream_chunk(chunk_index)
			built += 1

func _load_stream_chunk(chunk_index: int) -> void:
	var chunk_root: Spatial = Spatial.new()
	chunk_root.name = "DuctStreamChunk_%03d" % chunk_index
	chunk_root.set_meta("chunk_index", chunk_index)
	add_child(chunk_root)
	_stream_chunks[chunk_index] = chunk_root
	_generate_grid_into(
		chunk_root,
		_stream_chunk_depth(),
		_stream_chunk_center_y(chunk_index),
		_stream_chunk_seed(chunk_index),
		_stream_fixed_border_tiles(chunk_index),
		chunk_index
	)

func _stream_target_local_y() -> float:
	if not _stream_target or not is_instance_valid(_stream_target):
		_stream_target = get_node_or_null(stream_target_path) as Spatial
	if _stream_target and is_instance_valid(_stream_target):
		return global_transform.affine_inverse().xform(_stream_target.global_transform.origin).y
	return axial_center_y

func _stream_chunk_depth() -> int:
	return int(max(2, stream_chunk_rings))

func _stream_chunk_length() -> float:
	return float(_stream_chunk_depth()) * ring_step

func _stream_start_y() -> float:
	return axial_center_y - stream_total_length * 0.5

func _stream_chunk_center_y(chunk_index: int) -> float:
	return _stream_start_y() + (float(chunk_index) + 0.5) * _stream_chunk_length()

func _chunk_index_for_y(local_y: float) -> int:
	var index: int = int(floor((local_y - _stream_start_y()) / _stream_chunk_length()))
	return int(clamp(index, 0, max(0, _stream_chunk_count - 1)))

func _stream_chunk_seed(chunk_index: int) -> int:
	var base_seed: int = seed_value if seed_value != -1 else 52
	return int(abs(base_seed + chunk_index * 92821 + 131))

func _stream_fixed_border_tiles(chunk_index: int) -> Dictionary:
	var fixed := {}
	var depth: int = _stream_chunk_depth()
	if chunk_index > 0:
		_add_stream_seam_tiles(fixed, chunk_index, 0)
	if chunk_index < _stream_chunk_count - 1:
		_add_stream_seam_tiles(fixed, chunk_index + 1, depth - 1)
	return fixed

func _add_stream_seam_tiles(fixed: Dictionary, seam_index: int, y: int) -> void:
	var port_count: int = int(clamp(stream_seam_ports, 1, max(1, sectors)))
	var stride: int = int(max(1, floor(float(sectors) / float(port_count))))
	var offset: int = int(abs(_stream_hash(seam_index, 17))) % stride
	for n in range(port_count):
		var x: int = int((offset + n * stride) % sectors)
		fixed["%d,%d" % [x, y]] = {"height": _stream_seam_height(seam_index, x)}

func _stream_seam_height(seam_index: int, sector: int) -> float:
	var level_count: int = int(max(1, height_steps))
	var level: int = (int(abs(_stream_hash(seam_index, sector))) % level_count) + 1
	return float(level) * 2.0

func _stream_hash(a: int, b: int) -> int:
	var base_seed: int = seed_value if seed_value != -1 else 52
	return int(base_seed + a * 73856093 + b * 19349663)

func get_active_stream_chunk_indices() -> Array:
	var keys: Array = _stream_chunks.keys()
	keys.sort()
	return keys

func get_stream_coverage_length() -> float:
	return float(_stream_chunk_count) * _stream_chunk_length()

func _cell_value(cell, key: String, fallback):
	if cell is Dictionary:
		return cell[key] if cell.has(key) else fallback
	var value = cell.get(key)
	return fallback if value == null else value

func _grid_to_world(gx: int, gy: int, height: float) -> Transform:
	var r = _cell_radius(gy, height)
	var angle = deg2rad(gx * _angle_step())

	var pos: Vector3
	if axial_layout:
		pos = Vector3(r * cos(angle), _axis_position(gy), r * sin(angle))
	else:
		pos = Vector3(r * cos(angle), height, r * sin(angle))

	# Basis: X=tangent, Y=up, Z=radial outward
	var tangent = Vector3(-sin(angle), 0, cos(angle))
	var up = Vector3.UP
	var radial = Vector3(cos(angle), 0, sin(angle))

	var basis = Basis(tangent, up, radial)
	return Transform(basis, pos)

func _ring_radius(gy: int) -> float:
	return inner_radius + (float(gy) + 0.5) * ring_step

func _angle_step() -> float:
	return 360.0 / float(max(1, sectors))

func _cell_radius(gy: int, height: float) -> float:
	if axial_layout:
		return inner_radius + height
	return _ring_radius(gy)

func _axis_position(gy: int) -> float:
	var active_rings: int = rings if _build_rings < 0 else _build_rings
	var active_center_y: float = axial_center_y if _build_rings < 0 else _build_axial_center_y
	var centered_index: float = float(gy) - float(max(active_rings - 1, 0)) * 0.5
	return active_center_y + centered_index * ring_step

func _make_procedural_tile(connections: Array, port_heights: Array, ring_radius: float, is_room: bool = false, extra_endpoint_specs: Array = []) -> Spatial:
	var root: Spatial = Spatial.new()
	root.name = "DuctProceduralTile"
	root.set_meta("is_room", is_room)

	var visual_data: Dictionary = _new_mesh_data()
	var collision_data: Dictionary = _new_mesh_data()
	var visual_radius: float = duct_radius
	var collision_radius: float = max(0.2, duct_radius - 0.05)
	var collar_radius: float = min(duct_radius + duct_wall_thickness + collar_radius_extra, duct_radius + max(duct_wall_thickness, 0.12))

	# A room's port tube must reach the capsule wall, not just the grid port endpoint.
	# The capsule body sits at _room_outer_radius(); the bare port endpoint is well
	# inside it (~4 vs ~6.2), so without this the tube stops short of the carved hole
	# and the opening reads as "a hole with no tunnel reaching it" — you can't enter.
	# We extend the tube out to the wall and remember that wall point as the mouth so
	# the airlock gate sits in the opening instead of floating inside the room.
	# Every port tube must reach the OUTER surface of whatever shell wraps this tile,
	# then cross it, or the carved hole has no tunnel behind it ("shell with a hole but
	# no way out"). Rooms are wrapped by the capsule (_room_outer_radius). Junctions
	# (degree > 1) are wrapped by the junction sphere (duct_radius+wall). Tangential
	# (E/W) port endpoints land at only ~2.5 from centre — well inside the sphere
	# (~4.1) — so without forcing the tube out to the shell surface those arms dead-end
	# inside the sphere and read as "small nexus, no exit".
	var has_junction_shell: bool = (not is_room) and _grado(connections) > 1
	var shell_reach: float = 0.0
	if is_room:
		shell_reach = _room_outer_radius()
	elif has_junction_shell:
		shell_reach = duct_radius + duct_wall_thickness

	var endpoint_specs: Array = []
	for d in range(4):
		if d >= connections.size() or not connections[d]:
			continue
		var height: float = 0.0
		if d < port_heights.size():
			height = float(port_heights[d])
		var endpoint: Vector3 = _local_port_endpoint(d, ring_radius, height)
		var length: float = endpoint.length()
		if length <= 0.01:
			continue
		var axis: Vector3 = endpoint.normalized()
		# Mouth = where the tube meets the shell surface (room wall / junction sphere),
		# or the grid endpoint when there's no shell (straight/elbow corridor).
		var mouth: Vector3 = endpoint
		var reach: float = length
		if shell_reach > length:
			mouth = axis * shell_reach
			reach = shell_reach
		# Tube spans from BEHIND the cell centre (overlap so it buries into the shell /
		# meets the opposite arm) out PAST the mouth by connection_overlap, so the bore
		# punches cleanly through the shell and the neighbour's tube overlaps it.
		var near: float = -connection_overlap
		var far: float = reach + connection_overlap
		var tube_length: float = far - near
		var tube_center: Vector3 = axis * ((near + far) * 0.5)
		endpoint_specs.append({"dir": d, "endpoint": endpoint, "mouth": mouth, "length": length, "axis": axis, "airlock": true})
		_append_cylinder_shell(visual_data, tube_center, axis, tube_length, visual_radius, mesh_segments, true)
		_append_cylinder_shell(collision_data, tube_center, axis, tube_length, collision_radius, mesh_segments, false)
		# Collar ring at the mouth. When there's a shell (room/junction) push it slightly
		# outward so its faces don't sit coplanar with the shell (z-fight). For shell-less
		# straight/elbow corridors there is no mouth surface to clash with, and two
		# neighbour tiles meet at the grid endpoint — push the collar inward there so the
		# two collars don't overlap at the seam midpoint.
		var collar_offset: float = collar_length * 0.25 if shell_reach > 0.0 else -collar_length * 0.25
		var collar_center: Vector3 = mouth + axis * collar_offset
		_append_cylinder_shell(visual_data, collar_center, axis, collar_length, collar_radius, mesh_segments, true)

	for extra_spec in extra_endpoint_specs:
		if not (extra_spec is Dictionary):
			continue
		var spec_copy: Dictionary = extra_spec.duplicate()
		var extra_axis: Vector3 = spec_copy["axis"]
		# Extra ports (radial bridges / entry tunnels) land inside the room. Put the gate
		# at the capsule wall regardless. Only emit an inner tube when the port has no
		# external bridge tube of its own — otherwise we'd double the geometry there.
		if is_room and shell_reach > 0.0:
			var extra_mouth: Vector3 = extra_axis * shell_reach
			spec_copy["mouth"] = extra_mouth
			if not spec_copy.get("external_tube", false):
				var extra_len: float = shell_reach + connection_overlap * 2.0
				var extra_center: Vector3 = extra_axis * (shell_reach * 0.5)
				_append_cylinder_shell(visual_data, extra_center, extra_axis, extra_len, visual_radius, mesh_segments, true)
				_append_cylinder_shell(collision_data, extra_center, extra_axis, extra_len, collision_radius, mesh_segments, false)
				_append_cylinder_shell(visual_data, extra_mouth + extra_axis * (collar_length * 0.25), extra_axis, collar_length, collar_radius, mesh_segments, true)
		endpoint_specs.append(spec_copy)

	# Visual shells emit real back-faces so generated ducts remain readable even when
	# material culling/lighting changes. Collision shells stay single-sided.
	if is_room:
		_append_capsule_shell(visual_data, endpoint_specs, _room_outer_radius(), _room_body_length(), room_segments, 5, true)
		_append_capsule_shell(collision_data, endpoint_specs, _room_inner_radius(), _room_body_length(), room_segments, 5, false)
	elif _grado(connections) > 1:
		_append_sphere_shell(visual_data, endpoint_specs, duct_radius + duct_wall_thickness, mesh_segments, 6, true)
		_append_sphere_shell(collision_data, endpoint_specs, collision_radius, mesh_segments, 5, false)

	var visual_mesh: ArrayMesh = _mesh_from_data(visual_data)
	if visual_mesh:
		var mesh_instance: MeshInstance = MeshInstance.new()
		mesh_instance.name = "Geometry"
		mesh_instance.mesh = visual_mesh
		mesh_instance.material_override = _get_runtime_material()
		root.add_child(mesh_instance)

	var collision_mesh: ArrayMesh = _mesh_from_data(collision_data)
	if collision_mesh:
		var body: StaticBody = StaticBody.new()
		body.name = "Collision"
		body.collision_layer = DUCT_COLLISION_LAYER
		body.collision_mask = 255
		var shape: CollisionShape = CollisionShape.new()
		shape.shape = collision_mesh.create_trimesh_shape()
		body.add_child(shape)
		root.add_child(body)

	if is_room:
		if room_light_strips_enabled:
			_add_room_light_strips(root)
		if room_airlocks_enabled:
			_add_room_airlocks(root, endpoint_specs)

	return root

func _add_room_airlocks(root: Spatial, endpoint_specs: Array) -> void:
	# Airlocks are iris doors set into each tube mouth. IrisDoorV2 extends
	# InteractableBaseV2, so the player can open/close it through the normal
	# interaction system (group "interactable" + its InteractionArea) — no extra
	# wiring needed. Its passage axis is local Z (blades lie in the XY plane), which
	# _basis_from_z_axis aligns to the port direction.
	var iris_scene = _get_res(IRIS_DOOR_PATH)
	if not iris_scene:
		return
	# Scale the iris so its open aperture clears the duct bore.
	var iris_scale: float = max(1.0, (duct_radius + 0.1) / IRIS_DOOR_BASE_RADIUS)
	for spec in endpoint_specs:
		if spec.has("airlock") and not bool(spec["airlock"]):
			continue
		var axis: Vector3 = spec["axis"]
		# Set the door slightly inside the mouth so its frame reads as part of the wall
		# opening rather than floating beyond it.
		var mouth: Vector3 = spec["mouth"] if spec.has("mouth") else spec["endpoint"]
		var endpoint: Vector3 = mouth - axis * (collar_length * 0.5)
		var iris = iris_scene.instance()
		iris.name = "RoomAirlockIris_%d" % int(spec["dir"])
		# The InteractableBaseV2 (the actual interactable, in group "interactable") is the
		# IrisMechanism child, not the InteractableBridge root — configure it there.
		var mechanism = iris.get_node_or_null("IrisMechanism")
		if mechanism:
			if "interaction_text" in mechanism:
				mechanism.interaction_text = "Operar exclusa"
			# Start OPEN so the maze is traversable — you can walk into rooms. The player
			# closes a door on interact (e.g. to seal a section). A closed-by-default
			# airlock blocks every room entrance and reads as "no door ever opens to let
			# me in". The iris is "active" when open.
			if "starts_active" in mechanism:
				mechanism.starts_active = true
		iris.transform = Transform(_basis_from_z_axis(axis, Vector3.UP), endpoint)
		iris.scale = Vector3.ONE * iris_scale
		root.add_child(iris)
		# The iris .tscn's StaticBodies (Frame, DoorBlocker) default to layer 1 (Entorno),
		# which would block the camera. Move them to the Prop layer like the tubes so the
		# camera passes through; the player still collides (Prop is in the required mask).
		_move_static_bodies_to_prop_layer(iris)
		# Robust interaction targeting: give the iris its own InteractionArea (layer 16,
		# the interaction layer the player's interact scan reads) on the IrisMechanism, so
		# the player can target it whether the door is open or closed. Without it the only
		# physics body to hit when open is the Frame (under the non-interactable bridge
		# root), which doesn't resolve back to the mechanism.
		if mechanism:
			_ensure_iris_interaction_area(mechanism)

func _move_static_bodies_to_prop_layer(node: Node) -> void:
	if node is StaticBody:
		if (node.collision_layer & 1) != 0:
			node.collision_layer = DUCT_COLLISION_LAYER
	elif node is CSGCombiner:
		if (node.collision_layer & 1) != 0:
			node.collision_layer = DUCT_COLLISION_LAYER
	for child in node.get_children():
		_move_static_bodies_to_prop_layer(child)

func _ensure_iris_interaction_area(mechanism: Spatial) -> void:
	if mechanism.has_node("InteractionArea"):
		return
	var area := Area.new()
	area.name = "InteractionArea"
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	var shape := CollisionShape.new()
	var sphere := SphereShape.new()
	# Local radius; the mechanism's inherited scale (~2.3x) expands it to cover the bore.
	sphere.radius = 1.6
	shape.shape = sphere
	area.add_child(shape)
	mechanism.add_child(area)

func _add_room_light_strips(root: Spatial) -> void:
	var mat: Material = _get_room_light_material()
	var radius: float = _room_inner_radius() * 0.72
	var length: float = _room_body_length() * 0.72
	_add_room_strip(root, Vector3(radius, 0.0, 0.0), Vector3(0.10, length, 0.28), mat, "RoomLightStrip_XP")
	_add_room_strip(root, Vector3(-radius, 0.0, 0.0), Vector3(0.10, length, 0.28), mat, "RoomLightStrip_XN")
	_add_room_strip(root, Vector3(0.0, 0.0, radius), Vector3(0.28, length, 0.10), mat, "RoomLightStrip_ZP")
	_add_room_strip(root, Vector3(0.0, 0.0, -radius), Vector3(0.28, length, 0.10), mat, "RoomLightStrip_ZN")

func _add_room_strip(root: Spatial, pos: Vector3, size: Vector3, mat: Material, node_name: String) -> void:
	var mesh := CubeMesh.new()
	mesh.size = size
	var strip := MeshInstance.new()
	strip.name = node_name
	strip.mesh = mesh
	strip.material_override = mat
	strip.translation = pos
	root.add_child(strip)

func _get_room_light_material() -> Material:
	if _room_light_material:
		return _room_light_material
	var mat := SpatialMaterial.new()
	mat.flags_unshaded = true
	mat.albedo_color = Color(0.25, 0.95, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.95, 1.0, 1.0)
	mat.emission_energy = 1.4
	_room_light_material = mat
	return _room_light_material

func _get_runtime_material() -> Material:
	if _runtime_material:
		return _runtime_material
	var base_mat = _get_res("res://core_v2/props/duct/DuctHull.tres")
	if base_mat is SpatialMaterial:
		var mat: SpatialMaterial = base_mat.duplicate()
		mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
		_runtime_material = mat
	else:
		var fallback = SpatialMaterial.new()
		fallback.params_cull_mode = SpatialMaterial.CULL_DISABLED
		fallback.albedo_color = Color(0.2, 0.2, 0.22, 1.0)
		fallback.metallic = 0.3
		fallback.roughness = 0.9
		_runtime_material = fallback
	return _runtime_material

func _new_mesh_data() -> Dictionary:
	return {"vertices": [], "normals": [], "uvs": []}

func _mesh_from_data(data: Dictionary) -> ArrayMesh:
	if not data.has("vertices") or data["vertices"].empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PoolVector3Array(data["vertices"])
	arrays[Mesh.ARRAY_NORMAL] = PoolVector3Array(data["normals"])
	arrays[Mesh.ARRAY_TEX_UV] = PoolVector2Array(data["uvs"])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _push_triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	data["vertices"].append(a)
	data["vertices"].append(b)
	data["vertices"].append(c)
	data["normals"].append(na.normalized())
	data["normals"].append(nb.normalized())
	data["normals"].append(nc.normalized())
	data["uvs"].append(Vector2(0.0, 0.0))
	data["uvs"].append(Vector2(0.0, 1.0))
	data["uvs"].append(Vector2(1.0, 0.0))

func _push_shell_triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, double_sided: bool) -> void:
	_push_triangle(data, a, b, c, na, nb, nc)
	if double_sided:
		_push_triangle(data, c, b, a, -nc, -nb, -na)

func _push_shell_quad(data: Dictionary, p00: Vector3, p10: Vector3, p01: Vector3, p11: Vector3, n00: Vector3, n10: Vector3, n01: Vector3, n11: Vector3, double_sided: bool) -> void:
	_push_shell_triangle(data, p00, p10, p01, n00, n10, n01, double_sided)
	_push_shell_triangle(data, p01, p10, p11, n01, n10, n11, double_sided)

func _append_cylinder_shell(data: Dictionary, center: Vector3, axis: Vector3, length: float, radius: float, segments: int, double_sided: bool) -> void:
	if length <= 0.01 or radius <= 0.01:
		return
	var safe_segments: int = int(max(6, segments))
	var basis: Basis = _basis_from_y_axis(axis.normalized())
	var half_length: float = length * 0.5
	for s in range(safe_segments):
		var a0: float = TAU * float(s) / float(safe_segments)
		var a1: float = TAU * float(s + 1) / float(safe_segments)
		var n0: Vector3 = basis.xform(Vector3(cos(a0), 0.0, sin(a0))).normalized()
		var n1: Vector3 = basis.xform(Vector3(cos(a1), 0.0, sin(a1))).normalized()
		var p00: Vector3 = center + basis.xform(Vector3(cos(a0) * radius, -half_length, sin(a0) * radius))
		var p10: Vector3 = center + basis.xform(Vector3(cos(a0) * radius, half_length, sin(a0) * radius))
		var p01: Vector3 = center + basis.xform(Vector3(cos(a1) * radius, -half_length, sin(a1) * radius))
		var p11: Vector3 = center + basis.xform(Vector3(cos(a1) * radius, half_length, sin(a1) * radius))
		_push_shell_quad(data, p00, p10, p01, p11, n0, n0, n1, n1, double_sided)

func _append_sphere_shell(data: Dictionary, endpoint_specs: Array, radius: float, segments: int, rings: int, double_sided: bool) -> void:
	var safe_segments: int = int(max(8, segments))
	var safe_rings: int = int(max(4, rings))
	for y in range(safe_rings):
		var v0: float = -PI * 0.5 + PI * float(y) / float(safe_rings)
		var v1: float = -PI * 0.5 + PI * float(y + 1) / float(safe_rings)
		for s in range(safe_segments):
			var a0: float = TAU * float(s) / float(safe_segments)
			var a1: float = TAU * float(s + 1) / float(safe_segments)
			var n00: Vector3 = Vector3(cos(v0) * cos(a0), sin(v0), cos(v0) * sin(a0)).normalized()
			var n10: Vector3 = Vector3(cos(v1) * cos(a0), sin(v1), cos(v1) * sin(a0)).normalized()
			var n01: Vector3 = Vector3(cos(v0) * cos(a1), sin(v0), cos(v0) * sin(a1)).normalized()
			var n11: Vector3 = Vector3(cos(v1) * cos(a1), sin(v1), cos(v1) * sin(a1)).normalized()
			var patch_normal: Vector3 = (n00 + n10 + n01 + n11).normalized()
			if _is_port_hole_direction(patch_normal, endpoint_specs, radius):
				continue
			_push_shell_quad(data, n00 * radius, n10 * radius, n01 * radius, n11 * radius, n00, n10, n01, n11, double_sided)

func _append_capsule_shell(data: Dictionary, endpoint_specs: Array, radius: float, body_length: float, segments: int, hemisphere_rings: int, double_sided: bool) -> void:
	var safe_segments: int = int(max(8, segments))
	var half_body: float = body_length * 0.5
	for s in range(safe_segments):
		var a0: float = TAU * float(s) / float(safe_segments)
		var a1: float = TAU * float(s + 1) / float(safe_segments)
		var n0: Vector3 = Vector3(cos(a0), 0.0, sin(a0)).normalized()
		var n1: Vector3 = Vector3(cos(a1), 0.0, sin(a1)).normalized()
		var patch_normal: Vector3 = (n0 + n1).normalized()
		if not _is_port_hole_direction(patch_normal, endpoint_specs, radius):
			var p00: Vector3 = Vector3(n0.x * radius, -half_body, n0.z * radius)
			var p10: Vector3 = Vector3(n0.x * radius, half_body, n0.z * radius)
			var p01: Vector3 = Vector3(n1.x * radius, -half_body, n1.z * radius)
			var p11: Vector3 = Vector3(n1.x * radius, half_body, n1.z * radius)
			_push_shell_quad(data, p00, p10, p01, p11, n0, n0, n1, n1, double_sided)

	var safe_rings: int = int(max(3, hemisphere_rings))
	_append_capsule_cap(data, endpoint_specs, radius, half_body, 1.0, safe_segments, safe_rings, double_sided)
	_append_capsule_cap(data, endpoint_specs, radius, -half_body, -1.0, safe_segments, safe_rings, double_sided)

func _append_capsule_cap(data: Dictionary, endpoint_specs: Array, radius: float, y_center: float, y_sign: float, segments: int, rings: int, double_sided: bool) -> void:
	for r in range(rings):
		var p0: float = float(r) / float(rings) * PI * 0.5
		var p1: float = float(r + 1) / float(rings) * PI * 0.5
		for s in range(segments):
			var a0: float = TAU * float(s) / float(segments)
			var a1: float = TAU * float(s + 1) / float(segments)
			var n00: Vector3 = Vector3(sin(p0) * cos(a0), y_sign * cos(p0), sin(p0) * sin(a0)).normalized()
			var n10: Vector3 = Vector3(sin(p1) * cos(a0), y_sign * cos(p1), sin(p1) * sin(a0)).normalized()
			var n01: Vector3 = Vector3(sin(p0) * cos(a1), y_sign * cos(p0), sin(p0) * sin(a1)).normalized()
			var n11: Vector3 = Vector3(sin(p1) * cos(a1), y_sign * cos(p1), sin(p1) * sin(a1)).normalized()
			var patch_normal: Vector3 = (n00 + n10 + n01 + n11).normalized()
			if _is_port_hole_direction(patch_normal, endpoint_specs, radius):
				continue
			var center: Vector3 = Vector3(0.0, y_center, 0.0)
			_push_shell_quad(data, center + n00 * radius, center + n10 * radius, center + n01 * radius, center + n11 * radius, n00, n10, n01, n11, double_sided)

func _is_port_hole_direction(normal: Vector3, endpoint_specs: Array, radius: float) -> bool:
	if endpoint_specs.empty():
		return false
	var hole_ratio: float = clamp((duct_radius + 0.25) / max(radius, duct_radius + 0.26), 0.2, 0.96)
	var hole_cos: float = cos(min(PI * 0.45, asin(hole_ratio) + 0.12))
	for spec in endpoint_specs:
		var axis: Vector3 = spec["axis"]
		if normal.dot(axis) > hole_cos:
			return true
	return false

func _room_outer_radius() -> float:
	return max(duct_radius + duct_wall_thickness, duct_radius * room_radius_multiplier)

func _room_inner_radius() -> float:
	return max(duct_radius, _room_outer_radius() - max(duct_wall_thickness, 0.5))

func _room_body_length() -> float:
	return max(ring_step * room_length_multiplier, _room_outer_radius() * 1.25)

func _local_port_endpoint(direction: int, ring_radius: float, port_height: float = 0.0) -> Vector3:
	if axial_layout:
		if direction == 0:
			return Vector3(0, -ring_step * 0.5, port_height)
		if direction == 2:
			return Vector3(0, ring_step * 0.5, port_height)
		var axial_port_radius: float = ring_radius + port_height
		var axial_half_angle: float = deg2rad(_angle_step() * 0.5)
		var axial_tangent_offset: float = axial_port_radius * sin(axial_half_angle)
		var axial_inward_offset: float = axial_port_radius * cos(axial_half_angle) - ring_radius
		if direction == 1:
			return Vector3(axial_tangent_offset, 0, axial_inward_offset)
		return Vector3(-axial_tangent_offset, 0, axial_inward_offset)
	if direction == 0:
		return Vector3(0, port_height, -ring_step * 0.5)
	if direction == 2:
		return Vector3(0, port_height, ring_step * 0.5)
	var half_angle: float = deg2rad(_angle_step() * 0.5)
	var tangent_offset: float = ring_radius * sin(half_angle)
	var inward_offset: float = ring_radius * (cos(half_angle) - 1.0)
	if direction == 1:
		return Vector3(tangent_offset, port_height, inward_offset)
	return Vector3(-tangent_offset, port_height, inward_offset)

func _basis_from_y_axis(axis: Vector3) -> Basis:
	var y_axis: Vector3 = axis.normalized()
	var x_ref: Vector3 = Vector3.RIGHT
	if abs(y_axis.dot(x_ref)) > 0.92:
		x_ref = Vector3.FORWARD
	var z_axis: Vector3 = x_ref.cross(y_axis).normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _basis_from_z_axis(axis: Vector3, up_hint: Vector3 = Vector3.UP) -> Basis:
	var z_axis: Vector3 = axis.normalized()
	var y_ref: Vector3 = up_hint.normalized()
	if abs(z_axis.dot(y_ref)) > 0.92:
		y_ref = Vector3.RIGHT
	# Godot's Basis(x, y, z) takes the axes as COLUMNS; it is right-handed (det +1) only
	# when z == x.cross(y). Build an orthonormal frame, then flip x if the result came out
	# mirrored (det -1) — a mirrored basis shows up as a NEGATIVE scale on the placed node
	# and flips the iris blade rotation sense, so the door looks like it does nothing.
	var x_axis: Vector3 = y_ref.cross(z_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	if basis.determinant() < 0.0:
		basis = Basis(-x_axis, y_axis, z_axis)
	return basis

func _grado(conn: Array) -> int:
	var count = 0
	for c in conn:
		if c: count += 1
	return count

func _add_overlay(node: Spatial, gy: int, cell_index: int = -1) -> void:
	# Task 4: Content Zones
	var color = Color.white
	var zone_name = "Air"

	if gy >= 4:
		color = Color.cyan # Gas
		zone_name = "Gas"
	elif gy >= 2:
		color = Color.blue # Water
		zone_name = "Water"
	else:
		color = Color.lightgray # Air
		zone_name = "Air"

	node.set_meta("zone_color", color)
	node.set_meta("zone_name", zone_name)

	var sparse_overlay: bool = overlay_stride <= 1 or cell_index < 0 or cell_index % overlay_stride == 0
	var is_room_overlay: bool = node.has_meta("is_room") and bool(node.get_meta("is_room"))
	if not sparse_overlay and not is_room_overlay:
		return

	# Visual overlays: Colored light
	var light = OmniLight.new()
	light.light_color = color
	light.light_energy = 0.45
	light.omni_range = 8.0
	node.add_child(light)

	# Material tint (Water/Gas)
	if zone_name != "Air" and is_room_overlay:
		_apply_tint(node, color)

	# Particles for Gas
	if enable_zone_particles and zone_name == "Gas" and is_room_overlay:
		var particles = Particles.new()
		particles.name = "ZoneParticles_" + zone_name
		var mat = ParticlesMaterial.new()
		mat.emission_shape = ParticlesMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(1.5, 1.5, 1.5)
		mat.direction = Vector3(0, 1, 0)
		mat.spread = 180.0
		mat.gravity = Vector3(0, 0, 0)
		mat.initial_velocity = 0.2
		mat.color = color
		particles.process_material = mat
		particles.amount = 32
		particles.lifetime = 4.0
		node.add_child(particles)

func _apply_tint(node: Node, color: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance:
			for i in range(child.get_surface_material_count()):
				var mat = child.get_surface_material(i)
				if not mat:
					mat = child.mesh.surface_get_material(i) if child.mesh else null

				if mat is SpatialMaterial:
					var new_mat = mat.duplicate()
					new_mat.albedo_color = new_mat.albedo_color.linear_interpolate(color, 0.3)
					child.set_surface_material(i, new_mat)
		elif child is CSGCombiner:
			# Tinting CSG is trickier if it uses material at root
			var child_mat = child.get("material")
			if child_mat is SpatialMaterial:
				var new_child_mat = child_mat.duplicate()
				new_child_mat.albedo_color = new_child_mat.albedo_color.linear_interpolate(color, 0.3)
				child.set("material", new_child_mat)
		_apply_tint(child, color)

func _find_csg_material(node: Node) -> Material:
	var material = node.get("material")
	if material is Material:
		return material
	for child in node.get_children():
		var child_material = _find_csg_material(child)
		if child_material:
			return child_material
	return null

func _insert_valves(parent: Spatial = null) -> void:
	# Task 2: Strategic valves
	if not corridor_valves_enabled:
		return
	var valve_scene = _get_res(VALVE_PATH)
	if not valve_scene: return
	var root: Spatial = parent if parent != null else self

	var count = 0
	for child in root.get_children():
		var is_radial = false
		if "DuctRadial" in child.name:
			is_radial = true
		elif child.has_meta("variant_id") and child.get_meta("variant_id") == "W":
			if child.has_meta("rotation") and int(child.get_meta("rotation")) % 180 == 0:
				is_radial = true

		if is_radial:
			count += 1
			if count % 3 == 0:
				var valve = valve_scene.instance()
				root.add_child(valve)
				valve.name = "DuctGateValve_%d" % count
				var valve_axis: Vector3 = _valve_axis_for_child(child)
				var valve_transform: Transform = Transform(_basis_from_z_axis(valve_axis, child.transform.basis.y), child.translation)
				valve.transform = valve_transform
				valve.scale = Vector3.ONE * max(1.0, duct_radius / 2.0)

func _valve_axis_for_child(child: Spatial) -> Vector3:
	if axial_layout and child.has_meta("variant_id") and child.get_meta("variant_id") == "W":
		if child.has_meta("rotation") and int(child.get_meta("rotation")) % 180 == 0:
			return child.transform.basis.y.normalized()
	return child.transform.basis.z.normalized()

func _activate_collapse_triggers(parent: Spatial = null) -> void:
	# Task 3: Progressive collapse activation
	var root: Spatial = parent if parent != null else self
	for child in root.get_children():
		if child is Spatial:
			child.set_meta("collapse_active", true)
			if child.has_method("enable_collapse"):
				child.enable_collapse()
