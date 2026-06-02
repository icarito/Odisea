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
const PROP_VISUAL_LAYER := 64
const PROP_COLLISION_MASK := 255
const FOOTSTEP_SURFACE_SCRIPT := preload("res://core_v2/systems/footsteps/footstep_surface.gd")
const SCAFFOLD_FOOTSTEP_PROFILE := preload("res://core_v2/audio/footsteps/footstep_profile_scaffold_metal.tres")

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
var _lod_deck_mesh: Mesh = null
var _lod_ramp_mesh: Mesh = null
var _lod_rail_mesh: CubeMesh = null
var _lod_material: SpatialMaterial = null
var _lod_rail_material: SpatialMaterial = null
var _lod_ramp_material: Material = null
var _lod_grate_material: Material = null
var _lod_grate_far_material: Material = null

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
		_build_lod1_chunk(chunk_node, grid_data, chunk_key)
	elif mode == "lod2":
		_build_lod2_chunk(chunk_node, grid_data, chunk_key)

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
	var min_x = origin.x - cell_size * 0.5
	var min_z = origin.z - cell_size * 0.5
	var max_x = origin.x + (float(chunk_height) - 0.5) * cell_size
	var max_z = origin.z + (float(chunk_length) - 0.5) * cell_size
	var closest_x = clamp(local_pos.x, min_x, max_x)
	var closest_z = clamp(local_pos.z, min_z, max_z)
	return Vector2(local_pos.x - closest_x, local_pos.z - closest_z).length()

func _chunk_step_x() -> float:
	return max(1.0, float(chunk_height)) * cell_size

func _chunk_step_z() -> float:
	return max(1.0, float(chunk_length)) * cell_size

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
	_lod_deck_mesh = _make_lod_deck_surface_mesh()
	_lod_ramp_mesh = _make_lod_ramp_surface_mesh()
	_lod_rail_mesh = CubeMesh.new()
	_lod_rail_mesh.size = Vector3.ONE

	_lod1_tube_mesh = CylinderMesh.new()
	_lod1_tube_mesh.radial_segments = lod_tube_segments
	_lod1_tube_mesh.top_radius = 0.07 # Match SteelGratePlatform default tube_radius
	_lod1_tube_mesh.bottom_radius = 0.07
	_lod1_tube_mesh.height = 1.0

	_lod1_grate_mesh = QuadMesh.new()

	_lod2_deck_mesh = CubeMesh.new()
	_lod2_deck_mesh.size = Vector3.ONE

	_lod_material = SpatialMaterial.new()
	_lod_material.albedo_color = frame_color
	_lod_material.metallic = 0.12
	_lod_material.roughness = 0.96

	_lod_rail_material = _lod_material.duplicate()
	_lod_rail_material.albedo_color = rail_color

	_lod_grate_material = _make_lod_grate_material(true, 0.42, Vector2(1.55, 1.55), 0.82, true)
	_lod_grate_far_material = _make_lod_grate_material(false, 0.0, Vector2(1.55, 1.55), 0.82, true)
	_lod_ramp_material = _make_lod_ramp_grate_material()

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
	_add_lod_ramp_face(st, low_l, low_r, high_r, high_l, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 1.0)))
	_add_lod_ramp_face(st, base_high_l, base_high_r, base_low_r, base_low_l, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 1.0)))
	_add_lod_ramp_face(st, base_low_l, low_l, high_l, base_high_l, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 1.0)))
	_add_lod_ramp_face(st, base_high_r, high_r, low_r, base_low_r, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 1.0)))
	_add_lod_ramp_face(st, base_low_l, base_low_r, low_r, low_l, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 0.4)))
	_add_lod_ramp_face(st, base_high_l, high_l, high_r, base_high_r, Rect2(Vector2(0.0, 0.0), Vector2(1.0, 0.4)))
	st.generate_normals()
	st.commit(mesh)
	return mesh

func _make_lod_deck_surface_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_lod_ramp_face(st,
		Vector3(-0.5, 0.0, -0.5),
		Vector3(0.5, 0.0, -0.5),
		Vector3(0.5, 0.0, 0.5),
		Vector3(-0.5, 0.0, 0.5),
		Rect2(Vector2.ZERO, Vector2.ONE)
	)
	_add_lod_ramp_face(st,
		Vector3(-0.5, 0.0, 0.5),
		Vector3(0.5, 0.0, 0.5),
		Vector3(0.5, 0.0, -0.5),
		Vector3(-0.5, 0.0, -0.5),
		Rect2(Vector2.ZERO, Vector2.ONE)
	)
	st.generate_normals()
	st.commit(mesh)
	return mesh

func _make_lod_ramp_surface_mesh() -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_lod_ramp_face(st,
		Vector3(-0.5, 0.0, -0.5),
		Vector3(0.5, 0.0, -0.5),
		Vector3(0.5, 1.0, 0.5),
		Vector3(-0.5, 1.0, 0.5),
		Rect2(Vector2.ZERO, Vector2.ONE)
	)
	# Cara inferior: winding invertido para normal hacia abajo, mismos vértices sin offset
	_add_lod_ramp_face(st,
		Vector3(-0.5, 1.0, 0.5),
		Vector3(0.5, 1.0, 0.5),
		Vector3(0.5, 0.0, -0.5),
		Vector3(-0.5, 0.0, -0.5),
		Rect2(Vector2(0.0, 1.0), Vector2(1.0, -1.0))
	)
	st.generate_normals()
	st.commit(mesh)
	return mesh

func _make_lod_ramp_grate_material() -> SpatialMaterial:
	var source = load("res://textures/trenchbroom/steel_grate_platform.tres")
	var mat: SpatialMaterial
	if source is SpatialMaterial:
		mat = (source as SpatialMaterial).duplicate(true)
	else:
		mat = SpatialMaterial.new()
	mat.albedo_color = Color(
		grate_color.r * 0.82,
		grate_color.g * 0.82,
		grate_color.b * 0.82,
		grate_color.a
	)
	mat.params_alpha_scissor_threshold = 0.42
	mat.flags_transparent = false
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.metallic = 0.0
	mat.roughness = 1.0
	mat.metallic_specular = 0.08
	# El mesh va de 0→1 en UV pero cubre lane_width × cell_size metros en world.
	# Escalar igual que los decks (1.55 tiles/m) para que el patrón tenga el mismo tamaño visual.
	var repeat_per_meter := 1.55
	var ramp_u := clamp(cell_size * 0.32, 2.5, 4.5) * repeat_per_meter
	var ramp_v := cell_size * lod_cell_scale * repeat_per_meter
	mat.uv1_scale = Vector3(ramp_u, ramp_v, 1.0)
	return mat

func _make_lod_grate_material(use_alpha_scissor: bool, alpha_threshold: float, repeat: Vector2, brightness: float, use_world_uv: bool) -> ShaderMaterial:
	var source = load("res://textures/trenchbroom/steel_grate_platform.tres")
	var texture = null
	if source is SpatialMaterial:
		texture = (source as SpatialMaterial).albedo_texture
	var shader = load("res://shaders/prop_dither_occlusion.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_param("albedo", Color(
		grate_color.r * brightness,
		grate_color.g * brightness,
		grate_color.b * brightness,
		grate_color.a
	))
	mat.set_shader_param("texture_albedo", texture)
	mat.set_shader_param("metallic", 0.0)
	mat.set_shader_param("roughness", 1.0)
	mat.set_shader_param("specular", 0.08)
	mat.set_shader_param("use_alpha_scissor", use_alpha_scissor)
	mat.set_shader_param("alpha_scissor_threshold", alpha_threshold)
	mat.set_shader_param("use_world_uv", use_world_uv)
	mat.set_shader_param("world_uv_repeat", repeat)
	mat.set_shader_param("is_active", 0.0)
	return mat

func _add_lod_ramp_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv_rect: Rect2) -> void:
	var uv_a = Vector2(uv_rect.position.x, uv_rect.position.y)
	var uv_b = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y)
	var uv_c = Vector2(uv_rect.position.x + uv_rect.size.x, uv_rect.position.y + uv_rect.size.y)
	var uv_d = Vector2(uv_rect.position.x, uv_rect.position.y + uv_rect.size.y)
	st.add_uv(uv_a)
	st.add_vertex(a)
	st.add_uv(uv_b)
	st.add_vertex(b)
	st.add_uv(uv_c)
	st.add_vertex(c)
	st.add_uv(uv_a)
	st.add_vertex(a)
	st.add_uv(uv_c)
	st.add_vertex(c)
	st.add_uv(uv_d)
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
		_build_lod1_chunk(chunk_node, grid_data, chunk_key)
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
		_build_lod1_chunk(chunk_node, grid_data, chunk_key)
	else:
		_build_lod2_chunk(chunk_node, grid_data, chunk_key)

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
	if enabled:
		var dither = get_node_or_null("/root/PropDitherManager")
		if dither and dither.has_method("refresh_occlusion_for_node"):
			dither.call_deferred("refresh_occlusion_for_node", chunk_node)

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
		_build_lod1_chunk(chunk_node, _chunk_grid_cache[chunk_key], chunk_key)
	if use_mst_generator:
		_ensure_wfc_module_ref()
	var module_ref = _wfc_module_ref if use_mst_generator else _generator_ref
	_threaded.enqueue_grid_for_instancing(
		chunk_node, _chunk_grid_cache[chunk_key],
		chunk_height, chunk_length, cell_size,
		module_ref, Vector3.ZERO
	)

func _build_lod1_chunk(chunk_node: Spatial, grid_data: Array, chunk_key: Vector2) -> void:
	var deck_transforms = []
	var ramp_transforms = []
	var rail_transforms = []
	var support_transforms = []
	var collision_shapes = []
	var used_support_keys = {}
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
				_append_lod_decks(deck_transforms, x, y, state, v, scale_xz, height_center)
				_append_lod_rails(rail_transforms, collision_shapes if lod_collision_enabled else null, x, y, state, v)
			if lod_supports_enabled:
				_append_lod_supports(support_transforms, collision_shapes if lod_collision_enabled else null, used_support_keys, chunk_key, x, y, state, v)
			if lod_collision_enabled:
				if vid == "S":
					collision_shapes.append(_lod_ramp_collision_transform(x, y, state, v))
				else:
					_append_lod_deck_collisions(collision_shapes, x, y, state, v, scale_xz)
	_add_lod_multimesh(chunk_node, "LOD1Decks", _lod_deck_mesh, deck_transforms, _lod_grate_material)
	_add_lod_multimesh(chunk_node, "LOD1Ramps", _lod_ramp_mesh, ramp_transforms, _lod_ramp_material)
	_add_lod_multimesh(chunk_node, "LOD1Rails", _lod1_tube_mesh, rail_transforms, _lod_rail_material)
	_add_lod_multimesh(chunk_node, "LOD1Supports", _lod1_tube_mesh, support_transforms, _lod_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _build_lod2_chunk(chunk_node: Spatial, grid_data: Array, chunk_key: Vector2) -> void:
	var deck_transforms = []
	var ramp_transforms = []
	var rail_transforms = []
	var support_transforms = []
	var collision_shapes = []
	var used_support_keys = {}
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
				_append_lod_decks(deck_transforms, x, y, state, v, scale_xz, height_center)
			if lod_supports_enabled:
				_append_lod_supports(support_transforms, collision_shapes if lod_collision_enabled else null, used_support_keys, chunk_key, x, y, state, v)
			if lod_collision_enabled:
				if vid == "S":
					collision_shapes.append(_lod_ramp_collision_transform(x, y, state, v))
				else:
					_append_lod_deck_collisions(collision_shapes, x, y, state, v, scale_xz)
	_add_lod_multimesh(chunk_node, "LOD2Decks", _lod_deck_mesh, deck_transforms, _lod_grate_far_material)
	_add_lod_multimesh(chunk_node, "LOD2Ramps", _lod_ramp_mesh, ramp_transforms, _lod_ramp_material)
	_add_lod_multimesh(chunk_node, "LOD2Rails", _lod1_tube_mesh, rail_transforms, _lod_rail_material)
	_add_lod_multimesh(chunk_node, "LOD2Supports", _lod1_tube_mesh, support_transforms, _lod_material)
	_add_lod_collision(chunk_node, collision_shapes)

func _lod_deck_transform(x: int, y: int, state, v, size: Vector3, y_offset: float) -> Transform:
	var xf = Transform()
	xf.basis = _basis_scaled_local(_lod_slope_basis(v), size)
	xf.origin = Vector3(x * cell_size, _state_base_height(state) + y_offset, y * cell_size)
	return xf

func _append_lod_decks(out: Array, x: int, y: int, state, v, scale_xz: float, y_offset: float) -> void:
	# Small overlap (~2cm/side) to close seams between adjacent tiles
	var scale_xz_visual := scale_xz + lod_support_thickness
	for spec in _lod_deck_specs(v, scale_xz_visual, lod_deck_thickness):
		var xf = _lod_deck_transform(x, y, state, v, spec.size, y_offset + lod_deck_thickness * 0.5)
		xf.origin += spec.offset
		out.append(xf)

func _lod_deck_size(v, scale_xz: float) -> Vector3:
	var half_ext = _lod_deck_half_extents(v, scale_xz)
	return Vector3(half_ext.x * 2.0, lod_deck_thickness, half_ext.y * 2.0)

func _lod_ramp_transform(x: int, y: int, state, v, scale_xz: float) -> Transform:
	var stair = _lod_stair_axis_data(v)
	var ramp_h = max(0.2, stair.high_h - stair.low_h)
	var xf = Transform()
	xf.basis = _basis_scaled_local(_lod_ramp_orientation_basis(v), Vector3(_lane_width(), ramp_h, scale_xz))
	xf.origin = Vector3(x * cell_size, _state_base_height(state) + stair.low_h, y * cell_size)
	return xf

func _basis_scaled_local(basis: Basis, size: Vector3) -> Basis:
	var scaled = Basis()
	scaled.x = basis.x * size.x
	scaled.y = basis.y * size.y
	scaled.z = basis.z * size.z
	return scaled

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
	if _use_perimeter_lod_rails(v):
		_append_lod_perimeter_rails(out, collision_out, base, heights, connections, scale_xz)
		return
	var scale_xz_visual = scale_xz + lod_support_thickness
	var rects = _lod_deck_rects(v, scale_xz_visual)
	for i in range(rects.size()):
		_append_lod_rect_side_rail(out, collision_out, base, heights, connections, rects, i, DIR_NORTH, scale_xz_visual)
		_append_lod_rect_side_rail(out, collision_out, base, heights, connections, rects, i, DIR_SOUTH, scale_xz_visual)
		_append_lod_rect_side_rail(out, collision_out, base, heights, connections, rects, i, DIR_WEST, scale_xz_visual)
		_append_lod_rect_side_rail(out, collision_out, base, heights, connections, rects, i, DIR_EAST, scale_xz_visual)

func _append_lod_ramp_rails(out: Array, collision_out, x: int, y: int, state, v) -> void:
	if lod_rail_height <= 0.01:
		return
	var stair = _lod_stair_axis_data(v)
	var scale_xz = cell_size * lod_cell_scale
	var basis = _lod_ramp_orientation_basis(v)
	var base = Vector3(x * cell_size, _state_base_height(state), y * cell_size)
	var rail_bottom_offset = lod_deck_thickness * 0.5
	var side_offset = _lane_width() * 0.5 - lod_rail_thickness * 0.5
	var low = base - basis.z * (scale_xz * 0.5) + Vector3.UP * (float(stair.low_h) + rail_bottom_offset)
	var high = base + basis.z * (scale_xz * 0.5) + Vector3.UP * (float(stair.high_h) + rail_bottom_offset)
	for side in [-1.0, 1.0]:
		var side_vec = basis.x * (side * side_offset)
		var low_side = low + side_vec
		var high_side = high + side_vec
		_append_lod_rail_segment(out, collision_out, low_side, high_side)

func _append_lod_supports(out: Array, collision_out, used_support_keys: Dictionary, chunk_key: Vector2, x: int, y: int, state, v) -> void:
	if _variant_id(v) == "S":
		return
	var heights = _variant_port_heights(v)
	if heights.empty():
		return
	var base_y = _state_base_height(state)
	var base = Vector3(x * cell_size, 0.0, y * cell_size)
	var scale_xz = cell_size * lod_cell_scale
	var thick = lod_support_thickness
	var rects = _lod_deck_rects(v, scale_xz)
	for rect_index in range(rects.size()):
		var rect = rects[rect_index]
		var corners = [
			Vector2(rect.min_x + thick * 0.5, rect.min_z + thick * 0.5),
			Vector2(rect.max_x - thick * 0.5, rect.min_z + thick * 0.5),
			Vector2(rect.min_x + thick * 0.5, rect.max_z - thick * 0.5),
			Vector2(rect.max_x - thick * 0.5, rect.max_z - thick * 0.5),
		]
		for corner in corners:
			var snapped_corner = _snap_support_corner(corner, scale_xz, thick)
			var support_pos = base + Vector3(snapped_corner.x, 0.0, snapped_corner.y)
			var world_support_pos = _chunk_to_local_origin(chunk_key) + support_pos
			if _support_owner_chunk_for_world_position(world_support_pos) != chunk_key:
				continue
			var key = _support_world_key(world_support_pos)
			if used_support_keys.has(key):
				continue
			var x_sign = -1.0 if corner.x < 0.0 else 1.0
			var z_sign = -1.0 if corner.y < 0.0 else 1.0
			var top_y = base_y + _corner_height(heights, x_sign, z_sign) - lod_deck_thickness * 0.35
			if top_y <= thick:
				continue
			used_support_keys[key] = true
			var post = _tube_between_transform(Vector3(support_pos.x, 0.0, support_pos.z), Vector3(support_pos.x, top_y, support_pos.z))
			out.append(post)
			if collision_out != null:
				collision_out.append(_collision_box_from_transform(_vertical_box_transform(Vector3(support_pos.x, 0.0, support_pos.z), top_y, thick)))

func _snap_support_corner(corner: Vector2, scale_xz: float, thick: float) -> Vector2:
	var snapped = corner
	var full_edge = scale_xz * 0.5
	if abs(abs(corner.x) - (full_edge - thick * 0.5)) <= thick:
		snapped.x = sign(corner.x) * full_edge
	if abs(abs(corner.y) - (full_edge - thick * 0.5)) <= thick:
		snapped.y = sign(corner.y) * full_edge
	return snapped

func _rect_corner_needs_support(rects: Array, rect_index: int, corner: Vector2) -> bool:
	var z_dir = DIR_NORTH if corner.y < 0.0 else DIR_SOUTH
	var x_dir = DIR_WEST if corner.x < 0.0 else DIR_EAST
	return (
		_rect_side_has_visible_point(rects, rect_index, z_dir, corner.x) and
		_rect_side_has_visible_point(rects, rect_index, x_dir, corner.y)
	)

func _rect_side_has_visible_point(rects: Array, rect_index: int, dir: int, point: float, epsilon: float = 0.06) -> bool:
	for seg in _rect_side_visible_segments(rects, rect_index, dir):
		if point >= seg.x - epsilon and point <= seg.y + epsilon:
			return true
	return false

func _support_world_key(world_pos: Vector3) -> String:
	var step = max(lod_support_thickness, 0.1)
	return "%d:%d" % [
		int(round(world_pos.x / step)),
		int(round(world_pos.z / step))
	]

func _use_perimeter_lod_rails(v) -> bool:
	return _variant_id(v) == "P"

func _append_lod_perimeter_rails(out: Array, collision_out, base: Vector3, heights: Array, connections: Array, scale_xz: float) -> void:
	var edge = scale_xz * 0.5
	var opening = min(_lane_width(), max(scale_xz - lod_rail_thickness * 2.0, 0.0))
	_append_lod_side_opening_rail(out, collision_out, base, heights, connections, DIR_NORTH, -edge, opening)
	_append_lod_side_opening_rail(out, collision_out, base, heights, connections, DIR_SOUTH, edge, opening)
	_append_lod_side_opening_rail(out, collision_out, base, heights, connections, DIR_WEST, -edge, opening)
	_append_lod_side_opening_rail(out, collision_out, base, heights, connections, DIR_EAST, edge, opening)

func _append_lod_side_opening_rail(out: Array, collision_out, base: Vector3, heights: Array, connections: Array, dir: int, side_value: float, opening_width: float) -> void:
	var h = (float(heights[dir]) if heights.size() > dir else 0.0) + lod_deck_thickness * 0.5
	var half_span = cell_size * lod_cell_scale * 0.5 + lod_support_thickness * 0.5
	var is_open = connections.size() > dir and connections[dir]
	var open_half = opening_width * 0.5 if is_open else 0.0
	if dir == DIR_NORTH or dir == DIR_SOUTH:
		if not is_open:
			_append_lod_horizontal_rail_interval(out, collision_out, base, h, side_value, -half_span, half_span)
			return
		_append_lod_horizontal_rail_interval(out, collision_out, base, h, side_value, -half_span, -open_half)
		_append_lod_horizontal_rail_interval(out, collision_out, base, h, side_value, open_half, half_span)
		return
	if not is_open:
		_append_lod_vertical_rail_interval(out, collision_out, base, h, side_value, -half_span, half_span)
		return
	_append_lod_vertical_rail_interval(out, collision_out, base, h, side_value, -half_span, -open_half)
	_append_lod_vertical_rail_interval(out, collision_out, base, h, side_value, open_half, half_span)

func _append_lod_horizontal_rail_interval(out: Array, collision_out, base: Vector3, height: float, z_value: float, x_start: float, x_end: float) -> void:
	if x_end - x_start <= 0.05:
		return
	var a = base + Vector3(x_start, height, z_value)
	var b = base + Vector3(x_end, height, z_value)
	_append_lod_rail_segment(out, collision_out, a, b)

func _append_lod_vertical_rail_interval(out: Array, collision_out, base: Vector3, height: float, x_value: float, z_start: float, z_end: float) -> void:
	if z_end - z_start <= 0.05:
		return
	var a = base + Vector3(x_value, height, z_start)
	var b = base + Vector3(x_value, height, z_end)
	_append_lod_rail_segment(out, collision_out, a, b)

func _append_lod_rail_segment(out: Array, collision_out, a: Vector3, b: Vector3) -> void:
	var top_a = a + Vector3.UP * lod_rail_height
	var top_b = b + Vector3.UP * lod_rail_height
	var mid_a = a + Vector3.UP * (lod_rail_height * 0.5)
	var mid_b = b + Vector3.UP * (lod_rail_height * 0.5)
	var visual = [
		_tube_between_transform(top_a, top_b),
		_tube_between_transform(mid_a, mid_b),
		_tube_between_transform(a, top_a),
		_tube_between_transform(b, top_b),
	]
	var collision = [
		_box_between_transform(top_a, top_b, lod_rail_thickness),
		_box_between_transform(mid_a, mid_b, lod_rail_thickness),
		_vertical_box_transform(a, lod_rail_height, lod_rail_thickness),
		_vertical_box_transform(b, lod_rail_height, lod_rail_thickness),
	]
	for xf in visual:
		out.append(xf)
	if collision_out != null:
		for col in collision:
			collision_out.append(_collision_box_from_transform(col))

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

func _lod_deck_half_extents(v, scale_xz: float) -> Vector2:
	var vid = _variant_id(v)
	if vid == "W" or vid == "R" or vid == "G":
		var connections = _variant_connections(v)
		var east_west = connections.size() > DIR_WEST and connections[DIR_EAST] and connections[DIR_WEST]
		if east_west:
			return Vector2(scale_xz * 0.5, _lane_width() * 0.5)
		return Vector2(_lane_width() * 0.5, scale_xz * 0.5)
	return Vector2(scale_xz * 0.5, scale_xz * 0.5)

func _lod_deck_specs(v, scale_xz: float, thickness: float) -> Array:
	var vid = _variant_id(v)
	if vid == "P":
		return [{"offset": Vector3.ZERO, "size": Vector3(scale_xz, thickness, scale_xz)}]
	if vid == "W" or vid == "R" or vid == "G":
		return [{"offset": Vector3.ZERO, "size": _lod_deck_size(v, scale_xz)}]

	var connections = _variant_connections(v)
	var count = 0
	for c in connections:
		if c:
			count += 1
	if count <= 0:
		return [{"offset": Vector3.ZERO, "size": Vector3(scale_xz, thickness, scale_xz)}]
	if count == 1:
		var dead_end_specs = []
		var lane_single = _lane_width()
		var arm_len_single = scale_xz * 0.5 + lane_single * 0.5
		var arm_offset_single = scale_xz * 0.25 - lane_single * 0.25
		if connections.size() > DIR_NORTH and connections[DIR_NORTH]:
			dead_end_specs.append({"offset": Vector3(0.0, 0.0, -arm_offset_single), "size": Vector3(lane_single, thickness, arm_len_single)})
		if connections.size() > DIR_SOUTH and connections[DIR_SOUTH]:
			dead_end_specs.append({"offset": Vector3(0.0, 0.0, arm_offset_single), "size": Vector3(lane_single, thickness, arm_len_single)})
		if connections.size() > DIR_EAST and connections[DIR_EAST]:
			dead_end_specs.append({"offset": Vector3(arm_offset_single, 0.0, 0.0), "size": Vector3(arm_len_single, thickness, lane_single)})
		if connections.size() > DIR_WEST and connections[DIR_WEST]:
			dead_end_specs.append({"offset": Vector3(-arm_offset_single, 0.0, 0.0), "size": Vector3(arm_len_single, thickness, lane_single)})
		return dead_end_specs

	var lane = _lane_width()
	var arm_len = max((scale_xz - lane) * 0.5, 0.0)
	var arm_offset = (scale_xz + lane) * 0.25
	var specs = [{"offset": Vector3.ZERO, "size": Vector3(lane, thickness, lane)}]
	if connections.size() > DIR_NORTH and connections[DIR_NORTH]:
		specs.append({"offset": Vector3(0.0, 0.0, -arm_offset), "size": Vector3(lane, thickness, arm_len)})
	if connections.size() > DIR_SOUTH and connections[DIR_SOUTH]:
		specs.append({"offset": Vector3(0.0, 0.0, arm_offset), "size": Vector3(lane, thickness, arm_len)})
	if connections.size() > DIR_EAST and connections[DIR_EAST]:
		specs.append({"offset": Vector3(arm_offset, 0.0, 0.0), "size": Vector3(arm_len, thickness, lane)})
	if connections.size() > DIR_WEST and connections[DIR_WEST]:
		specs.append({"offset": Vector3(-arm_offset, 0.0, 0.0), "size": Vector3(arm_len, thickness, lane)})
	return specs

func _lod_deck_rects(v, scale_xz: float) -> Array:
	var rects = []
	for spec in _lod_deck_specs(v, scale_xz, lod_deck_thickness):
		var half_x = float(spec.size.x) * 0.5
		var half_z = float(spec.size.z) * 0.5
		rects.append({
			"min_x": float(spec.offset.x) - half_x,
			"max_x": float(spec.offset.x) + half_x,
			"min_z": float(spec.offset.z) - half_z,
			"max_z": float(spec.offset.z) + half_z,
		})
	return rects

func _lod_rail_half_extents(v, scale_xz: float) -> Vector2:
	var vid = _variant_id(v)
	if vid == "W" or vid == "R" or vid == "G":
		return _lod_deck_half_extents(v, scale_xz)
	return Vector2(_lane_width() * 0.5, _lane_width() * 0.5)

func _append_lod_rect_side_rail(out: Array, collision_out, base: Vector3, heights: Array, connections: Array, rects: Array, rect_index: int, dir: int, scale_xz: float) -> void:
	var rect = rects[rect_index]
	if _rect_side_is_connected_open(rect, dir, connections, scale_xz):
		return
	var segments = _rect_side_visible_segments(rects, rect_index, dir)
	var h = (float(heights[dir]) if heights.size() > dir else 0.0) + lod_deck_thickness * 0.5
	for seg in segments:
		if abs(seg.y - seg.x) <= 0.05:
			continue
		var a: Vector3
		var b: Vector3
		if dir == DIR_NORTH:
			a = base + Vector3(seg.x, h, rect.min_z)
			b = base + Vector3(seg.y, h, rect.min_z)
		elif dir == DIR_SOUTH:
			a = base + Vector3(seg.x, h, rect.max_z)
			b = base + Vector3(seg.y, h, rect.max_z)
		elif dir == DIR_WEST:
			a = base + Vector3(rect.min_x, h, seg.x)
			b = base + Vector3(rect.min_x, h, seg.y)
		else:
			a = base + Vector3(rect.max_x, h, seg.x)
			b = base + Vector3(rect.max_x, h, seg.y)
		_append_lod_rail_segment(out, collision_out, a, b)

func _support_owner_chunk_for_world_position(world_pos: Vector3) -> Vector2:
	var owner_x = floor((world_pos.x - 0.001) / _chunk_step_x())
	var owner_z = floor((world_pos.z - 0.001) / _chunk_step_z())
	return Vector2(owner_x, owner_z)

func _rect_side_is_connected_open(rect: Dictionary, dir: int, connections: Array, scale_xz: float) -> bool:
	if connections.size() <= dir or not connections[dir]:
		return false
	var edge = scale_xz * 0.5
	if dir == DIR_NORTH:
		return rect.min_z <= -edge + 0.01
	if dir == DIR_SOUTH:
		return rect.max_z >= edge - 0.01
	if dir == DIR_WEST:
		return rect.min_x <= -edge + 0.01
	return rect.max_x >= edge - 0.01

func _rect_side_visible_segments(rects: Array, rect_index: int, dir: int) -> Array:
	var rect = rects[rect_index]
	var horizontal = dir == DIR_NORTH or dir == DIR_SOUTH
	var side_value = rect.min_z if dir == DIR_NORTH else rect.max_z
	var start = rect.min_x
	var end = rect.max_x
	if not horizontal:
		side_value = rect.min_x if dir == DIR_WEST else rect.max_x
		start = rect.min_z
		end = rect.max_z
	var segments = [Vector2(start, end)]
	for i in range(rects.size()):
		if i == rect_index:
			continue
		var other = rects[i]
		var covers_side = false
		var overlap = Vector2()
		if horizontal:
			covers_side = other.min_z < side_value + 0.001 and other.max_z > side_value - 0.001
			overlap = Vector2(max(start, other.min_x), min(end, other.max_x))
		else:
			covers_side = other.min_x < side_value + 0.001 and other.max_x > side_value - 0.001
			overlap = Vector2(max(start, other.min_z), min(end, other.max_z))
		if covers_side and overlap.y > overlap.x:
			segments = _subtract_lod_interval(segments, overlap)
	return segments

func _subtract_lod_interval(segments: Array, cut: Vector2) -> Array:
	var out = []
	for seg in segments:
		if cut.y <= seg.x or cut.x >= seg.y:
			out.append(seg)
			continue
		if cut.x > seg.x:
			out.append(Vector2(seg.x, min(cut.x, seg.y)))
		if cut.y < seg.y:
			out.append(Vector2(max(cut.y, seg.x), seg.y))
	return out

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

func _tube_between_transform(start: Vector3, end: Vector3) -> Transform:
	var delta = end - start
	var length = delta.length()
	if length <= 0.001:
		return Transform()
	var y_axis = delta / length
	var tangent = Vector3.FORWARD if abs(y_axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var x_axis = tangent.cross(y_axis).normalized()
	var z_axis = x_axis.cross(y_axis).normalized()
	var basis = Basis()
	basis.x = x_axis
	basis.y = y_axis * length
	basis.z = z_axis
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
	# Deck/ramp surfaces get their own body with FootstepSurface so the player
	# hears metal steps on scaffold without overriding sounds from floor below.
	var surface_body = StaticBody.new()
	surface_body.name = "LODCollision"
	surface_body.collision_layer = PROP_COLLISION_LAYER
	surface_body.collision_mask = 0
	var footstep_surface = Spatial.new()
	footstep_surface.name = "FootstepSurface"
	footstep_surface.set_script(FOOTSTEP_SURFACE_SCRIPT)
	footstep_surface.set("footstep_profile", SCAFFOLD_FOOTSTEP_PROFILE)
	surface_body.add_child(footstep_surface)
	var other_body = StaticBody.new()
	other_body.name = "LODCollisionOther"
	other_body.collision_layer = PROP_COLLISION_LAYER
	other_body.collision_mask = 0
	var surface_count := 0
	var other_count := 0
	for spec in transforms:
		var shape = BoxShape.new()
		shape.extents = spec.get("extents", Vector3(0.5, 0.5, 0.5)) if typeof(spec) == TYPE_DICTIONARY else Vector3(0.5, 0.5, 0.5)
		var col = CollisionShape.new()
		col.shape = shape
		col.transform = spec.get("transform", Transform()) if typeof(spec) == TYPE_DICTIONARY else spec
		if typeof(spec) == TYPE_DICTIONARY and spec.get("surface", false):
			col.name = "LODDeckCollision_%d" % surface_count
			surface_body.add_child(col)
			surface_count += 1
		else:
			col.name = "LODOtherCollision_%d" % other_count
			other_body.add_child(col)
			other_count += 1
	if surface_count > 0:
		chunk_node.add_child(surface_body)
	if other_count > 0:
		chunk_node.add_child(other_body)

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
	var half_ext = _lod_deck_half_extents(v, scale_xz)
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
		ext = Vector3(half_ext.x, lod_collision_thickness * 0.5, half_ext.y * slope_scale)
	else:
		# Slope along X — rotate around +Z raises the +X side
		# +Z rotation tilts +X downward, so to raise +X we use negative angle
		slope_angle = atan2(dx, cell_size)
		slope_scale = 1.0 / max(cos(slope_angle), 0.02)
		center_y = base + (west_h + east_h) * 0.5 - lod_collision_thickness * 0.5
		rot_basis = Basis(Vector3.FORWARD, slope_angle)
		ext = Vector3(half_ext.x * slope_scale, lod_collision_thickness * 0.5, half_ext.y)
	return {"transform": Transform(rot_basis, Vector3(x * cell_size, center_y, y * cell_size)), "extents": ext}

func _lod_collision_transform(x: int, y: int, state, v) -> Dictionary:
	return _lod_slope_collision(x, y, state, v, false)

func _append_lod_deck_collisions(out: Array, x: int, y: int, state, v, scale_xz: float) -> void:
	var y_offset = _lod_height_center_offset(v) - lod_collision_thickness * 0.5
	for spec in _lod_deck_specs(v, scale_xz, lod_collision_thickness):
		var xf = _lod_deck_transform(x, y, state, v, spec.size, y_offset)
		xf.origin += spec.offset
		var box = _collision_box_from_transform(xf)
		box["surface"] = true
		out.append(box)

func _lod_ramp_collision_transform(x: int, y: int, state, v) -> Dictionary:
	var scale_xz = cell_size * lod_cell_scale
	var stair = _lod_stair_axis_data(v)
	var flat_basis = _lod_ramp_orientation_basis(v)
	var base = Vector3(x * cell_size, _state_base_height(state), y * cell_size)
	var low = base - flat_basis.z * (scale_xz * 0.5) + Vector3.UP * float(stair.low_h)
	var high = base + flat_basis.z * (scale_xz * 0.5) + Vector3.UP * float(stair.high_h)
	var delta = high - low
	var length = max(delta.length(), 0.001)
	var z_axis = delta / length
	var x_axis = flat_basis.x.normalized()
	var y_axis = z_axis.cross(x_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	var basis = Basis()
	basis.x = x_axis * _lane_width()
	basis.y = y_axis * lod_collision_thickness
	basis.z = z_axis * length
	var box = _collision_box_from_transform(Transform(basis, (low + high) * 0.5 - y_axis * (lod_collision_thickness * 0.5)))
	box["surface"] = true
	return box

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
	inst.layers = PROP_VISUAL_LAYER
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
