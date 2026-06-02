extends Spatial
class_name ScaffoldStreamController

# FD-050.2: Chunk-based streaming scaffold generator

const GENERATOR_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")
const MST_GENERATOR_SCRIPT = preload("res://core_v2/systems/ScaffoldMSTGenerator.gd")
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
export(bool) var lod_supports_enabled := true
export(float, 0.04, 0.6) var lod_support_thickness := 0.16
export(int, 3, 12) var lod_tube_segments := 6
export(Color) var frame_color := Color(0.18, 0.19, 0.21, 1.0)
export(Color) var rail_color := Color(0.18, 0.19, 0.21, 1.0)
export(Color) var grate_color := Color(0.42, 0.46, 0.50, 1.0)
export(bool) var lod_collision_enabled := true
export(float, 0.05, 1.0) var lod_collision_thickness := 0.25
export(float, 0.1, 5.0) var lod_platform_height := 1.6  # Must match SteelGratePlatform.platform_height
export(int, 4, 24) var chunk_height := 8 setget set_chunk_height
export(int, 4, 32) var chunk_length := 12 setget set_chunk_length
export(float, 4.0, 30.0) var cell_size := 6.0
export(bool) var use_mst_generator := false
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
var _chunk_expected_full_count: Dictionary = {}  # unused, kept for compatibility
var _full_lod_cleanup_pending: Dictionary = {}
var _mst_build_queue: Array = []  # [{key, grid_data}] waiting to be built, one per frame
var _chunk_collision_state: Dictionary = {}  # chunk_key -> bool, avoids per-frame child iteration
var _threaded: ScaffoldWFCThreaded = null
var _generator_ref = null
var _wfc_module_ref = null  # WFCGenerator kept as asset library when use_mst_generator is true
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
	if use_mst_generator:
		_generator_ref = MST_GENERATOR_SCRIPT.new()
		_generator_ref.grid_width = chunk_height
		_generator_ref.grid_depth = chunk_length
		_generator_ref.cell_size = cell_size
		# _wfc_module_ref loaded lazily on first full-detail request
	else:
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
	_threaded.connect("instancing_done", self, "_on_chunk_instancing_done")

func _exit_tree() -> void:
	if _generator_ref != null and is_instance_valid(_generator_ref):
		if not use_mst_generator:
			_generator_ref.free()
	_generator_ref = null
	if _wfc_module_ref != null and is_instance_valid(_wfc_module_ref):
		_wfc_module_ref.free()
	_wfc_module_ref = null

func _process(_delta) -> void:
	if not streaming_enabled:
		return
	var player_pos = _get_player_position()
	if not _origin_initialized:
		_initialize_origin(player_pos)
	var player_chunk = _world_to_chunk(player_pos)

	var scan_radius = _chunk_scan_radius()
	if use_mst_generator:
		# Drain build queue first, then only enqueue new grids if queue is empty
		# This prevents unbounded queue growth and keeps frame time predictable
		if not _mst_build_queue.empty():
			var frame_start = OS.get_ticks_usec()
			while not _mst_build_queue.empty():
				var job = _mst_build_queue.pop_front()
				_on_chunk_generated(job.key, job.grid)
				if (OS.get_ticks_usec() - frame_start) / 1000.0 >= 8.0:
					break
		else:
			_request_needed_chunks(player_pos, player_chunk, scan_radius, max_chunk_requests_per_frame)
			if prewarm_chunk_radius > 0:
				_request_needed_chunks(player_pos, player_chunk, prewarm_chunk_radius, max_pending_generation_jobs, false)
	else:
		_request_needed_chunks(player_pos, player_chunk, scan_radius, max_chunk_requests_per_frame)
		if prewarm_chunk_radius > 0:
			_request_needed_chunks(player_pos, player_chunk, prewarm_chunk_radius, max_pending_generation_jobs, false)

	var local_player_pos = global_transform.affine_inverse().xform(player_pos)
	var upgrades_left = max_full_detail_upgrades_per_frame
	for key in _active_chunks.keys():
		var world_center = _chunk_to_world_center(key)
		var center_dist = player_pos.distance_to(world_center)
		var footprint_dist = _distance_to_chunk_footprint_local(local_player_pos, key)
		if center_dist > unload_radius:
			_unload_chunk(key)
		else:
			var chunk_node = _active_chunks[key]
			var want_collision = footprint_dist <= collision_radius
			if _chunk_collision_state.get(key) != want_collision:
				_set_chunk_collision(chunk_node, want_collision)
				_chunk_collision_state[key] = want_collision

			var current_mode = _chunk_modes.get(key, "")
			var target_mode = _target_lod_mode(footprint_dist, current_mode)

			if current_mode != target_mode:
				if target_mode == "full":
					if upgrades_left > 0:
						_upgrade_chunk_to_full_detail(key)
						upgrades_left -= 1
				else:
					_switch_to_lod_mode(key, target_mode)

	_cleanup_finished_full_detail_lods()

func _target_lod_mode(footprint_dist: float, current_mode: String = "") -> String:
	if not use_multimesh_lod:
		return "full"
	# Hysteresis: upgrade at the export radius, downgrade at +10% to avoid oscillation.
	var lod1_out = lod1_radius * 1.10
	var full_out = full_detail_radius * 1.10
	var prefetch_out = full_detail_prefetch_radius * 1.10

	match current_mode:
		"full":
			if footprint_dist <= full_out:
				return "full"
			if _full_detail_enabled() and footprint_dist <= prefetch_out:
				return "full"
			if footprint_dist <= lod1_out:
				return "lod1"
			return "lod2"
		"lod1":
			if _full_detail_enabled() and footprint_dist <= full_detail_radius:
				return "full"
			if _full_detail_enabled() and footprint_dist <= full_detail_prefetch_radius:
				return "full"
			if footprint_dist <= lod1_out:
				return "lod1"
			return "lod2"
		_:  # lod2 or "" (first assignment)
			if _full_detail_enabled() and footprint_dist <= full_detail_radius:
				return "full"
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
	_full_lod_cleanup_pending.erase(chunk_key)
	_chunk_collision_state.erase(chunk_key)
	_threaded.cancel_instancing_for(chunk_node)

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
	var local_player_pos = global_transform.affine_inverse().xform(player_pos)
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
			var footprint_dist = _distance_to_chunk_footprint_local(local_player_pos, key)
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
	chunk_height = int(max(1, value))

func set_chunk_length(value: int) -> void:
	chunk_length = int(max(1, value))

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
	return _distance_to_chunk_footprint_local(global_transform.affine_inverse().xform(world_pos), chunk_key)

func _distance_to_chunk_footprint_local(local_pos: Vector3, chunk_key: Vector2) -> float:
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

func _ensure_wfc_module_ref() -> void:
	if _wfc_module_ref != null:
		return
	_wfc_module_ref = GENERATOR_SCRIPT.new()
	_wfc_module_ref.grid_width = chunk_height
	_wfc_module_ref.grid_depth = chunk_length
	_wfc_module_ref.cell_size = cell_size
	_apply_generator_tweaks(_wfc_module_ref)
	_wfc_module_ref._setup_variants()

func _request_chunk(chunk_key: Vector2) -> void:
	var chunk_seed = _chunk_seed(chunk_key)
	if use_mst_generator:
		# MST generates in <1ms synchronously, but visual build is deferred one-per-frame
		_generator_ref.apply_params({"grid_width": chunk_height, "grid_depth": chunk_length, "cell_size": cell_size})
		var grid = _generator_ref.generate_grid_data(chunk_seed)
		_pending_chunks[chunk_key] = true
		_mst_build_queue.append({"key": chunk_key, "grid": grid})
		return
	if _pending_chunks.size() >= max_pending_generation_jobs:
		return
	_pending_chunks[chunk_key] = true
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
		"weight_empty": weight_empty,
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
	var plate_t = 0.05
	var low_l = Vector3(-0.5, 0.0, -0.5)
	var low_r = Vector3(0.5, 0.0, -0.5)
	var high_r = Vector3(0.5, 1.0, 0.5)
	var high_l = Vector3(-0.5, 1.0, 0.5)
	var base_low_l = low_l - Vector3.UP * plate_t
	var base_low_r = low_r - Vector3.UP * plate_t
	var base_high_r = high_r - Vector3.UP * plate_t
	var base_high_l = high_l - Vector3.UP * plate_t
	_add_lod_ramp_face(st, low_l, low_r, high_r, high_l)
	_add_lod_ramp_face(st, base_high_l, base_high_r, base_low_r, base_low_l)
	_add_lod_ramp_face(st, base_low_l, low_l, high_l, base_high_l)
	_add_lod_ramp_face(st, base_high_r, high_r, low_r, base_low_r)
	_add_lod_ramp_face(st, base_low_l, base_low_r, low_r, low_l)
	_add_lod_ramp_face(st, base_high_l, high_l, high_r, base_high_r)
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

	chunk_node.translation = _chunk_to_local_origin(chunk_key)
	var player_pos = _get_player_position()
	var footprint_dist = _distance_to_chunk_footprint(player_pos, chunk_key)

	var mode = _target_lod_mode(footprint_dist)
	_chunk_modes[chunk_key] = mode

	if mode == "full":
		# Build LOD1 immediately as visual placeholder while assets stream in
		_build_lod1_chunk(chunk_node, grid_data)
		_full_lod_cleanup_pending[chunk_key] = true
		if use_mst_generator:
			_ensure_wfc_module_ref()
		var module_ref = _wfc_module_ref if use_mst_generator else _generator_ref
		_threaded.enqueue_grid_for_instancing(
			chunk_node, grid_data,
			chunk_height, chunk_length, cell_size,
			module_ref, Vector3.ZERO
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
	var prev_mode = _chunk_modes.get(chunk_key, "")
	_chunk_modes[chunk_key] = "full"
	_full_lod_cleanup_pending[chunk_key] = true
	# Ensure a LOD1 placeholder is visible while assets stream in
	if prev_mode != "lod1":
		_clear_chunk_visuals(chunk_node)
		_build_lod1_chunk(chunk_node, _chunk_grid_cache[chunk_key])
	if use_mst_generator:
		_ensure_wfc_module_ref()
	var module_ref = _wfc_module_ref if use_mst_generator else _generator_ref
	_threaded.enqueue_grid_for_instancing(
		chunk_node, _chunk_grid_cache[chunk_key],
		chunk_height, chunk_length, cell_size,
		module_ref, Vector3.ZERO
	)

func _build_lod1_chunk(chunk_node: Spatial, grid_data: Array) -> void:
	var deck_transforms = []
	var ramp_transforms = []
	var rail_transforms = []
	var support_transforms = []
	var collision_shapes = []
	for y in range(chunk_length):
		for x in range(chunk_height):
			var state = grid_data[y * chunk_height + x]
			var v = _state_variant(state)
			if state == null or v == null or _variant_id(v) == "EMPTY":
				continue
			var scale_xz = cell_size * lod_cell_scale
			var vid = _variant_id(v)
			if vid == "S" and lod_full_detail_ramps:
				_instance_lod_full_detail_cell(chunk_node, x, y, state, v)
			elif vid == "S":
				ramp_transforms.append(_lod_ramp_transform(x, y, state, v, scale_xz))
				_append_lod_ramp_rails(rail_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			else:
				var height_center = _lod_height_center_offset(v)
				deck_transforms.append(_lod_deck_transform(x, y, state, v, Vector3(scale_xz, lod_deck_thickness, scale_xz), height_center))
				_append_lod_rails(rail_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			if lod_supports_enabled:
				_append_lod_supports(support_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			if lod_collision_enabled:
				if vid == "S":
					collision_shapes.append(_lod_ramp_collision_transform(x, y, state, v))
				else:
					collision_shapes.append(_lod_collision_transform(x, y, state, v))
	_add_lod_multimesh(chunk_node, "LOD1Decks", _lod_deck_mesh, deck_transforms, _lod_material)
	_add_lod_multimesh(chunk_node, "LOD1Ramps", _lod_ramp_mesh, ramp_transforms, _lod_ramp_material)
	_add_lod_multimesh(chunk_node, "LOD1Rails", _lod_rail_mesh, rail_transforms, _lod_rail_material)
	_add_lod_multimesh(chunk_node, "LOD1Supports", _lod_rail_mesh, support_transforms, _lod_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _build_lod2_chunk(chunk_node: Spatial, grid_data: Array) -> void:
	var deck_transforms = []
	var ramp_transforms = []
	var rail_transforms = []
	var support_transforms = []
	var collision_shapes = []
	for y in range(chunk_length):
		for x in range(chunk_height):
			var state = grid_data[y * chunk_height + x]
			var v = _state_variant(state)
			if state == null or v == null or _variant_id(v) == "EMPTY":
				continue
			var scale_xz = cell_size * lod_cell_scale
			var vid = _variant_id(v)
			if vid == "S":
				ramp_transforms.append(_lod_ramp_transform(x, y, state, v, scale_xz))
				_append_lod_ramp_rails(rail_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			else:
				var height_center = _lod_height_center_offset(v)
				deck_transforms.append(_lod_deck_transform(x, y, state, v, Vector3(scale_xz, lod_deck_thickness, scale_xz), height_center))
			if lod_supports_enabled:
				_append_lod_supports(support_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			if lod_collision_enabled:
				if vid == "S":
					collision_shapes.append(_lod_ramp_collision_transform(x, y, state, v))
				else:
					collision_shapes.append(_lod_collision_transform(x, y, state, v))
	_add_lod_multimesh(chunk_node, "LOD2Decks", _lod_deck_mesh, deck_transforms, _lod_material)
	_add_lod_multimesh(chunk_node, "LOD2Ramps", _lod_ramp_mesh, ramp_transforms, _lod_ramp_material)
	_add_lod_multimesh(chunk_node, "LOD2Rails", _lod_rail_mesh, rail_transforms, _lod_rail_material)
	_add_lod_multimesh(chunk_node, "LOD2Supports", _lod_rail_mesh, support_transforms, _lod_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _lod_deck_transform(x: int, y: int, state, v, size: Vector3, y_offset: float) -> Transform:
	var xf = Transform()
	xf.basis = _lod_slope_basis(v).scaled(size)
	xf.origin = Vector3(x * cell_size, _state_base_height(state) + y_offset, y * cell_size)
	return xf

func _lod_ramp_transform(x: int, y: int, state, v, scale_xz: float) -> Transform:
	var stair = _lod_stair_axis_data(v)
	var ramp_h = max(0.2, stair.high_h - stair.low_h)
	var xf = Transform()
	xf.basis = _lod_ramp_orientation_basis(v).scaled(Vector3(scale_xz, ramp_h, scale_xz))
	xf.origin = Vector3(x * cell_size, _state_base_height(state) + stair.low_h, y * cell_size)
	return xf

func _lod_slope_basis(v) -> Basis:
	return _lod_slope_basis_for_heights(_variant_port_heights(v))

func _lod_slope_basis_for_heights(heights: Array) -> Basis:
	if heights.size() < 4:
		return Basis()
	var dz = heights[2] - heights[0]
	var dx = heights[1] - heights[3]
	if abs(dx) < 0.001 and abs(dz) < 0.001:
		return Basis()
	var x_axis = Vector3(cell_size, dx, 0.0).normalized()
	var z_axis = Vector3(0.0, dz, cell_size).normalized()
	var y_axis = z_axis.cross(x_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

func _lod_height_center_offset(v) -> float:
	return _height_center_offset_for_heights(_variant_port_heights(v))

func _height_center_offset_for_heights(heights: Array) -> float:
	if heights.empty(): return 0.0
	var lo = heights[0]
	var hi = heights[0]
	for h in heights:
		lo = min(lo, h)
		hi = max(hi, h)
	return (lo + hi) * 0.5

func _scaled_lod_ramp_heights(v) -> Array:
	var scaled = []
	for h in _variant_port_heights(v):
		scaled.append(float(h) * lod_ramp_height_scale)
	return scaled

func _min_height_for_heights(heights: Array) -> float:
	if heights.empty(): return 0.0
	var r = float(heights[0])
	for h in heights: r = min(r, float(h))
	return r

func _max_height_for_heights(heights: Array) -> float:
	if heights.empty(): return 0.0
	var r = float(heights[0])
	for h in heights: r = max(r, float(h))
	return r

func _lod_ramp_orientation_basis(v) -> Basis:
	var z_axis = _lod_stair_axis_data(v).high_axis
	var x_axis = Vector3.UP.cross(z_axis).normalized()
	return Basis(x_axis, Vector3.UP, z_axis)

func _lod_stair_axis_data(v) -> Dictionary:
	var heights = _variant_port_heights(v)
	var connections = _variant_connections(v)
	var north_h = float(heights[DIR_NORTH]) if heights.size() > DIR_NORTH else 0.0
	var east_h = float(heights[DIR_EAST]) if heights.size() > DIR_EAST else 0.0
	var south_h = float(heights[DIR_SOUTH]) if heights.size() > DIR_SOUTH else 0.0
	var west_h = float(heights[DIR_WEST]) if heights.size() > DIR_WEST else 0.0
	var north_south = connections.size() > DIR_SOUTH and connections[DIR_NORTH] and connections[DIR_SOUTH]
	var east_west = connections.size() > DIR_WEST and connections[DIR_EAST] and connections[DIR_WEST]
	if east_west and not north_south:
		if east_h >= west_h:
			return {"low_h": west_h, "high_h": east_h, "low_axis": Vector3(-1, 0, 0), "high_axis": Vector3(1, 0, 0)}
		return {"low_h": east_h, "high_h": west_h, "low_axis": Vector3(1, 0, 0), "high_axis": Vector3(-1, 0, 0)}
	if south_h >= north_h:
		return {"low_h": north_h, "high_h": south_h, "low_axis": Vector3(0, 0, -1), "high_axis": Vector3(0, 0, 1)}
	return {"low_h": south_h, "high_h": north_h, "low_axis": Vector3(0, 0, 1), "high_axis": Vector3(0, 0, -1)}

func _append_lod_rails(out: Array, collision_out, x: int, y: int, state, v) -> void:
	var connections = _variant_connections(v)
	var heights = _variant_port_heights(v)
	var base = Vector3(x * cell_size, _state_base_height(state), y * cell_size)
	var scale_xz = cell_size * lod_cell_scale
	var hw = scale_xz * 0.5
	var rh = lod_rail_height
	var sides = [
		{"dir": DIR_NORTH, "offset": Vector3(0, heights[DIR_NORTH], -hw), "axis": Vector3(1, 0, 0)},
		{"dir": DIR_SOUTH, "offset": Vector3(0, heights[DIR_SOUTH],  hw), "axis": Vector3(1, 0, 0)},
		{"dir": DIR_WEST,  "offset": Vector3(-hw, heights[DIR_WEST],  0), "axis": Vector3(0, 0, 1)},
		{"dir": DIR_EAST,  "offset": Vector3( hw, heights[DIR_EAST],  0), "axis": Vector3(0, 0, 1)},
	]
	for side in sides:
		if connections[side.dir]: continue
		var center = base + side.offset
		var xf = Transform()
		xf.basis = Basis().scaled(Vector3(
			scale_xz if side.axis.x > 0.5 else lod_rail_thickness,
			rh,
			scale_xz if side.axis.z > 0.5 else lod_rail_thickness
		))
		xf.origin = center + Vector3.UP * (rh * 0.5)
		out.append(xf)
		if collision_out != null:
			collision_out.append(_collision_box_from_transform(xf))

func _append_lod_ramp_rails(out: Array, collision_out, x: int, y: int, state, v) -> void:
	if lod_rail_height <= 0.01:
		return
	var stair = _lod_stair_axis_data(v)
	var scale_xz = cell_size * lod_cell_scale
	var basis = _lod_ramp_orientation_basis(v)
	var base = Vector3(x * cell_size, _state_base_height(state), y * cell_size)
	var side_offset = scale_xz * 0.5 - lod_rail_thickness * 0.5
	var low = base - basis.z * (scale_xz * 0.5) + Vector3.UP * float(stair.low_h)
	var high = base + basis.z * (scale_xz * 0.5) + Vector3.UP * float(stair.high_h)
	for side in [-1.0, 1.0]:
		var side_vec = basis.x * (side * side_offset)
		var low_side = low + side_vec
		var high_side = high + side_vec
		var top = _box_between_transform(
			low_side + Vector3.UP * lod_rail_height,
			high_side + Vector3.UP * lod_rail_height,
			lod_rail_thickness
		)
		var mid = _box_between_transform(
			low_side + Vector3.UP * (lod_rail_height * 0.5),
			high_side + Vector3.UP * (lod_rail_height * 0.5),
			lod_rail_thickness
		)
		var low_post = _vertical_box_transform(low_side, lod_rail_height, lod_rail_thickness)
		var high_post = _vertical_box_transform(high_side, lod_rail_height, lod_rail_thickness)
		for xf in [top, mid, low_post, high_post]:
			out.append(xf)
			if collision_out != null:
				collision_out.append(_collision_box_from_transform(xf))

func _append_lod_supports(out: Array, collision_out, x: int, y: int, state, v) -> void:
	if _variant_id(v) == "S":
		return
	var heights = _variant_port_heights(v)
	if heights.empty():
		return
	var base_y = _state_base_height(state)
	var base = Vector3(x * cell_size, 0.0, y * cell_size)
	var scale_xz = cell_size * lod_cell_scale
	var half_ext = _lod_support_half_extents(v, scale_xz)
	var half_w = half_ext.x - lod_support_thickness * 0.5
	var half_d = half_ext.y - lod_support_thickness * 0.5
	var thick = lod_support_thickness
	var supports = [
		{"pos": base + Vector3(-half_w, 0.0, -half_d), "top_y": base_y + _corner_height(heights, -1.0, -1.0) - lod_deck_thickness},
		{"pos": base + Vector3( half_w, 0.0, -half_d), "top_y": base_y + _corner_height(heights,  1.0, -1.0) - lod_deck_thickness},
		{"pos": base + Vector3(-half_w, 0.0,  half_d), "top_y": base_y + _corner_height(heights, -1.0,  1.0) - lod_deck_thickness},
		{"pos": base + Vector3( half_w, 0.0,  half_d), "top_y": base_y + _corner_height(heights,  1.0,  1.0) - lod_deck_thickness},
	]
	for support in supports:
		var top_y = float(support.top_y)
		if top_y <= thick:
			continue
		var post = Transform()
		post.basis = Basis().scaled(Vector3(thick, top_y, thick))
		post.origin = Vector3(support.pos.x, top_y * 0.5, support.pos.z)
		out.append(post)
		if collision_out != null:
			collision_out.append(_collision_box_from_transform(post))

func _corner_height(heights: Array, x_sign: float, z_sign: float) -> float:
	if heights.size() < 4:
		return 0.0
	var north_h = float(heights[DIR_NORTH])
	var east_h = float(heights[DIR_EAST])
	var south_h = float(heights[DIR_SOUTH])
	var west_h = float(heights[DIR_WEST])
	var z_h = north_h if z_sign < 0.0 else south_h
	var x_h = west_h if x_sign < 0.0 else east_h
	return (z_h + x_h) * 0.5

func _lod_support_half_extents(v, scale_xz: float) -> Vector2:
	var vid = _variant_id(v)
	if vid == "W" or vid == "R" or vid == "G":
		var connections = _variant_connections(v)
		var east_west = connections.size() > DIR_WEST and connections[DIR_EAST] and connections[DIR_WEST]
		if east_west:
			return Vector2(scale_xz * 0.5, _lane_width() * 0.5)
		return Vector2(_lane_width() * 0.5, scale_xz * 0.5)
	return Vector2(scale_xz * 0.5, scale_xz * 0.5)

func _lod_primary_axis_basis(v) -> Basis:
	if _variant_id(v) == "S":
		return _lod_ramp_orientation_basis(v)
	var connections = _variant_connections(v)
	var z_axis = Vector3(0.0, 0.0, 1.0)
	if connections.size() >= 4 and (connections[DIR_EAST] or connections[DIR_WEST]) and not (connections[DIR_NORTH] or connections[DIR_SOUTH]):
		z_axis = Vector3(1.0, 0.0, 0.0)
	var x_axis = Vector3.UP.cross(z_axis).normalized()
	return Basis(x_axis, Vector3.UP, z_axis)

func _collision_box_from_transform(xf: Transform) -> Dictionary:
	var x_axis = xf.basis.x
	var y_axis = xf.basis.y
	var z_axis = xf.basis.z
	var sx = max(x_axis.length(), 0.001)
	var sy = max(y_axis.length(), 0.001)
	var sz = max(z_axis.length(), 0.001)
	var basis = Basis(x_axis / sx, y_axis / sy, z_axis / sz)
	return {
		"transform": Transform(basis, xf.origin),
		"extents": Vector3(sx, sy, sz) * 0.5
	}

func _box_between_transform(start: Vector3, end: Vector3, thickness: float) -> Transform:
	var delta = end - start
	var length = delta.length()
	if length <= 0.001:
		return _vertical_box_transform(start, thickness, thickness)
	var x_axis = delta / length
	var tangent = Vector3.UP if abs(x_axis.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var z_axis = x_axis.cross(tangent).normalized()
	var y_axis = z_axis.cross(x_axis).normalized()
	var basis = Basis()
	basis.x = x_axis * length
	basis.y = y_axis * thickness
	basis.z = z_axis * thickness
	return Transform(basis, (start + end) * 0.5)

func _vertical_box_transform(base: Vector3, height: float, thickness: float) -> Transform:
	var xf = Transform()
	xf.basis = Basis().scaled(Vector3(thickness, height, thickness))
	xf.origin = base + Vector3.UP * (height * 0.5)
	return xf

func _instance_lod_full_detail_cell(chunk_node: Spatial, x: int, y: int, state, v) -> void:
	if use_mst_generator:
		_ensure_wfc_module_ref()
	var gen = _wfc_module_ref if use_mst_generator else _generator_ref
	if gen == null or not is_instance_valid(gen):
		return
	var vid = _variant_id(v)
	if not gen.modules.has(vid) or gen.modules[vid] == null:
		return
	var inst = gen.modules[vid].instance()
	var deck_local_y = inst.platform_height
	var base_height = _state_base_height(state)
	inst.translation = Vector3(x * cell_size, base_height - deck_local_y, y * cell_size)
	inst.rotation_degrees.y = -_variant_rotation(v)
	inst.set("support_base_local_y", deck_local_y - base_height)
	gen._apply_local_dims(inst, gen._lane_width(), cell_size)
	gen._apply_port_heights_to_front_back(inst, v)
	gen._apply_rails_from_connections(inst, v)
	gen._apply_opening_widths_from_connections(inst, v)
	chunk_node.add_child(inst)
	if inst.has_method("_rebuild"):
		inst.call("_rebuild")

func _on_chunk_instancing_done(chunk_node: Spatial) -> void:
	# Find which key owns this chunk_node
	for key in _full_lod_cleanup_pending.keys():
		if _active_chunks.get(key) == chunk_node:
			_remove_lod_children(chunk_node)
			_full_lod_cleanup_pending.erase(key)
			# Re-apply collision state: new StaticBodies from threaded instancer arrive with
			# layer=0 and need collision enabled if the chunk is within collision_radius.
			_chunk_collision_state.erase(key)
			return

func _cleanup_finished_full_detail_lods() -> void:
	# Stale entries for chunks that were unloaded before instancing finished
	for key in _full_lod_cleanup_pending.keys():
		if not _active_chunks.has(key):
			_full_lod_cleanup_pending.erase(key)

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

func _lod_slope_collision(x: int, y: int, state, v, _is_ramp: bool) -> Dictionary:
	# Unified slope collision following SteelGratePlatform._add_deck_collision convention:
	#   slope N-S → rotate around +X (Vector3.RIGHT)
	#   slope E-W → rotate around +Z (Vector3.FORWARD), sign matches right-hand rule
	var scale_xz = cell_size * lod_cell_scale
	var heights = _variant_port_heights(v)
	var north_h = float(heights[DIR_NORTH]) if heights.size() > DIR_NORTH else 0.0
	var east_h  = float(heights[DIR_EAST])  if heights.size() > DIR_EAST  else 0.0
	var south_h = float(heights[DIR_SOUTH]) if heights.size() > DIR_SOUTH else 0.0
	var west_h  = float(heights[DIR_WEST])  if heights.size() > DIR_WEST  else 0.0
	var dz = south_h - north_h   # positive → floor rises toward +Z (South)
	var dx = east_h  - west_h    # positive → floor rises toward +X (East)
	var base = _state_base_height(state)
	var slope_angle: float
	var slope_scale: float
	var center_y: float
	var rot_basis: Basis
	var ext: Vector3
	if abs(dz) >= abs(dx):
		# Slope along Z — rotate around +X raises the +Z side
		# SteelGratePlatform: slope_angle = -atan2(back_h - front_h, depth)
		# back = South (+Z), front = North (-Z), so dz = back - front
		slope_angle = -atan2(dz, cell_size)
		slope_scale = 1.0 / max(cos(slope_angle), 0.02)
		center_y = base + (north_h + south_h) * 0.5 - lod_collision_thickness * 0.5
		rot_basis = Basis(Vector3.RIGHT, slope_angle)
		ext = Vector3(scale_xz * 0.5, lod_collision_thickness * 0.5, scale_xz * slope_scale * 0.5)
	else:
		# Slope along X — rotate around +Z raises the +X side
		# +Z rotation tilts +X downward, so to raise +X we use negative angle
		slope_angle = atan2(dx, cell_size)
		slope_scale = 1.0 / max(cos(slope_angle), 0.02)
		center_y = base + (west_h + east_h) * 0.5 - lod_collision_thickness * 0.5
		rot_basis = Basis(Vector3.FORWARD, slope_angle)
		ext = Vector3(scale_xz * slope_scale * 0.5, lod_collision_thickness * 0.5, scale_xz * 0.5)
	return {"transform": Transform(rot_basis, Vector3(x * cell_size, center_y, y * cell_size)), "extents": ext}

func _lod_collision_transform(x: int, y: int, state, v) -> Dictionary:
	return _lod_slope_collision(x, y, state, v, false)

func _lod_ramp_collision_transform(x: int, y: int, state, v) -> Dictionary:
	var scale_xz = cell_size * lod_cell_scale
	var stair = _lod_stair_axis_data(v)
	var ramp_h = max(0.2, float(stair.high_h) - float(stair.low_h))
	var slope_angle = -atan2(ramp_h, cell_size)
	var slope_scale = 1.0 / max(cos(slope_angle), 0.02)
	var center_y = _state_base_height(state) + (float(stair.low_h) + float(stair.high_h)) * 0.5 - lod_collision_thickness * 0.5
	var ramp_basis = _lod_ramp_orientation_basis(v) * Basis(Vector3.RIGHT, slope_angle)
	var ext = Vector3(
		scale_xz * 0.5,
		lod_collision_thickness * 0.5,
		scale_xz * slope_scale * 0.5
	)
	return {"transform": Transform(ramp_basis, Vector3(x * cell_size, center_y, y * cell_size)), "extents": ext}

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
	_pending_chunks.erase(chunk_key)
	if use_mst_generator:
		for i in range(_mst_build_queue.size() - 1, -1, -1):
			if _mst_build_queue[i].key == chunk_key:
				_mst_build_queue.remove(i)
	if not _active_chunks.has(chunk_key):
		return
	var node = _active_chunks[chunk_key]
	_active_chunks.erase(chunk_key)
	_chunk_modes.erase(chunk_key)
	_chunk_grid_cache.erase(chunk_key)
	_chunk_expected_full_count.erase(chunk_key)
	_full_lod_cleanup_pending.erase(chunk_key)
	_chunk_collision_state.erase(chunk_key)
	_threaded.cancel_instancing_for(node)
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
