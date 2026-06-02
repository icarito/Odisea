extends Spatial
class_name ScaffoldStreamController

# FD-050.2: Chunk-based streaming scaffold generator

const GENERATOR_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

export(bool) var streaming_enabled := true
export(float, 20.0, 300.0) var load_radius := 120.0
export(float, 20.0, 400.0) var unload_radius := 180.0
export(int, 4, 24) var chunk_height := 8 setget set_chunk_height
export(int, 4, 32) var chunk_length := 12 setget set_chunk_length
export(float, 4.0, 30.0) var cell_size := 6.0
export(int) var global_seed := 42
export(int, 1, 64) var instances_per_frame := 8
export(int, 1, 8) var max_chunk_requests_per_frame := 1
export(int, 1, 32) var max_pending_generation_jobs := 4
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

var _active_chunks: Dictionary = {}   # Vector2 -> Spatial (chunk node)
var _pending_chunks: Dictionary = {}  # Vector2 -> true (requested, awaiting generation_done)
var _threaded: ScaffoldWFCThreaded = null
var _generator_ref = null

func _ready() -> void:
	_generator_ref = GENERATOR_SCRIPT.new()
	_generator_ref.grid_width = chunk_height
	_generator_ref.grid_depth = chunk_length
	_generator_ref.cell_size = cell_size
	_apply_generator_tweaks(_generator_ref)
	_generator_ref._setup_variants()

	_threaded = ScaffoldWFCThreaded.new()
	_threaded.instances_per_frame = instances_per_frame
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
	var player_chunk = _world_to_chunk(player_pos)

	var requests_left = max_chunk_requests_per_frame
	var scan_radius = _chunk_scan_radius()
	var cx_min = int(player_chunk.x) - scan_radius
	var cx_max = int(player_chunk.x) + scan_radius
	var cz_min = int(player_chunk.y) - scan_radius
	var cz_max = int(player_chunk.y) + scan_radius

	for cx in range(cx_min, cx_max + 1):
		for cz in range(cz_min, cz_max + 1):
			if requests_left <= 0:
				break
			var key = Vector2(cx, cz)
			if _active_chunks.has(key) or _pending_chunks.has(key):
				continue
			var world_center = _chunk_to_world_center(key)
			if player_pos.distance_to(world_center) <= load_radius:
				_request_chunk(key)
				requests_left -= 1

	for key in _active_chunks.keys():
		var world_center = _chunk_to_world_center(key)
		if player_pos.distance_to(world_center) > unload_radius:
			_unload_chunk(key)

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
	var chunk_world_w = chunk_height * cell_size
	var chunk_world_d = chunk_length * cell_size
	return Vector2(
		floor(local_pos.x / chunk_world_w),
		floor(local_pos.z / chunk_world_d)
	)

func _chunk_to_world_center(chunk_key: Vector2) -> Vector3:
	var chunk_world_w = chunk_height * cell_size
	var chunk_world_d = chunk_length * cell_size
	var local_center = Vector3(
		(chunk_key.x + 0.5) * chunk_world_w,
		0.0,
		(chunk_key.y + 0.5) * chunk_world_d
	)
	return global_transform.xform(local_center)

func _chunk_to_world_origin(chunk_key: Vector2) -> Vector3:
	return Vector3(
		chunk_key.x * chunk_height * cell_size,
		0.0,
		chunk_key.y * chunk_length * cell_size
	)

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

	var offset = _chunk_to_world_origin(chunk_key)
	_threaded.enqueue_grid_for_instancing(
		chunk_node, grid_data,
		chunk_height, chunk_length, cell_size,
		_generator_ref, offset
	)

func _on_chunk_failed(chunk_key) -> void:
	_pending_chunks.erase(chunk_key)
	push_warning("[ScaffoldStream] Chunk generation failed: %s" % str(chunk_key))

func _unload_chunk(chunk_key: Vector2) -> void:
	if not _active_chunks.has(chunk_key):
		return
	var node = _active_chunks[chunk_key]
	_active_chunks.erase(chunk_key)
	node.queue_free()

func _chunk_scan_radius() -> int:
	var min_chunk_side = max(1.0, min(chunk_height * cell_size, chunk_length * cell_size))
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
		"chunk_world_height_x": chunk_height * cell_size,
		"chunk_world_length_z": chunk_length * cell_size,
		"active_chunks": _active_chunks.size(),
		"pending_chunks": _pending_chunks.size(),
		"instances_per_frame": instances_per_frame,
		"max_wfc_retries": max_wfc_retries,
		"min_non_empty_cells": min_non_empty_cells
	}
