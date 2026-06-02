extends Node
# Test 4: The subgraph of non-EMPTY cells must be a single connected component (BFS).

const GEN_SCRIPT = preload("res://core_v2/systems/ScaffoldWFCGenerator.gd")

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var _passed := 0
var _failed := 0

func _ready():
	for s in [42, 99, 777]:
		_run(s)
	print("[T4:Connectivity] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _run(seed_val: int) -> void:
	var gen = GEN_SCRIPT.new()
	gen.map_seed = seed_val
	gen.max_wfc_retries = 400
	gen.require_single_component = true
	gen.debug_verbose = false
	add_child(gen)
	var grid = gen.call("_wfc_generate")

	if grid.empty():
		print("[T4] FAIL seed=%d: grid empty" % seed_val)
		_failed += 1
		gen.queue_free()
		return

	var gw = gen.grid_width
	var gd = gen.grid_depth
	var non_empty = []
	for i in range(grid.size()):
		if grid[i] != null and grid[i].variant.id != "EMPTY":
			non_empty.append(i)

	if non_empty.empty():
		print("[T4] FAIL seed=%d: no non-EMPTY cells" % seed_val)
		_failed += 1
		gen.queue_free()
		return

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

	if visited.size() == non_empty.size():
		print("[T4] PASS seed=%d (%d cells in one component)" % [seed_val, non_empty.size()])
		_passed += 1
	else:
		var unreachable = non_empty.size() - visited.size()
		print("[T4] FAIL seed=%d — %d cell(s) unreachable (total=%d component=%d)" % [
			seed_val, unreachable, non_empty.size(), visited.size()])
		_failed += 1

	gen.queue_free()
