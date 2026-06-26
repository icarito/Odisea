extends GdUnitTestSuite

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

func test_mst_generation():
	var mst_gen = load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
	mst_gen.apply_params({"grid_width": 8, "grid_depth": 12, "cell_size": 6.0})

	var start_time = OS.get_ticks_usec()
	var grid = mst_gen.generate_grid_data(1234)
	var end_time = OS.get_ticks_usec()

	var duration_ms = (end_time - start_time) / 1000.0
	print("MST Generation took: ", duration_ms, "ms")

	assert_bool(duration_ms < 20.0).is_true()
	assert_int(grid.size()).is_equal(8 * 12)

	var occupied = 0
	var room_count = 0
	for i in range(grid.size()):
		var cell = grid[i]
		if cell != null:
			occupied += 1
			assert_bool(cell.has("is_room")).is_true()
			if bool(cell["is_room"]):
				room_count += 1
			# MST Generator serializes to dicts — use bracket notation (Godot 3)
			var v = cell["variant"]
			var vid = v["id"]
			if vid == "EMPTY":
				continue
			var conn = v["connections"]
			var c_count = 0
			for c in conn:
				if c: c_count += 1
			assert_int(c_count).is_greater(0)
			_assert_port_alignment(grid, i, mst_gen.grid_width, mst_gen.grid_depth)

	assert_int(occupied).is_greater(10)
	assert_int(room_count).is_greater_equal(5)
	assert_int(room_count).is_less_equal(8)
	assert_bool(_is_connected(grid, mst_gen.grid_width, mst_gen.grid_depth)).is_true()

func _assert_port_alignment(grid: Array, i: int, gw: int, gd: int) -> void:
	var cell = grid[i]
	var v = cell["variant"]
	var cx = i % gw
	var cy = i / gw
	for dir in [0, 1, 2, 3]:
		if not bool(v["connections"][dir]):
			continue
		var dv = DIR_VEC[dir]
		var nx = cx + int(dv.x)
		var ny = cy + int(dv.y)
		if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
			continue
		var ni = ny * gw + nx
		var nb = grid[ni]
		if nb == null:
			continue
		var nv = nb["variant"]
		if not bool(nv["connections"][OPPOSITE[dir]]):
			continue
		var my_port = float(cell["base_height"]) + float(v["port_heights"][dir])
		var their_port = float(nb["base_height"]) + float(nv["port_heights"][OPPOSITE[dir]])
		assert_float(my_port).is_equal_approx(their_port, 0.01)

func _is_connected(grid: Array, gw: int, gd: int) -> bool:
	var start := -1
	var occupied := 0
	for i in range(grid.size()):
		if grid[i] != null and grid[i]["variant"]["id"] != "EMPTY":
			occupied += 1
			if start < 0:
				start = i
	if start < 0:
		return false
	var visited := {}
	var q := [start]
	visited[start] = true
	while not q.empty():
		var curr = q.pop_front()
		var cx = curr % gw
		var cy = curr / gw
		var cv = grid[curr]["variant"]
		for dir in [0, 1, 2, 3]:
			if not bool(cv["connections"][dir]):
				continue
			var dv = DIR_VEC[dir]
			var nx = cx + int(dv.x)
			var ny = cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni = ny * gw + nx
			if visited.has(ni) or grid[ni] == null:
				continue
			var nv = grid[ni]["variant"]
			if nv["id"] == "EMPTY" or not bool(nv["connections"][OPPOSITE[dir]]):
				continue
			visited[ni] = true
			q.push_back(ni)
	return visited.size() == occupied
