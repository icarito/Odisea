extends Node

const STREAM_SCRIPT = preload("res://core_v2/systems/ScaffoldStreamController.gd")
const SOLVER_SCRIPT = preload("res://core_v2/systems/WFCSolverCore.gd")

const DIR_NORTH := 0
const DIR_EAST := 1
const DIR_SOUTH := 2
const DIR_WEST := 3

var _failed := 0

func _ready() -> void:
	_check_border_ports_match(Vector2(0, 0), Vector2(1, 0))
	_check_border_ports_match(Vector2(0, 0), Vector2(0, 1))
	_check_neighbor_match(Vector2(0, 0), Vector2(1, 0))
	_check_neighbor_match(Vector2(0, 0), Vector2(0, 1))
	print("[T7:ChunkBackbone] failed=%d" % _failed)
	get_tree().quit(1 if _failed > 0 else 0)

func _make_stream():
	var stream = STREAM_SCRIPT.new()
	stream.chunk_height = 8
	stream.chunk_length = 8
	stream.global_seed = 42
	return stream

func _make_solver(fixed_tiles: Dictionary, seed_val: int):
	var solver = SOLVER_SCRIPT.new()
	solver.apply_params({
		"grid_width": 8,
		"grid_depth": 8,
		"seed": seed_val,
		"max_wfc_retries": 12,
		"require_single_component": false,
		"min_non_empty_cells": 0,
		"min_stairs_per_map": 0,
		"min_elevated_cells": 0,
		"min_empty_cells": 0,
		"min_height_span": 0.0,
		"fixed_border_tiles": fixed_tiles,
	})
	return solver

func _state_at(grid: Array, x: int, y: int):
	return grid[y * 8 + x]

func _find_open_boundary_cell(fixed: Dictionary, side: String) -> Vector2:
	for key in fixed.keys():
		var parts = key.split(",")
		var x := int(parts[0])
		var y := int(parts[1])
		var spec: Dictionary = fixed[key]
		var id := String(spec.get("id", ""))
		var rot := int(spec.get("rotation", 0))
		if side == "east" and x == 7 and ((id == "W" and rot == 90) or (id == "S" and (rot == 90 or rot == 270)) or id == "T" or id == "X"):
			return Vector2(x, y)
		if side == "west" and x == 0 and ((id == "W" and rot == 90) or (id == "S" and (rot == 90 or rot == 270)) or id == "T" or id == "X"):
			return Vector2(x, y)
		if side == "north" and y == 0 and ((id == "W" and rot == 0) or (id == "S" and (rot == 0 or rot == 180)) or id == "T" or id == "X"):
			return Vector2(x, y)
		if side == "south" and y == 7 and ((id == "W" and rot == 0) or (id == "S" and (rot == 0 or rot == 180)) or id == "T" or id == "X"):
			return Vector2(x, y)
	return Vector2(-1, -1)

func _fail(msg: String) -> void:
	print("[T7] FAIL ", msg)
	_failed += 1

func _check_border_ports_match(chunk_a: Vector2, chunk_b: Vector2) -> void:
	var stream = _make_stream()
	var fixed_a: Dictionary = stream.call("_collect_border_data", chunk_a).get("fixed_border_tiles", {})
	var fixed_b: Dictionary = stream.call("_collect_border_data", chunk_b).get("fixed_border_tiles", {})
	if chunk_b == chunk_a + Vector2(1, 0):
		var east_a := _find_open_boundary_cell(fixed_a, "east")
		var west_b := _find_open_boundary_cell(fixed_b, "west")
		if east_a.y != west_b.y:
			_fail("E/W ports do not match: %s vs %s" % [str(east_a), str(west_b)])
	elif chunk_b == chunk_a + Vector2(0, 1):
		var south_a := _find_open_boundary_cell(fixed_a, "south")
		var north_b := _find_open_boundary_cell(fixed_b, "north")
		if south_a.x != north_b.x:
			_fail("N/S ports do not match: %s vs %s" % [str(south_a), str(north_b)])

func _check_neighbor_match(chunk_a: Vector2, chunk_b: Vector2) -> void:
	var stream = _make_stream()
	var fixed_a: Dictionary = stream.call("_collect_border_data", chunk_a).get("fixed_border_tiles", {})
	var fixed_b: Dictionary = stream.call("_collect_border_data", chunk_b).get("fixed_border_tiles", {})
	var solver_a = _make_solver(fixed_a, 101)
	var solver_b = _make_solver(fixed_b, 202)
	var grid_a: Array = solver_a.generate_grid_data(101)
	var grid_b: Array = solver_b.generate_grid_data(202)
	if grid_a.empty() or grid_b.empty():
		_fail("solver returned empty grid for %s <-> %s" % [str(chunk_a), str(chunk_b)])
		return

	if chunk_b == chunk_a + Vector2(1, 0):
		var port_a := _find_open_boundary_cell(fixed_a, "east")
		var port_b := _find_open_boundary_cell(fixed_b, "west")
		var a = _state_at(grid_a, int(port_a.x), int(port_a.y))
		var b = _state_at(grid_b, int(port_b.x), int(port_b.y))
		_check_boundary_pair(a, b, DIR_EAST, "E/W")
	elif chunk_b == chunk_a + Vector2(0, 1):
		var port_a := _find_open_boundary_cell(fixed_a, "south")
		var port_b := _find_open_boundary_cell(fixed_b, "north")
		var a = _state_at(grid_a, int(port_a.x), int(port_a.y))
		var b = _state_at(grid_b, int(port_b.x), int(port_b.y))
		_check_boundary_pair(a, b, DIR_SOUTH, "N/S")

func _check_boundary_pair(a, b, dir: int, label: String) -> void:
	if a == null or b == null:
		_fail("%s boundary pair is null" % label)
		return
	var va: Dictionary = a.get("variant", {})
	var vb: Dictionary = b.get("variant", {})
	var opp := DIR_WEST if dir == DIR_EAST else DIR_NORTH
	if not va.get("connections", [])[dir]:
		_fail("%s boundary left side is not open" % label)
	if not vb.get("connections", [])[opp]:
		_fail("%s boundary right side is not open" % label)
	var ha := float(a.get("base_height", 0.0)) + float(va.get("port_heights", [0.0, 0.0, 0.0, 0.0])[dir])
	var hb := float(b.get("base_height", 0.0)) + float(vb.get("port_heights", [0.0, 0.0, 0.0, 0.0])[opp])
	if abs(ha - hb) > 0.01:
		_fail("%s boundary height mismatch %.2f != %.2f" % [label, ha, hb])
