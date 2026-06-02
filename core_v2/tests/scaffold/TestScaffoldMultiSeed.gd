extends Node
# Test 6: Run Tests 1-5 across 10 distinct seeds. Report pass/fail per seed.

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const HEIGHT_STEP = 2.0

const SEEDS = [1, 7, 42, 44, 99, 123, 256, 500, 777, 1337, 9999]

func _dir_from_local_side(rot: int, side: String) -> int:
	var r = int(posmod(rot, 360))
	match side:
		"front":
			if r == 0:   return 0
			if r == 90:  return 1
			if r == 180: return 2
			return 3
		"back":
			return OPPOSITE[_dir_from_local_side(rot, "front")]
		"left":
			if r == 0:   return 3
			if r == 90:  return 0
			if r == 180: return 1
			return 2
		"right":
			return OPPOSITE[_dir_from_local_side(rot, "left")]
	return 0

func _t1_height_alignment(gen, grid: Array) -> Array:
	var gw = gen.grid_width
	var gd = gen.grid_depth
	var errs = []
	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var cx = i % gw
		var cy = i / gw
		for dir in [0, 1, 2, 3]:
			if not state.variant.connections[dir]:
				continue
			var dv = DIR_VEC[dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			var nb = grid[ni]
			if nb == null or nb.variant.id == "EMPTY":
				continue
			if not nb.variant.connections[OPPOSITE[dir]]:
				continue
			var my_port = state.base_height + state.variant.port_heights[dir]
			var their_port = nb.base_height + nb.variant.port_heights[OPPOSITE[dir]]
			if abs(my_port - their_port) > 0.01:
				errs.append("T1:[%d,%d]%s->dir%d %.2f!=%.2f" % [cx, cy, state.variant.id, dir, my_port, their_port])
	return errs

func _t2_rail_consistency(gen, grid: Array) -> Array:
	var gw = gen.grid_width
	var gd = gen.grid_depth
	var errs = []
	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var v = state.variant
		var cx = i % gw
		var cy = i / gw
		for side in ["front", "back", "left", "right"]:
			var wd = _dir_from_local_side(v.rotation, side)
			if not v.connections[wd]:
				continue
			var dv = DIR_VEC[wd]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				errs.append("T2:[%d,%d]%s side=%s connects out of bounds" % [cx, cy, v.id, side])
	return errs

func _t3_openings(gen, grid: Array) -> Array:
	var gw = gen.grid_width
	var gd = gen.grid_depth
	var errs = []
	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var v = state.variant
		var cx = i % gw
		var cy = i / gw
		for side in ["front", "back", "left", "right"]:
			var wd = _dir_from_local_side(v.rotation, side)
			var connected = v.connections[wd]
			var dv = DIR_VEC[wd]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			var nb = grid[ni]
			if not connected:
				if nb != null and nb.variant.id != "EMPTY" and nb.variant.connections[OPPOSITE[wd]]:
					errs.append("T3:[%d,%d]%s side=%s: no conn but neighbor connects back" % [cx, cy, v.id, side])
			else:
				if nb == null or nb.variant.id == "EMPTY":
					errs.append("T3:[%d,%d]%s side=%s: connected but neighbor empty" % [cx, cy, v.id, side])
				elif not nb.variant.connections[OPPOSITE[wd]]:
					errs.append("T3:[%d,%d]%s side=%s: connected but neighbor doesn't connect back" % [cx, cy, v.id, side])
	return errs

func _t4_connectivity(gen, grid: Array) -> String:
	var gw = gen.grid_width
	var gd = gen.grid_depth
	var non_empty = []
	for i in range(grid.size()):
		if grid[i] != null and grid[i].variant.id != "EMPTY":
			non_empty.append(i)
	if non_empty.empty():
		return "no non-EMPTY cells"
	var visited = {}
	var q = [non_empty[0]]
	visited[non_empty[0]] = true
	while not q.empty():
		var curr = q.pop_front()
		var cx = curr % gw
		var cy = curr / gw
		var cv = grid[curr].variant
		for dir in [0, 1, 2, 3]:
			if not cv.connections[dir]:
				continue
			var dv = DIR_VEC[dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			if visited.has(ni):
				continue
			if grid[ni] == null or grid[ni].variant.id == "EMPTY":
				continue
			if not grid[ni].variant.connections[OPPOSITE[dir]]:
				continue
			visited[ni] = true
			q.push_back(ni)
	if visited.size() != non_empty.size():
		return "component=%d total=%d (%d unreachable)" % [visited.size(), non_empty.size(), non_empty.size() - visited.size()]
	return ""

func _t5_no_negative(grid: Array) -> Array:
	var errs = []
	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var bh = state.base_height
		if bh < HEIGHT_STEP - 0.01:
			errs.append("T5:cell %d %s base_height=%.3f" % [i, state.variant.id, bh])
	return errs

# T6: port_heights with non-zero value must only be in front_dir or back_dir,
# because SteelGratePlatform only supports front_height_offset and back_height_offset.
func _t6_port_heights_representable(grid: Array) -> Array:
	var errs = []
	for i in range(grid.size()):
		var state = grid[i]
		if state == null or state.variant.id == "EMPTY":
			continue
		var v = state.variant
		var cx = i % 6
		var cy = i / 6
		var front_dir = _dir_from_local_side(v.rotation, "front")
		var back_dir = _dir_from_local_side(v.rotation, "back")
		for dir in [0, 1, 2, 3]:
			if abs(v.port_heights[dir]) < 0.001:
				continue
			if dir != front_dir and dir != back_dir:
				errs.append("T6:[%d,%d]%s rot=%d has port_height=%.1f at dir=%d but front=%d back=%d (not representable)" % [
					cx, cy, v.id, v.rotation, v.port_heights[dir], dir, front_dir, back_dir])
	return errs

func _ready():
	var total_seeds = SEEDS.size()
	var passed_seeds = 0
	var all_errors = []

	for s in SEEDS:
		var gen = GEN_SCRIPT.new()
		gen.map_seed = s
		gen.max_wfc_retries = 150
		gen.require_single_component = true
		gen.debug_verbose = false
		add_child(gen)
		var grid = gen.call("_wfc_generate")

		var seed_errors = []
		if grid.empty():
			seed_errors.append("T0: grid empty")
		else:
			seed_errors += _t1_height_alignment(gen, grid)
			seed_errors += _t2_rail_consistency(gen, grid)
			seed_errors += _t3_openings(gen, grid)
			var t4 = _t4_connectivity(gen, grid)
			if t4 != "":
				seed_errors.append("T4:" + t4)
			seed_errors += _t5_no_negative(grid)
			seed_errors += _t6_port_heights_representable(grid)

		if seed_errors.empty():
			print("[T6] PASS seed=%d" % s)
			passed_seeds += 1
		else:
			print("[T6] FAIL seed=%d — %d error(s):" % [s, seed_errors.size()])
			for e in seed_errors:
				print("  ", e)
			all_errors += seed_errors

		remove_child(gen)
		gen.free()

	print("[T6:MultiSeed] %d/%d seeds passed — %d total errors" % [passed_seeds, total_seeds, all_errors.size()])
	get_tree().quit(1 if all_errors.size() > 0 else 0)
