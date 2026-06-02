extends Spatial
class_name ScaffoldStreamController

# FD-050.2: Chunk-based streaming scaffold generator

const GENERATOR_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")
const DIR_NORTH := 0
const DIR_EAST := 1
const DIR_SOUTH := 2
const DIR_WEST := 3
const PROP_COLLISION_LAYER := 64  # Godot layer 7
const PROP_COLLISION_MASK := 255

export(bool) var streaming_enabled := true
export(float, 20.0, 300.0) var load_radius := 120.0
export(float, 20.0, 400.0) var unload_radius := 180.0
export(float, 10.0, 200.0) var collision_radius := 40.0  # chunks inside get physics, outside are visual only
export(bool) var use_multimesh_lod := true
export(float, 0.0, 200.0) var full_detail_radius := 25.0
export(float, 0.0, 300.0) var lod1_radius := 65.0
export(float, 0.0, 200.0) var full_detail_prefetch_radius := 40.0
export(int, 0, 4) var max_full_detail_upgrades_per_frame := 1
export(float, 0.2, 1.0) var lod_cell_scale := 1.0
export(float, 0.02, 0.5) var lod_deck_thickness := 0.12
export(float, 1.0, 4.0) var lod_ramp_height_scale := 1.25
export(bool) var lod_full_detail_ramps := true
export(float, 0.02, 0.5) var lod_rail_thickness := 0.08
export(float, 0.0, 3.0) var lod_rail_height := 1.1
export(int, 3, 12) var lod_tube_segments := 6
export(Color) var frame_color := Color(0.18, 0.19, 0.21, 1.0)
export(Color) var rail_color := Color(0.18, 0.19, 0.21, 1.0)
export(Color) var grate_color := Color(0.42, 0.46, 0.50, 1.0)
export(bool) var lod_collision_enabled := true
export(float, 0.05, 1.0) var lod_collision_thickness := 0.25
export(int, 4, 24) var chunk_height := 8 setget set_chunk_height
export(int, 4, 32) var chunk_length := 12 setget set_chunk_length
export(float, 4.0, 30.0) var cell_size := 6.0
export(int) var global_seed := 42
export(int, 1, 64) var instances_per_frame := 8
export(int, 1, 16) var rebuilds_per_frame := 1
export(int, 1, 8) var max_chunk_requests_per_frame := 1
export(int, 1, 32) var max_pending_generation_jobs := 4
export(int, 0, 4) var prewarm_chunk_radius := 1
export(NodePath) var player_path: NodePath

export(int, 1, 2000) var max_wfc_retries := 24
export(bool) var require_single_component := false
export(int, 0, 128) var min_non_empty_cells := 8
export(int, 0, 32) var min_stairs_per_chunk := 0
export(int, 0, 32) var min_elevated_cells := 0
export(int, 0, 32) var min_empty_cells := 0
export(float, 0.0, 20.0) var min_height_span := 0.0
export(bool) var constrain_border_heights := false

export(float) var weight_W := 6.0
export(float) var weight_R := 5.0
export(float) var weight_P := 3.0
export(float) var weight_S := 8.0
export(float) var weight_C := 3.0
export(float) var weight_G := 0.5
export(float) var weight_X := 1.0
export(float) var weight_T := 2.0
export(float) var weight_E := 1.8
export(float) var weight_empty := 0.18

var _active_chunks: Dictionary = {}
var _pending_chunks: Dictionary = {}
var _chunk_modes: Dictionary = {}
var _chunk_grid_cache: Dictionary = {}
var _chunk_expected_full_count: Dictionary = {}
var _full_lod_cleanup_pending: Dictionary = {}
var _threaded: ScaffoldWFCThreaded = null
var _generator_ref = null
var _origin_initialized := false
var _lod_deck_mesh: CubeMesh = null
var _lod_ramp_mesh: ArrayMesh = null
var _lod_rail_mesh: CubeMesh = null
var _lod_material: SpatialMaterial = null
var _lod_rail_material: SpatialMaterial = null
var _lod_ramp_material: SpatialMaterial = null
var _lod_grate_material: SpatialMaterial = null

var _lod1_tube_mesh: CylinderMesh = null
var _lod1_grate_mesh: QuadMesh = null
var _lod2_deck_mesh: CubeMesh = null

func _ready() -> void:
	_build_lod_resources()
	_generator_ref = GENERATOR_SCRIPT.new()
	_generator_ref.grid_width = chunk_height
	_generator_ref.grid_depth = chunk_length
	_generator_ref.cell_size = cell_size
	_apply_generator_tweaks(_generator_ref)
	_generator_ref._setup_variants()

	_threaded = ScaffoldWFCThreaded.new()
	_threaded.instances_per_frame = instances_per_frame
	_threaded.rebuilds_per_frame = rebuilds_per_frame
	_threaded.max_pending_jobs = max_pending_generation_jobs
	add_child(_threaded)
	_threaded.connect("generation_done", self, "_on_chunk_generated")
	_threaded.connect("generation_failed", self, "_on_chunk_failed")

func _exit_tree() -> void:
	if _generator_ref != null and is_instance_valid(_generator_ref):
		_generator_ref.free()
	_generator_ref = null

func _process(_delta) -> void:
	if not streaming_enabled:
		return
	var player_pos = _get_player_position()
	if not _origin_initialized:
		_initialize_origin(player_pos)
	var player_chunk = _world_to_chunk(player_pos)

	var scan_radius = _chunk_scan_radius()
	_request_needed_chunks(player_pos, player_chunk, scan_radius, max_chunk_requests_per_frame)
	if prewarm_chunk_radius > 0:
		_request_needed_chunks(player_pos, player_chunk, prewarm_chunk_radius, max_pending_generation_jobs, false)

	var upgrades_left = max_full_detail_upgrades_per_frame
	for key in _active_chunks.keys():
		var world_center = _chunk_to_world_center(key)
		var center_dist = player_pos.distance_to(world_center)
		var footprint_dist = _distance_to_chunk_footprint(player_pos, key)
		if center_dist > unload_radius:
			_unload_chunk(key)
		else:
			var chunk_node = _active_chunks[key]
			_set_chunk_collision(chunk_node, footprint_dist <= collision_radius)

			var current_mode = _chunk_modes.get(key, "")
			var target_mode = _target_lod_mode(footprint_dist)

			if current_mode != target_mode:
				if target_mode == "full":
					if upgrades_left > 0:
						_upgrade_chunk_to_full_detail(key)
						upgrades_left -= 1
				else:
					_switch_to_lod_mode(key, target_mode)

	_cleanup_finished_full_detail_lods()

func _target_lod_mode(footprint_dist: float) -> String:
	if not use_multimesh_lod:
		return "full"
	if footprint_dist <= full_detail_radius:
		return "full"
	# Prefetch full detail if close
	if _full_detail_enabled() and footprint_dist <= full_detail_prefetch_radius:
		return "full"
	if footprint_dist <= lod1_radius:
		return "lod1"
	return "lod2"

func _switch_to_lod_mode(chunk_key: Vector2, mode: String) -> void:
	if not _active_chunks.has(chunk_key) or not _chunk_grid_cache.has(chunk_key):
		return
	var chunk_node = _active_chunks[chunk_key]
	if not is_instance_valid(chunk_node):
		return

	_chunk_modes[chunk_key] = mode
	_full_lod_cleanup_pending.erase(chunk_key) # Cancel any pending full detail cleanup

	_clear_chunk_visuals(chunk_node)

	var grid_data = _chunk_grid_cache[chunk_key]
	if mode == "lod1":
		_build_lod1_chunk(chunk_node, grid_data)
	elif mode == "lod2":
		_build_lod2_chunk(chunk_node, grid_data)

func _clear_chunk_visuals(chunk_node: Spatial) -> void:
	for child in chunk_node.get_children():
		# Keep collision
		if child.name == "LODCollision":
			continue
		child.queue_free()

func _initialize_origin(player_pos: Vector3) -> void:
	# Chunk (0,0) is anchored so its generated cell positions are centered on the
	# player's spawn. Later chunks use canonical global chunk coordinates.
	var chunk_w = float(chunk_height - 1) * cell_size
	var chunk_d = float(chunk_length - 1) * cell_size
	global_translation = Vector3(
		player_pos.x - chunk_w * 0.5,
		0.0,
		player_pos.z - chunk_d * 0.5
	)
	_origin_initialized = true

func _request_needed_chunks(player_pos: Vector3, player_chunk: Vector2, scan_radius: int, request_budget: int, respect_load_radius: bool = true) -> int:
	if request_budget <= 0:
		return 0
	var candidates = []
	var cx_min = int(player_chunk.x) - scan_radius
	var cx_max = int(player_chunk.x) + scan_radius
	var cz_min = int(player_chunk.y) - scan_radius
	var cz_max = int(player_chunk.y) + scan_radius

	for cx in range(cx_min, cx_max + 1):
		for cz in range(cz_min, cz_max + 1):
			var key = Vector2(cx, cz)
			if _active_chunks.has(key) or _pending_chunks.has(key):
				continue
			var world_center = _chunk_to_world_center(key)
			var center_dist = player_pos.distance_to(world_center)
			var footprint_dist = _distance_to_chunk_footprint(player_pos, key)
			if (not respect_load_radius) or footprint_dist <= load_radius:
				candidates.append({"key": key, "dist": center_dist})
	candidates.sort_custom(self, "_sort_chunk_candidates")
	var requested = 0
	for item in candidates:
		if requested >= request_budget:
			break
		if _pending_chunks.size() >= max_pending_generation_jobs:
			break
		_request_chunk(item.key)
		requested += 1
	return requested

func _sort_chunk_candidates(a: Dictionary, b: Dictionary) -> bool:
	return a.dist < b.dist

func set_chunk_height(value: int) -> void:
	chunk_height = max(1, value)

func set_chunk_length(value: int) -> void:
	chunk_length = max(1, value)

func _get_player_position() -> Vector3:
	if player_path and not player_path.is_empty():
		var player = get_node_or_null(player_path)
		if player:
			return player.global_translation
	# Fallback: find a node in group "player"
	var players = get_tree().get_nodes_in_group("player")
	if not players.empty():
		return players[0].global_translation
	return Vector3.ZERO

func _world_to_chunk(world_pos: Vector3) -> Vector2:
	var local_pos = global_transform.affine_inverse().xform(world_pos)
	var chunk_world_w = _chunk_step_x()
	var chunk_world_d = _chunk_step_z()
	return Vector2(
		floor(local_pos.x / chunk_world_w),
		floor(local_pos.z / chunk_world_d)
	)

func _chunk_to_world_center(chunk_key: Vector2) -> Vector3:
	var chunk_world_w = _chunk_step_x()
	var chunk_world_d = _chunk_step_z()
	var cell_center_w = float(chunk_height - 1) * cell_size * 0.5
	var cell_center_d = float(chunk_length - 1) * cell_size * 0.5
	var local_center = Vector3(
		chunk_key.x * chunk_world_w + cell_center_w,
		0.0,
		chunk_key.y * chunk_world_d + cell_center_d
	)
	return global_transform.xform(local_center)

func _chunk_to_local_origin(chunk_key: Vector2) -> Vector3:
	return Vector3(
		chunk_key.x * _chunk_step_x(),
		0.0,
		chunk_key.y * _chunk_step_z()
	)

func _distance_to_chunk_footprint(world_pos: Vector3, chunk_key: Vector2) -> float:
	var local_pos = global_transform.affine_inverse().xform(world_pos)
	var origin = _chunk_to_local_origin(chunk_key)
	var max_x = origin.x + float(chunk_height - 1) * cell_size
	var max_z = origin.z + float(chunk_length - 1) * cell_size
	var closest_x = clamp(local_pos.x, origin.x, max_x)
	var closest_z = clamp(local_pos.z, origin.z, max_z)
	return Vector2(local_pos.x - closest_x, local_pos.z - closest_z).length()

func _chunk_step_x() -> float:
	return max(1.0, float(chunk_height - 1)) * cell_size

func _chunk_step_z() -> float:
	return max(1.0, float(chunk_length - 1)) * cell_size

func _full_detail_upgrade_radius() -> float:
	return max(full_detail_radius, full_detail_prefetch_radius)

func _full_detail_enabled() -> bool:
	return _full_detail_upgrade_radius() > 0.001

func _request_chunk(chunk_key: Vector2) -> void:
	if _pending_chunks.size() >= max_pending_generation_jobs:
		return
	_pending_chunks[chunk_key] = true
	var chunk_seed = _chunk_seed(chunk_key)
	var params = {
		"grid_width": chunk_height,
		"grid_depth": chunk_length,
		"cell_size": cell_size,
		"seed": chunk_seed,
		"max_wfc_retries": max_wfc_retries,
		"require_single_component": require_single_component,
		"min_non_empty_cells": min_non_empty_cells,
		"min_stairs_per_map": min_stairs_per_chunk,
		"min_elevated_cells": min_elevated_cells,
		"min_empty_cells": min_empty_cells,
		"min_height_span": min_height_span,
		"constrain_border_heights": constrain_border_heights,
		"weight_W": weight_W,
		"weight_R": weight_R,
		"weight_P": weight_P,
		"weight_S": weight_S,
		"weight_C": weight_C,
		"weight_G": weight_G,
		"weight_X": weight_X,
		"weight_T": weight_T,
		"weight_E": weight_E,
		"weight_empty": weight_empty
	}
	_threaded.request_grid(chunk_key, params)

func _build_lod_resources() -> void:
	_lod_deck_mesh = CubeMesh.new()
	_lod_deck_mesh.size = Vector3.ONE
	_lod_ramp_mesh = _make_lod_ramp_mesh()
	_lod_rail_mesh = CubeMesh.new()
	_lod_rail_mesh.size = Vector3.ONE

	_lod1_tube_mesh = CylinderMesh.new()
	_lod1_tube_mesh.radial_segments = lod_tube_segments
	_lod1_tube_mesh.top_radius = 0.07 # Match SteelGratePlatform default tube_radius
	_lod1_tube_mesh.bottom_radius = 0.07

	_lod1_grate_mesh = QuadMesh.new()

	_lod2_deck_mesh = CubeMesh.new()
	_lod2_deck_mesh.size = Vector3.ONE

	_lod_material = SpatialMaterial.new()
	_lod_material.albedo_color = frame_color
	_lod_material.metallic = 0.12
	_lod_material.roughness = 0.96

	_lod_rail_material = _lod_material.duplicate()
	_lod_rail_material.albedo_color = rail_color

	_lod_ramp_material = _lod_material.duplicate()
	_lod_ramp_material.albedo_color = Color(0.55, 0.50, 0.38, 1.0)
	_lod_ramp_material.params_cull_mode = SpatialMaterial.CULL_DISABLED

	_lod_grate_material = load("res://textures/trenchbroom/steel_grate_platform.tres").duplicate(true)
	if _lod_grate_material is SpatialMaterial:
		var brightness = 0.72 # Match SteelGratePlatform default grate_brightness
		_lod_grate_material.albedo_color = Color(
			grate_color.r * brightness,
			grate_color.g * brightness,
			grate_color.b * brightness,
			grate_color.a
		)
		_lod_grate_material.metallic = 0.04
		_lod_grate_material.roughness = 0.98

func _make_lod_ramp_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom_y = -0.05
	var low_l = Vector3(-0.5, 0.0, -0.5)
	var low_r = Vector3(0.5, 0.0, -0.5)
	var high_r = Vector3(0.5, 1.0, 0.5)
	var high_l = Vector3(-0.5, 1.0, 0.5)
	var base_low_l = Vector3(-0.5, bottom_y, -0.5)
	var base_low_r = Vector3(0.5, bottom_y, -0.5)
	var base_high_r = Vector3(0.5, bottom_y, 0.5)
	var base_high_l = Vector3(-0.5, bottom_y, 0.5)
	_add_lod_ramp_face(st, low_l, low_r, high_r, high_l)
	_add_lod_ramp_face(st, base_high_l, base_high_r, base_low_r, base_low_l)
	_add_lod_ramp_face(st, base_low_l, low_l, high_l, base_high_l)
	_add_lod_ramp_face(st, base_high_r, high_r, low_r, base_low_r)
	_add_lod_ramp_face(st, base_low_l, base_low_r, low_r, low_l)
	_add_lod_ramp_face(st, base_high_l, high_l, high_r, base_high_r)
	# Two raised side strips make the continuous slope readable without turning it into stairs.
	var strip_w = 0.08
	var strip_h = 0.08
	for side_x in [-0.5 + strip_w * 0.5, 0.5 - strip_w * 0.5]:
		var x0 = side_x - strip_w * 0.5
		var x1 = side_x + strip_w * 0.5
		_add_lod_ramp_face(st,
			Vector3(x0, strip_h, -0.48),
			Vector3(x1, strip_h, -0.48),
			Vector3(x1, 1.0 + strip_h, 0.48),
			Vector3(x0, 1.0 + strip_h, 0.48)
		)
	_add_lod_ramp_face(st, Vector3(-0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, -0.5), Vector3(0.5, bottom_y, 0.5), Vector3(-0.5, bottom_y, 0.5))
	st.generate_normals()
	st.commit(mesh)
	return mesh

func _add_lod_ramp_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

func _chunk_seed(chunk_key: Vector2) -> int:
	# Deterministic per-chunk seed derived from global_seed and chunk coords
	return int(chunk_key.x) * 73856093 ^ int(chunk_key.y) * 19349663 ^ global_seed

func _on_chunk_generated(chunk_key, grid_data: Array) -> void:
	if not _pending_chunks.has(chunk_key):
		return
	_pending_chunks.erase(chunk_key)

	var chunk_node = Spatial.new()
	chunk_node.name = "Chunk_%d_%d" % [int(chunk_key.x), int(chunk_key.y)]
	add_child(chunk_node)
	_active_chunks[chunk_key] = chunk_node
	_chunk_grid_cache[chunk_key] = grid_data
	_chunk_expected_full_count[chunk_key] = _count_full_detail_cells(grid_data)

	chunk_node.translation = _chunk_to_local_origin(chunk_key)
	var player_pos = _get_player_position()
	var footprint_dist = _distance_to_chunk_footprint(player_pos, chunk_key)

	var mode = _target_lod_mode(footprint_dist)
	_chunk_modes[chunk_key] = mode

	if mode == "full":
		_threaded.enqueue_grid_for_instancing(
			chunk_node, grid_data,
			chunk_height, chunk_length, cell_size,
			_generator_ref, Vector3.ZERO
		)
	elif mode == "lod1":
		_build_lod1_chunk(chunk_node, grid_data)
	else:
		_build_lod2_chunk(chunk_node, grid_data)

	_set_chunk_collision(chunk_node, footprint_dist <= collision_radius)

func _on_chunk_failed(chunk_key) -> void:
	_pending_chunks.erase(chunk_key)
	push_warning("[ScaffoldStream] Chunk generation failed: %s" % str(chunk_key))

func _set_chunk_collision(chunk_node: Spatial, enabled: bool) -> void:
	var layer = PROP_COLLISION_LAYER if enabled else 0
	var mask = PROP_COLLISION_MASK if enabled else 0
	for module in chunk_node.get_children():
		if module is StaticBody:
			module.collision_layer = layer
			module.collision_mask = mask
			continue
		# SteelGratePlatform creates its StaticBody as a child named "StaticBody"
		var body = module.get_node_or_null("StaticBody")
		if body and body is StaticBody:
			body.collision_layer = layer
			body.collision_mask = mask

func _upgrade_chunk_to_full_detail(chunk_key: Vector2) -> void:
	if not _active_chunks.has(chunk_key):
		return
	if not _chunk_grid_cache.has(chunk_key):
		return
	var chunk_node = _active_chunks[chunk_key]
	if not is_instance_valid(chunk_node):
		return
	_chunk_modes[chunk_key] = "full"
	_full_lod_cleanup_pending[chunk_key] = true
	_threaded.enqueue_grid_for_instancing(
		chunk_node, _chunk_grid_cache[chunk_key],
		chunk_height, chunk_length, cell_size,
		_generator_ref, Vector3.ZERO
	)

func _build_lod1_chunk(chunk_node: Spatial, grid_data: Array) -> void:
	var tube_transforms = []
	var rail_tube_transforms = []
	var grate_transforms = []
	var collision_shapes = []

	var tube_radius = 0.07 # Match SteelGratePlatform

	for y in range(chunk_length):
		for x in range(chunk_height):
			var state = grid_data[y * chunk_height + x]
			var v = _state_variant(state)
			if state == null or v == null or _variant_id(v) == "EMPTY":
				continue

			var vid = _variant_id(v)
			var base_pos = Vector3(x * cell_size, _state_base_height(state), y * cell_size)
			var plat_w = _lane_width() if (vid == "W" or vid == "R" or vid == "G" or vid == "S") else cell_size
			var plat_d = cell_size

			# Deck grates
			var front_top_y = _variant_port_heights(v)[DIR_NORTH]
			var back_top_y = _variant_port_heights(v)[DIR_SOUTH]
			var slope_angle = - atan2(back_top_y - front_top_y, plat_d)
			var slope_scale = 1.0 / max(cos(slope_angle), 0.02)

			var grate_xf = Transform()
			grate_xf.origin = base_pos + Vector3(0, (front_top_y + back_top_y) * 0.5 - 0.015, 0)
			grate_xf.basis = Basis(Vector3.RIGHT, slope_angle).scaled(Vector3(plat_w, 1.0, plat_d * slope_scale))
			grate_xf.basis = grate_xf.basis.rotated(Vector3.RIGHT, -PI*0.5)
			grate_transforms.append(grate_xf)

			# Legs & Frame Beams
			var hw = plat_w * 0.5
			var hd = plat_d * 0.5
			var corners = [
				Vector3(-hw + tube_radius, front_top_y - tube_radius, -hd + tube_radius),
				Vector3(hw - tube_radius, front_top_y - tube_radius, -hd + tube_radius),
				Vector3(-hw + tube_radius, back_top_y - tube_radius, hd - tube_radius),
				Vector3(hw - tube_radius, back_top_y - tube_radius, hd - tube_radius)
			]

			# Legs
			for c in corners:
				var top = base_pos + c
				var bottom = Vector3(top.x, global_translation.y, top.z) # Reach "ground"
				tube_transforms.append(_tube_between_transform(bottom, top))

			# Beams
			tube_transforms.append(_tube_between_transform(base_pos + corners[0], base_pos + corners[1]))
			tube_transforms.append(_tube_between_transform(base_pos + corners[2], base_pos + corners[3]))
			tube_transforms.append(_tube_between_transform(base_pos + corners[0], base_pos + corners[2]))
			tube_transforms.append(_tube_between_transform(base_pos + corners[1], base_pos + corners[3]))

			# Rails
			_append_lod1_rails(rail_tube_transforms, base_pos, v, plat_w, plat_d)

			if lod_collision_enabled:
				collision_shapes.append(_lod_collision_transform(v, base_pos, plat_w, plat_d))

	_add_lod_multimesh(chunk_node, "LOD1Frames", _lod1_tube_mesh, tube_transforms, _lod_material)
	_add_lod_multimesh(chunk_node, "LOD1Rails", _lod1_tube_mesh, rail_tube_transforms, _lod_rail_material)
	_add_lod_multimesh(chunk_node, "LOD1Grates", _lod1_grate_mesh, grate_transforms, _lod_grate_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _append_lod1_rails(out: Array, base_pos: Vector3, v, plat_w: float, plat_d: float) -> void:
	var connections = _variant_connections(v)
	var heights = _variant_port_heights(v)
	var tube_radius = 0.07
	var rh = lod_rail_height

	# Logic for rails simplified: if no connection, add rail.
	# SteelGratePlatform: front = -Z, back = +Z, left = -X, right = +X
	var hw = plat_w * 0.5
	var hd = plat_d * 0.5

	var sides = [
		{"dir": DIR_NORTH, "start": Vector3(-hw, heights[DIR_NORTH], -hd), "end": Vector3(hw, heights[DIR_NORTH], -hd)},
		{"dir": DIR_SOUTH, "start": Vector3(-hw, heights[DIR_SOUTH], hd), "end": Vector3(hw, heights[DIR_SOUTH], hd)},
		{"dir": DIR_WEST, "start": Vector3(-hw, heights[DIR_WEST], -hd), "end": Vector3(-hw, heights[DIR_WEST], hd)},
		{"dir": DIR_EAST, "start": Vector3(hw, heights[DIR_EAST], -hd), "end": Vector3(hw, heights[DIR_EAST], hd)}
	]

	for side in sides:
		if not connections[side.dir]:
			var s = base_pos + side.start
			var e = base_pos + side.end
			# Rail top
			out.append(_tube_between_transform(s + Vector3.UP * rh, e + Vector3.UP * rh))
			# Rail mid
			out.append(_tube_between_transform(s + Vector3.UP * rh * 0.5, e + Vector3.UP * rh * 0.5))
			# Posts
			out.append(_tube_between_transform(s, s + Vector3.UP * rh))
			out.append(_tube_between_transform(e, e + Vector3.UP * rh))

func _tube_between_transform(start: Vector3, end: Vector3) -> Transform:
	var dir = end - start
	var length = dir.length()
	if length <= 0.001:
		return Transform()

	var xf = Transform(_basis_from_y_axis(dir.normalized()), (start + end) * 0.5)
	xf.basis = xf.basis.scaled(Vector3(1.0, length, 1.0))
	return xf

func _basis_from_y_axis(y_axis: Vector3) -> Basis:
	var up = y_axis.normalized()
	var tangent = Vector3.FORWARD if abs(up.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var x_axis = tangent.cross(up).normalized()
	var z_axis = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis)

func _build_lod2_chunk(chunk_node: Spatial, grid_data: Array) -> void:
	var deck_transforms = []
	var leg_transforms = []
	var collision_shapes = []

	for y in range(chunk_length):
		for x in range(chunk_height):
			var state = grid_data[y * chunk_height + x]
			var v = _state_variant(state)
			if state == null or v == null or _variant_id(v) == "EMPTY":
				continue

			var vid = _variant_id(v)
			var plat_w = _lane_width() if (vid == "W" or vid == "R" or vid == "G" or vid == "S") else cell_size
			var plat_d = cell_size
			var base_pos = Vector3(x * cell_size, _state_base_height(state), y * cell_size)

			var front_top_y = _variant_port_heights(v)[DIR_NORTH]
			var back_top_y = _variant_port_heights(v)[DIR_SOUTH]

			# Deck simplified to a box
			var deck_xf = Transform()
			deck_xf.origin = base_pos + Vector3(0, (front_top_y + back_top_y) * 0.5 - 0.05, 0)
			var slope_angle = - atan2(back_top_y - front_top_y, plat_d)
			var slope_scale = 1.0 / max(cos(slope_angle), 0.02)
			deck_xf.basis = Basis(Vector3.RIGHT, slope_angle).scaled(Vector3(plat_w, 0.1, plat_d * slope_scale))
			deck_transforms.append(deck_xf)

			# 4 Legs as stylized cubes
			var hw = plat_w * 0.4
			var hd = plat_d * 0.4
			var leg_positions = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(-hw, hd), Vector2(hw, hd)]
			for lp in leg_positions:
				var leg_h = base_pos.y + (front_top_y if lp.y < 0 else back_top_y)
				var leg_xf = Transform()
				leg_xf.origin = Vector3(base_pos.x + lp.x, leg_h * 0.5, base_pos.z + lp.y)
				leg_xf.basis = Basis().scaled(Vector3(0.15, leg_h, 0.15))
				leg_transforms.append(leg_xf)

			if lod_collision_enabled:
				collision_shapes.append(_lod_collision_transform(v, base_pos, plat_w, plat_d))

	_add_lod_multimesh(chunk_node, "LOD2Decks", _lod2_deck_mesh, deck_transforms, _lod_material)
	_add_lod_multimesh(chunk_node, "LOD2Legs", _lod2_deck_mesh, leg_transforms, _lod_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _instance_lod_full_detail_cell(chunk_node: Spatial, x: int, y: int, state, v) -> void:
	if _generator_ref == null or not is_instance_valid(_generator_ref):
		return
	var vid = _variant_id(v)
	if not _generator_ref.modules.has(vid) or _generator_ref.modules[vid] == null:
		return
	var inst = _generator_ref.modules[vid].instance()
	var deck_local_y = inst.platform_height
	var base_height = _state_base_height(state)
	inst.translation = Vector3(x * cell_size, base_height - deck_local_y, y * cell_size)
	inst.rotation_degrees.y = -_variant_rotation(v)
	inst.set("support_base_local_y", deck_local_y - base_height)
	_generator_ref._apply_local_dims(inst, _generator_ref._lane_width(), cell_size)
	_generator_ref._apply_port_heights_to_front_back(inst, v)
	_generator_ref._apply_rails_from_connections(inst, v)
	_generator_ref._apply_opening_widths_from_connections(inst, v)
	chunk_node.add_child(inst)
	if inst.has_method("_rebuild"):
		inst.call("_rebuild")

func _cleanup_finished_full_detail_lods() -> void:
	for key in _full_lod_cleanup_pending.keys():
		if not _active_chunks.has(key):
			_full_lod_cleanup_pending.erase(key)
			continue
		var chunk_node = _active_chunks[key]
		if not is_instance_valid(chunk_node):
			_full_lod_cleanup_pending.erase(key)
			continue
		var expected = int(_chunk_expected_full_count.get(key, 0))
		if expected <= 0:
			_remove_lod_children(chunk_node)
			_full_lod_cleanup_pending.erase(key)
			continue
		if _count_full_detail_children(chunk_node) >= expected:
			_remove_lod_children(chunk_node)
			_full_lod_cleanup_pending.erase(key)

func _count_full_detail_cells(grid_data: Array) -> int:
	var count = 0
	for state in grid_data:
		var v = _state_variant(state)
		if state != null and v != null and _variant_id(v) != "EMPTY":
			count += 1
	return count

func _count_full_detail_children(chunk_node: Spatial) -> int:
	var count = 0
	for child in chunk_node.get_children():
		if child.name.begins_with("LOD"):
			continue
		if child is Spatial:
			count += 1
	return count

func _remove_lod_children(chunk_node: Spatial) -> void:
	for child in chunk_node.get_children():
		if child.name.begins_with("LOD"):
			child.queue_free()

func _add_lod_collision(chunk_node: Spatial, transforms: Array) -> void:
	if transforms.empty():
		return
	var body = StaticBody.new()
	body.name = "LODCollision"
	body.collision_layer = 0
	body.collision_mask = 0
	for i in range(transforms.size()):
		var spec = transforms[i]
		var shape = BoxShape.new()
		if typeof(spec) == TYPE_DICTIONARY:
			shape.extents = spec.get("extents", Vector3(0.5, 0.5, 0.5))
		else:
			shape.extents = Vector3(0.5, 0.5, 0.5)
		var col = CollisionShape.new()
		col.name = "LODDeckCollision_%d" % i
		col.shape = shape
		col.transform = spec.get("transform", Transform()) if typeof(spec) == TYPE_DICTIONARY else spec
		body.add_child(col)
	chunk_node.add_child(body)

func _lane_width() -> float:
	return clamp(cell_size * 0.32, 2.5, 4.5)

func _dir_from_local_side(rot: int, side: String) -> int:
	var r = int(posmod(rot, 360))
	match side:
		"front":
			if r == 0: return DIR_NORTH
			if r == 90: return DIR_EAST
			if r == 180: return DIR_SOUTH
			return DIR_WEST
		"back":
			return _opposite_dir(_dir_from_local_side(rot, "front"))
		"left":
			if r == 0: return DIR_WEST
			if r == 90: return DIR_NORTH
			if r == 180: return DIR_EAST
			return DIR_SOUTH
		"right":
			return _opposite_dir(_dir_from_local_side(rot, "left"))
	return DIR_NORTH

func _opposite_dir(dir: int) -> int:
	if dir == DIR_NORTH: return DIR_SOUTH
	if dir == DIR_SOUTH: return DIR_NORTH
	if dir == DIR_EAST: return DIR_WEST
	return DIR_EAST

func _lod_collision_transform(v, base_pos: Vector3, plat_w: float, plat_d: float) -> Dictionary:
	var rot = _variant_rotation(v)
	var world_heights = _variant_port_heights(v)
	var front_dir = _dir_from_local_side(rot, "front")
	var back_dir = _dir_from_local_side(rot, "back")
	var local_front_h = world_heights[front_dir]
	var local_back_h = world_heights[back_dir]

	var slope_angle = - atan2(local_back_h - local_front_h, plat_d)
	var slope_scale = 1.0 / max(cos(slope_angle), 0.02)

	var base_xf = Transform(Basis(Vector3.UP, deg2rad(-rot)), base_pos)
	var deck_center_y = (local_front_h + local_back_h) * 0.5

	var xf = base_xf * Transform(
		Basis(Vector3.RIGHT, slope_angle),
		Vector3(0, deck_center_y - lod_collision_thickness * 0.5, 0)
	)

	return {
		"transform": xf,
		"extents": Vector3(plat_w, lod_collision_thickness, plat_d * slope_scale) * 0.5
	}

func _add_lod_multimesh(chunk_node: Spatial, node_name: String, mesh: Mesh, transforms: Array, material: Material = null) -> void:
	if transforms.empty():
		return
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_NONE
	mm.custom_data_format = MultiMesh.CUSTOM_DATA_NONE
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var inst = MultiMeshInstance.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = _lod_material if material == null else material
	chunk_node.add_child(inst)

func _state_variant(state):
	if state == null:
		return null
	if typeof(state) == TYPE_DICTIONARY:
		return state.get("variant", null)
	return state.variant

func _state_base_height(state) -> float:
	if typeof(state) == TYPE_DICTIONARY:
		return float(state.get("base_height", 0.0))
	return state.base_height

func _variant_id(v) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_DICTIONARY:
		return String(v.get("id", ""))
	return v.id

func _variant_rotation(v) -> int:
	if v == null:
		return 0
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("rotation", 0))
	return v.rotation

func _variant_connections(v) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_DICTIONARY:
		return v.get("connections", [])
	return v.connections

func _variant_port_heights(v) -> Array:
	if v == null:
		return []
	if typeof(v) == TYPE_DICTIONARY:
		return v.get("port_heights", [])
	return v.port_heights

func _unload_chunk(chunk_key: Vector2) -> void:
	if not _active_chunks.has(chunk_key):
		return
	var node = _active_chunks[chunk_key]
	_active_chunks.erase(chunk_key)
	_chunk_modes.erase(chunk_key)
	_chunk_grid_cache.erase(chunk_key)
	_chunk_expected_full_count.erase(chunk_key)
	_full_lod_cleanup_pending.erase(chunk_key)
	node.queue_free()

func _chunk_scan_radius() -> int:
	var min_chunk_side = max(1.0, min(_chunk_step_x(), _chunk_step_z()))
	return int(clamp(ceil(load_radius / min_chunk_side) + 1.0, 1.0, 8.0))

func _apply_generator_tweaks(gen) -> void:
	gen.max_wfc_retries = max_wfc_retries
	gen.require_single_component = require_single_component
	gen.min_stairs_per_map = min_stairs_per_chunk
	gen.min_elevated_cells = min_elevated_cells
	gen.min_empty_cells = min_empty_cells
	gen.min_height_span = min_height_span
	gen.constrain_border_heights = constrain_border_heights
	gen.weight_W = weight_W
	gen.weight_R = weight_R
	gen.weight_P = weight_P
	gen.weight_S = weight_S
	gen.weight_C = weight_C
	gen.weight_G = weight_G
	gen.weight_X = weight_X
	gen.weight_T = weight_T
	gen.weight_E = weight_E
	gen.weight_empty = weight_empty

func get_debug_summary() -> Dictionary:
	return {
		"streaming_enabled": streaming_enabled,
		"chunk_height_cells": chunk_height,
		"chunk_length_cells": chunk_length,
		"chunk_world_height_x": _chunk_step_x(),
		"chunk_world_length_z": _chunk_step_z(),
		"active_chunks": _active_chunks.size(),
		"pending_chunks": _pending_chunks.size(),
		"instances_per_frame": instances_per_frame,
		"max_wfc_retries": max_wfc_retries,
		"min_non_empty_cells": min_non_empty_cells
	}
