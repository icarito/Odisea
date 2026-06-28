extends SceneTree

const OPPOSITE = {0: 2, 1: 3, 2: 0, 3: 1}
const DIR_VEC = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

func _init():
	var mst_gen = load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
	mst_gen.apply_params({"grid_width": 8, "grid_depth": 12, "cell_size": 6.0})
	
	var start_time = OS.get_ticks_usec()
	var grid = mst_gen.generate_grid_data(1234)
	var end_time = OS.get_ticks_usec()
	
	var duration_ms = (end_time - start_time) / 1000.0
	print("Generation took: ", duration_ms, "ms")
	
	if duration_ms > 5.0:
		print("FAILED: Performance target exceeded (>5ms)")
		quit(1)
	
	if grid.size() != 8 * 12:
		print("FAILED: Grid size mismatch")
		quit(1)
	
	var occupied = 0
	var room_count = 0
	for i in range(grid.size()):
		var cell = grid[i]
		if cell != null:
			occupied += 1
			if not cell.has("is_room"):
				print("FAILED: Occupied cell missing is_room metadata")
				quit(1)
			if bool(cell["is_room"]):
				room_count += 1
			# Access dict format: cell["variant"]["id"]
			var v = cell["variant"]
			var vid = v["id"]
			if vid == "EMPTY": continue
			var conn = v["connections"]
			var c_count = 0
			for c in conn: if c: c_count += 1
			if c_count == 0:
				print("FAILED: Occupied cell has no connections")
				quit(1)
			_validate_port_alignment(grid, i, mst_gen.grid_width, mst_gen.grid_depth)
	
	print("Occupied cells: ", occupied)
	if occupied < 10:
		print("FAILED: Too few occupied cells")
		quit(1)
	if room_count < 5 or room_count > 8:
		print("FAILED: is_room count out of expected seed range: ", room_count)
		quit(1)
	if not _is_connected(grid, mst_gen.grid_width, mst_gen.grid_depth):
		print("FAILED: MST occupied cells are not one connected component")
		quit(1)

	print("SUCCESS: MST Generator verified")
	quit(0)

func _validate_port_alignment(grid: Array, i: int, gw: int, gd: int) -> void:
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
		if abs(my_port - their_port) > 0.01:
			print("FAILED: Port mismatch at %d dir %d: %.2f != %.2f" % [i, dir, my_port, their_port])
			quit(1)

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
